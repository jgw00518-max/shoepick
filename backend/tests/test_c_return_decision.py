from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.features.order_history import current_employee, get_db

BODY = {'request_id':'KEY','decision':'APPROVED','rejection_reason':None}
PATH = '/api/v1/order-history/staff/returns/2/decision'

@pytest.fixture
def context():
    db = MagicMock(); c = db.cursor.return_value.__enter__.return_value
    employee = {'employee_id':1,'roles':[{'role_code':'HQ_STAFF'}],'branches':[]}
    previous = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[current_employee] = lambda: employee
    try:
        with TestClient(app) as client: yield client, db, c, employee
    finally:
        app.dependency_overrides.clear(); app.dependency_overrides.update(previous)

@pytest.mark.parametrize('decision,reason,inspection_decision',[('APPROVED',None,'ACCEPTED'),('REJECTED','test reason','REJECTED')])
def test_decision_atomic_and_no_refund(context,decision,reason,inspection_decision):
    client,db,c,_=context
    c.fetchone.side_effect=[{'request_status':'INSPECTING'},None,{'after_sales_inspection_id':9,'inspection_decision':'PENDING'}]
    response=client.post(PATH,json={**BODY,'decision':decision,'rejection_reason':reason})
    assert response.status_code==200
    assert response.json()['data']['request_status']==decision
    calls=c.execute.call_args_list
    inspection_update=next(call for call in calls if call.args[0].startswith('UPDATE after_sales_inspections'))
    return_update=next(call for call in calls if call.args[0].startswith('UPDATE return_requests'))
    assert inspection_update.args[1]==(inspection_decision,9)
    assert return_update.args[1]==(decision,reason,1,2)
    assert 'processed_at=CURRENT_TIMESTAMP' in return_update.args[0]
    assert not any('UPDATE orders' in call.args[0] or 'INSERT INTO refunds' in call.args[0] for call in calls)
    db.commit.assert_called_once()

@pytest.mark.parametrize('role',['BRANCH_STAFF','BRANCH_MANAGER','DIRECTOR'])
def test_forbidden_roles(context,role):
    client,db,c,e=context; e['roles']=[{'role_code':role}]
    assert client.post(PATH,json=BODY).status_code==403
    c.execute.assert_not_called(); db.commit.assert_not_called()

@pytest.mark.parametrize('state',['REQUESTED','APPROVED','REJECTED','COMPLETED'])
def test_state_cannot_change_or_reverse(context,state):
    client,db,c,_=context;c.fetchone.side_effect=[{'request_status':state},None]
    assert client.post(PATH,json=BODY).status_code==409
    db.commit.assert_not_called();db.rollback.assert_called_once()

@pytest.mark.parametrize('inspection',[None,{'inspection_decision':'ACCEPTED'}])
def test_pending_hq_inspection_required(context,inspection):
    client,db,c,_=context;c.fetchone.side_effect=[{'request_status':'INSPECTING'},None,inspection]
    assert client.post(PATH,json=BODY).status_code==409
    db.commit.assert_not_called()

def test_replay_and_conflict(context):
    client,db,c,_=context
    prior={'after_data':{'return_request_id':2,'decision':'APPROVED','rejection_reason':None}}
    for body,status in [(BODY,200),({**BODY,'decision':'REJECTED','rejection_reason':'reason'},409)]:
        c.fetchone.side_effect=[{'request_status':'APPROVED'},prior]
        assert client.post(PATH,json=body).status_code==status
    db.commit.assert_not_called()

def test_failure_rolls_back_inspection_and_status(context):
    client,db,c,_=context
    c.fetchone.side_effect=[{'request_status':'INSPECTING'},None,{'after_sales_inspection_id':9,'inspection_decision':'PENDING'}]
    c.execute.side_effect=lambda sql,args: (_ for _ in ()).throw(RuntimeError('test')) if 'INSERT INTO audit_logs' in sql else None
    assert client.post(PATH,json=BODY).status_code==500
    db.commit.assert_not_called();db.rollback.assert_called_once()

@pytest.mark.parametrize('body',[{**BODY,'decision':'REJECTED'}, {**BODY,'decision':'REJECTED','rejection_reason':' '},{**BODY,'rejection_reason':'unused'},{**BODY,'decision':'OTHER'}])
def test_invalid_input(context,body):
    client,db,c,_=context
    assert client.post(PATH,json=body).status_code==400
    c.execute.assert_not_called()

def test_missing_auth(context):
    client,_,c,_=context;app.dependency_overrides.pop(current_employee)
    assert client.post(PATH,json=BODY).status_code==401
    c.execute.assert_not_called()

def test_missing_return(context):
    client,_,c,_=context;c.fetchone.return_value=None
    assert client.post(PATH,json=BODY).status_code==404
