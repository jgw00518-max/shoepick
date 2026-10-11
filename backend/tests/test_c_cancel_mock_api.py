import json
from unittest.mock import MagicMock, patch

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.features import order_history as c


@pytest.fixture
def setup_api():
    db = MagicMock()
    db.get_autocommit.return_value = False
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.fetchone.side_effect = [dict(order_status='PAID',coupon_discount=0,points_used=0),None,None,None]
    app = FastAPI()
    app.include_router(c.router, prefix='/api/v1')
    app.dependency_overrides[c.authenticated_customer] = lambda: c.CustomerScope(8)
    app.dependency_overrides[c.get_db] = lambda: db
    with patch.object(c,'stage_customer_order_cancel_mock',return_value={'refund_id':9}) as stage, \
         patch.object(c,'release_order_inventory') as release:
        yield TestClient(app), db, cursor, stage, release


def post(client, **changes):
    body = dict(request_id='KEY',reason='test')
    body.update(changes)
    return client.post('/api/v1/order-history/customer/1/cancel-mock',json=body)


def test_success_calls_d_before_single_commit_and_records_completion(setup_api):
    client, db, cursor, stage, release = setup_api
    release.side_effect = lambda *a,**k: db.commit.assert_not_called()
    response = post(client)
    assert response.status_code == 200
    assert response.json()['data']['completed'] is True
    stage.assert_called_once_with(db,order_id=1,customer=c.CustomerScope(8),request_id='KEY',reason='test')
    release.assert_called_once_with(db,order_id=1,reason='test')
    db.commit.assert_called_once()
    db.rollback.assert_not_called()
    assert cursor.execute.call_args_list[0].args[1] == (1,8)


@pytest.mark.parametrize('discount,points',[(1,0),(0,1)])
def test_benefit_orders_are_blocked(setup_api,discount,points):
    client,db,cursor,stage,release = setup_api
    cursor.fetchone.side_effect = [dict(order_status='PAID',coupon_discount=discount,points_used=points),None,None]
    assert post(client).status_code == 409
    stage.assert_not_called(); release.assert_not_called()
    db.commit.assert_not_called(); db.rollback.assert_called_once()


def test_foreign_order_is_404(setup_api):
    client,db,cursor,stage,release = setup_api
    cursor.fetchone.side_effect = [None]
    assert post(client).status_code == 404
    stage.assert_not_called(); release.assert_not_called()


def test_same_request_replay_returns_completion_without_new_work(setup_api):
    client,db,cursor,stage,release = setup_api
    stored = dict(request=dict(order_id=1,reason='test'),result=dict(order_id=1,completed=True,is_mock=True,refund_id=9))
    cursor.fetchone.side_effect = [dict(order_status='CANCELED'),{'after_data':json.dumps(stored)}]
    assert post(client).json()['data']['replayed'] is True
    stage.assert_not_called(); release.assert_not_called(); db.commit.assert_not_called()


def test_key_payload_conflict_is_409(setup_api):
    client,db,cursor,stage,release = setup_api
    cursor.fetchone.side_effect = [dict(order_status='CANCELED'),dict(after_data={'request':dict(order_id=2,reason='test')})]
    assert post(client).status_code == 409
    stage.assert_not_called(); release.assert_not_called()


def test_old_partial_financial_record_is_not_reprocessed(setup_api):
    client,db,cursor,stage,release = setup_api
    cursor.fetchone.side_effect = [dict(order_status='PAID',coupon_discount=0,points_used=0),None,None,{'refund_id':9}]
    assert post(client).status_code == 409
    stage.assert_not_called(); release.assert_not_called()


def test_d_failure_rolls_back_without_success_marker(setup_api):
    client,db,cursor,stage,release = setup_api
    release.side_effect = RuntimeError('simulated failure')
    assert post(client).status_code == 500
    db.rollback.assert_called_once(); db.commit.assert_not_called()
    assert not any(call.args[0].startswith('INSERT INTO audit_logs') for call in cursor.execute.call_args_list)


def test_invalid_body_rejected(setup_api):
    client,db,cursor,stage,release = setup_api
    assert post(client,reason='x'*256).status_code == 400
    stage.assert_not_called(); release.assert_not_called()


def test_missing_authentication_cannot_reach_cancel_code(setup_api):
    client,db,cursor,stage,release = setup_api
    client.app.dependency_overrides.pop(c.authenticated_customer)
    assert post(client).status_code == 401
    stage.assert_not_called(); release.assert_not_called()
