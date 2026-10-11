from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.features.order_history import current_employee, get_db

@pytest.fixture
def context():
    db = MagicMock()
    c = db.cursor.return_value.__enter__.return_value
    employee = {'employee_id':1, 'roles':[{'role_code':'HQ_STAFF'}], 'branches':[]}
    previous = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[current_employee] = lambda: employee
    try:
        with TestClient(app) as client:
            yield client, db, c, employee
    finally:
        app.dependency_overrides.clear()
        app.dependency_overrides.update(previous)

def test_hq_all_and_stable_pagination(context):
    client, db, c, _ = context
    c.fetchone.return_value = {'total_count':0}
    c.fetchall.return_value = []
    response = client.get('/api/v1/order-history/staff/returns?page=2')
    assert response.status_code == 200
    assert response.json()['data'] == []
    assert c.execute.call_args_list[0].args[1] == ()
    sql, args = c.execute.call_args_list[1].args
    assert 'r.requested_at DESC, r.return_request_id DESC LIMIT' in sql
    assert args == (20,20)
    db.commit.assert_not_called()

@pytest.mark.parametrize('role', ['BRANCH_STAFF','BRANCH_MANAGER'])
def test_branch_scope_and_forbidden_filter(context, role):
    client, _, c, employee = context
    employee['roles'] = [{'role_code':role}]
    employee['branches'] = [{'branch_id':3}]
    c.fetchone.return_value = {'total_count':0}
    c.fetchall.return_value = []
    assert client.get('/api/v1/order-history/staff/returns').status_code == 200
    assert c.execute.call_args_list[0].args[1] == (3,)
    c.execute.reset_mock()
    assert client.get('/api/v1/order-history/staff/returns?branch_id=4').status_code == 403
    c.execute.assert_not_called()

@pytest.mark.parametrize('role',['TEAM_LEAD','DIRECTOR','EXECUTIVE'])
def test_other_roles_denied(context,role):
    client, _, c, employee = context
    employee['roles'] = [{'role_code':role}]
    assert client.get('/api/v1/order-history/staff/returns').status_code == 403
    c.execute.assert_not_called()

def test_detail_scope_and_records(context):
    client, _, c, employee = context
    employee['roles'] = [{'role_code':'BRANCH_STAFF'}]
    employee['branches'] = [{'branch_id':3}]
    c.fetchone.return_value = {'return_request_id':2,'order_id':1}
    c.fetchall.side_effect = [[{'quantity':2}],[],[{'refund_status':'PROCESSING'}]]
    result = client.get('/api/v1/order-history/staff/returns/2')
    assert result.status_code == 200
    assert result.json()['data']['refunds'][0]['refund_status'] == 'PROCESSING'
    assert c.execute.call_args_list[0].args[1] == (2,3)
    assert 'after_sales_inspection_id' in c.execute.call_args_list[2].args[0]
    assert 'provider_refund_key' not in c.execute.call_args_list[3].args[0]

def test_other_branch_detail_hidden(context):
    client, _, c, _ = context
    c.fetchone.return_value = None
    assert client.get('/api/v1/order-history/staff/returns/2').status_code == 404
    c.fetchall.assert_not_called()

@pytest.mark.parametrize('query',['page=0','page_size=101','branch_id=0'])
def test_invalid_input(context,query):
    client, _, c, _ = context
    assert client.get('/api/v1/order-history/staff/returns?'+query).status_code == 400
    c.execute.assert_not_called()

def test_missing_auth(context):
    client, _, c, _ = context
    app.dependency_overrides.pop(current_employee)
    assert client.get('/api/v1/order-history/staff/returns').status_code == 401
    c.execute.assert_not_called()
