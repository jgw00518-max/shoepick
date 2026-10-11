from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.features.order_history import current_employee, get_db

BODY = dict(request_id='KEY', inspection_stage='BRANCH', received_product=True,
            has_wear_marks=False, has_product_damage=False, has_customer_fault=False,
            components_complete=True, packaging_intact=True, has_product_defect=False,
            is_wrong_item=False, inspection_notes='test notes')

@pytest.fixture
def context():
    db = MagicMock(); c = db.cursor.return_value.__enter__.return_value
    employee = {'employee_id':1,'roles':[{'role_code':'BRANCH_STAFF'}],'branches':[{'branch_id':3}]}
    prior = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[current_employee] = lambda: employee
    try:
        with TestClient(app) as client: yield client, db, c, employee
    finally:
        app.dependency_overrides.clear(); app.dependency_overrides.update(prior)

@pytest.mark.parametrize('status', ['REQUESTED','COLLECTING','INSPECTING'])
def test_first_observation_only(context,status):
    client,db,c,_ = context
    c.fetchone.side_effect=[{'request_status':status,'branch_id':3},None,None]; c.lastrowid=9
    assert client.post('/api/v1/order-history/staff/returns/2/inspection',json=BODY).status_code==201
    sqls=[call.args[0] for call in c.execute.call_args_list]
    assert any("request_status='INSPECTING'" in sql for sql in sqls)
    assert not any('UPDATE payments' in sql or 'UPDATE inventory' in sql for sql in sqls)
    assert 'inspection_decision' not in next(sql for sql in sqls if 'INSERT INTO after_sales_inspections' in sql)
    db.commit.assert_called_once()

@pytest.mark.parametrize('role,stage,branch,status', [('HQ_STAFF','HEADQUARTERS',4,201),('HQ_STAFF','BRANCH',3,403),('BRANCH_MANAGER','BRANCH',3,201),('BRANCH_STAFF','BRANCH',4,403),('DIRECTOR','HEADQUARTERS',3,403)])
def test_execution_scope(context,role,stage,branch,status):
    client,_,c,e=context; e['roles']=[{'role_code':role}]
    c.fetchone.side_effect=[{'request_status':'REQUESTED','branch_id':branch},None,None]
    c.lastrowid=1
    assert client.post('/api/v1/order-history/staff/returns/2/inspection',json={**BODY,'inspection_stage':stage}).status_code==status

def test_replay_and_payload_conflict(context):
    client,db,c,_=context
    prior={'entity_id':9,'after_data':{'return_request_id':2,**{k:v for k,v in BODY.items() if k!='request_id'}}}
    for body,status in [(BODY,200),({**BODY,'inspection_notes':'changed'},409)]:
        c.fetchone.side_effect=[{'request_status':'COMPLETED','branch_id':3},prior]
        assert client.post('/api/v1/order-history/staff/returns/2/inspection',json=body).status_code==status
    db.commit.assert_not_called()

@pytest.mark.parametrize('state,existing', [('COMPLETED',None),('REJECTED',None),('REQUESTED',{'after_sales_inspection_id':9})])
def test_wrong_state_or_duplicate(context,state,existing):
    client,db,c,_=context; c.fetchone.side_effect=[{'request_status':state,'branch_id':3},None,existing]
    assert client.post('/api/v1/order-history/staff/returns/2/inspection',json=BODY).status_code==409
    db.commit.assert_not_called(); db.rollback.assert_called_once()

def test_transaction_failure(context):
    client,db,c,_=context; c.fetchone.side_effect=[{'request_status':'REQUESTED','branch_id':3},None,None]
    c.execute.side_effect=lambda sql,args: (_ for _ in ()).throw(RuntimeError('test')) if 'INSERT INTO audit_logs' in sql else None
    assert client.post('/api/v1/order-history/staff/returns/2/inspection',json=BODY).status_code==500
    db.commit.assert_not_called();db.rollback.assert_called_once()

@pytest.mark.parametrize('body',[{**BODY,'received_product':False},{**BODY,'inspection_notes':' '},{**BODY,'has_wear_marks':'false'}])
def test_invalid_input(context,body):
    client,_,c,_=context
    assert client.post('/api/v1/order-history/staff/returns/2/inspection',json=body).status_code==400
    c.execute.assert_not_called()
