from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.features.order_history import CustomerScope, authenticated_customer, get_db

BODY = {'request_id': 'test-request', 'return_reason_code': 'OTHER', 'return_reason': 'test reason'}
ORDER = {'order_status': 'COMPLETED', 'pickup_branch_id': 3, 'purchase_confirmed_at': None}

@pytest.fixture
def context():
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    previous = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[authenticated_customer] = lambda: CustomerScope(8)
    try:
        with TestClient(app) as client:
            yield client, db, cursor
    finally:
        app.dependency_overrides.clear()
        app.dependency_overrides.update(previous)

def ready(cursor):
    cursor.fetchone.side_effect = [{'customer_id': 8}, ORDER, None, {'pickup_id': 1}, None, None]
    cursor.fetchall.return_value = [{'order_item_id': 2, 'quantity': 3}, {'order_item_id': 4, 'quantity': 1}]
    cursor.lastrowid = 9

def test_full_order_and_single_commit(context):
    client, db, cursor = context
    ready(cursor)
    response = client.post('/api/v1/order-history/customer/1/returns', json=BODY)
    assert response.status_code == 201
    item_calls = [call for call in cursor.execute.call_args_list if 'INSERT INTO return_items' in call.args[0]]
    assert [call.args[1] for call in item_calls] == [(9, 2, 3), (9, 4, 1)]
    assert cursor.execute.call_args_list[1].args[1] == (1, 8)
    assert 'FOR UPDATE' in cursor.execute.call_args_list[1].args[0]
    assert not any('UPDATE payments' in call.args[0] or 'UPDATE orders' in call.args[0] for call in cursor.execute.call_args_list)
    db.commit.assert_called_once()

@pytest.mark.parametrize('order', [None, {**ORDER, 'order_status': 'PAID'}, {**ORDER, 'purchase_confirmed_at': 'TIME'}])
def test_ownership_receipt_and_confirmation(context, order):
    client, db, cursor = context
    cursor.fetchone.side_effect = [{'customer_id': 8}, order, None]
    response = client.post('/api/v1/order-history/customer/1/returns', json=BODY)
    assert response.status_code == (404 if order is None else 409)
    db.commit.assert_not_called()
    db.rollback.assert_called_once()

def test_replay_and_changed_payload(context):
    client, db, cursor = context
    prior = {'entity_id': 9, 'after_data': {'order_id': 1, 'return_reason_code': 'OTHER', 'return_reason': 'test reason'}}
    cursor.fetchone.side_effect = [{'customer_id': 8}, ORDER, prior]
    assert client.post('/api/v1/order-history/customer/1/returns', json=BODY).json()['data']['return_request_id'] == 9
    cursor.fetchone.side_effect = [{'customer_id': 8}, ORDER, prior]
    assert client.post('/api/v1/order-history/customer/1/returns', json={**BODY, 'return_reason': 'changed'}).status_code == 409
    db.commit.assert_not_called()

@pytest.mark.parametrize('receipt,existing,refund', [(None,None,None), ({'pickup_id':1},{'return_request_id':2},None), ({'pickup_id':1},None,{'refund_id':2})])
def test_missing_receipt_or_duplicate(context, receipt, existing, refund):
    client, db, cursor = context
    cursor.fetchone.side_effect = [{'customer_id':8}, ORDER, None, receipt, existing, refund]
    assert client.post('/api/v1/order-history/customer/1/returns', json=BODY).status_code == 409
    db.commit.assert_not_called()

def test_item_failure_rolls_back(context):
    client, db, cursor = context
    ready(cursor)
    cursor.execute.side_effect = lambda sql, args: (_ for _ in ()).throw(RuntimeError('test')) if 'INSERT INTO return_items' in sql else None
    assert client.post('/api/v1/order-history/customer/1/returns', json=BODY).status_code == 500
    db.commit.assert_not_called()
    db.rollback.assert_called_once()

def test_active_return_blocks_confirmation(context):
    client, db, cursor = context
    cursor.fetchone.side_effect = [ORDER, {'pickup_id':1}, {'return_request_id':2}]
    assert client.post('/api/v1/order-history/customer/1/purchase-confirmation').status_code == 409
    db.commit.assert_not_called()

def test_missing_authentication(context):
    client, _, cursor = context
    app.dependency_overrides.pop(authenticated_customer)
    assert client.post('/api/v1/order-history/customer/1/returns', json=BODY).status_code == 401
    cursor.execute.assert_not_called()

@pytest.mark.parametrize('body', [{**BODY, 'return_reason': ' '}, {**BODY, 'return_reason_code': 'UNKNOWN'}, {**BODY, 'items': []}])
def test_invalid_input(context, body):
    client, _, cursor = context
    assert client.post('/api/v1/order-history/customer/1/returns', json=body).status_code == 400
    cursor.execute.assert_not_called()
