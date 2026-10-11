from unittest.mock import MagicMock
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from backend.features import order_history as c


@pytest.fixture
def api():
    db = MagicMock()
    db.get_autocommit.return_value = False
    cur = db.cursor.return_value.__enter__.return_value
    cur.rowcount = 1
    order = {'order_status': 'SHIPPING', 'pickup_branch_id': 3}
    delivery = {'order_id': 1, 'destination_branch_id': 3, 'fulfillment_status': 'ARRIVED',
                'shipped_at': 'time', 'arrived_at': 'time', 'inspected_at': None, 'completed_at': None}
    cur.fetchone.side_effect = [{'order_id': 1}, order, delivery, None, {'inspected_at': 'DB time'}]
    cur.fetchall.side_effect = [[{'order_item_id': 9, 'quantity': 2}],
                              [{'order_id': 1, 'order_item_id': 9, 'quantity': 2}]]
    employee = {'employee_id': 4, 'roles': [{'role_code': 'BRANCH_STAFF'}], 'branches': [{'branch_id': 3}]}
    app = FastAPI()
    app.include_router(c.router, prefix='/api/v1')
    app.dependency_overrides[c.current_employee] = lambda: employee
    app.dependency_overrides[c.get_db] = lambda: db
    return TestClient(app), db, cur, employee, order, delivery


def post(client, **changes):
    return client.post('/api/v1/order-history/staff/fulfillments/7/inspection',
                       json={'request_id': 'KEY', 'all_items_normal': True, **changes})


def test_inspection_is_not_ready_or_inventory_change(api):
    client, db, cur, *_ = api
    result = post(client)
    assert result.status_code == 200
    assert result.json()['data']['fulfillment_status'] == 'INSPECTING'
    assert result.json()['data']['inspected_at'] == 'DB time'
    assert not any(x.args[0].startswith(('UPDATE orders', 'UPDATE inventory', 'INSERT INTO pickup')) for x in cur.execute.call_args_list)
    db.commit.assert_called_once()


@pytest.mark.parametrize('role', ['HQ_STAFF', 'DIRECTOR'])
def test_other_role_cannot_inspect(api, role):
    client, db, cur, employee, *_ = api
    employee['roles'] = [{'role_code': role}]
    assert post(client).status_code == 403
    cur.execute.assert_not_called()


def test_foreign_branch(api):
    client, db, cur, employee, *_ = api
    employee['branches'] = []
    assert post(client).status_code == 403
    db.commit.assert_not_called()


@pytest.mark.parametrize('status', ['IN_TRANSIT', 'READY_FOR_PICKUP', 'COMPLETED'])
def test_invalid_state(api, status):
    client, db, cur, employee, order, delivery = api
    delivery['fulfillment_status'] = status
    assert post(client).status_code == 409
    db.commit.assert_not_called()


def test_quantity_mismatch(api):
    client, db, cur, *_ = api
    cur.fetchall.side_effect = [[{'order_item_id': 9, 'quantity': 2}],
                              [{'order_id': 1, 'order_item_id': 9, 'quantity': 1}]]
    assert post(client).status_code == 409
    db.commit.assert_not_called()


def test_replay_does_not_write(api):
    client, db, cur, employee, order, delivery = api
    stored = {'request': {'fulfillment_id': 7, 'all_items_normal': True},
              'result': {'fulfillment_id': 7, 'fulfillment_status': 'INSPECTING'}}
    cur.fetchone.side_effect = [{'order_id': 1}, order, delivery, {'after_data': stored}]
    assert post(client).json()['data']['replayed'] is True
    assert not any(x.args[0].startswith(('UPDATE', 'INSERT')) for x in cur.execute.call_args_list)
    db.commit.assert_not_called()


def test_failure_rolls_back(api):
    client, db, cur, *_ = api
    def execute(sql, args):
        if sql.startswith('INSERT INTO fulfillment_status_history'):
            raise RuntimeError('failure')
    cur.execute.side_effect = execute
    assert post(client).status_code == 500
    db.rollback.assert_called_once()
    db.commit.assert_not_called()


def test_false_confirmation_and_missing_auth(api):
    client, db, cur, *_ = api
    assert post(client, all_items_normal=False).status_code == 400
    client.app.dependency_overrides.pop(c.current_employee)
    assert post(client).status_code == 401
    cur.execute.assert_not_called()


def test_request_key_conflict_prevents_inspection_write(api):
    client, db, cur, employee, order, delivery = api
    cur.fetchone.side_effect = [{'order_id': 1}, order, delivery,
                               {'after_data': {'request': {'fulfillment_id': 99, 'all_items_normal': True}, 'result': {}}}]
    response = post(client)
    assert response.status_code == 409
    assert response.json()['error']['code'] == 'ALREADY_PROCESSED'
    assert all(x.args[0].startswith('SELECT') for x in cur.execute.call_args_list)
    db.commit.assert_not_called()


@pytest.mark.parametrize('failure_point', ['audit', 'commit'])
def test_inspection_late_failure_rolls_back(api, failure_point):
    client, db, cur, *_ = api
    if failure_point == 'commit':
        db.commit.side_effect = RuntimeError('commit failed')
    else:
        def execute(sql, args):
            if sql.startswith('INSERT INTO audit_logs'):
                raise RuntimeError('audit failed')
        cur.execute.side_effect = execute
    assert post(client).status_code == 500
    db.rollback.assert_called_once()
    if failure_point == 'audit':
        db.commit.assert_not_called()
