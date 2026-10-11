from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.features import dashboard as feature
from backend.features.authentication import current_employee

@pytest.fixture
def client():
    db=MagicMock();cursor=db.cursor.return_value.__enter__.return_value
    employee={'employee_id':15,'branches':[{'branch_id':1},{'branch_id':2}]}
    state={'exists':True,'rows':[(1,'INSPECTING',2),(1,'READY_FOR_PICKUP',7),(1,'RECALLING',3),(1,'DAMAGED',1),
        (1,'AWAITING_ARRIVAL',99),(1,'PICKED_UP',50),(1,'RETURNED_TO_HQ',40),(1,'CANCELED',20),(2,'READY_FOR_PICKUP',11)]}
    def fetch():
        query,params=cursor.execute.call_args.args
        if query.startswith('SELECT branch_id'):return {'branch_id':params[0],'branch_name':f'branch-{params[0]}'} if state['exists'] else None
        values=[qty for branch,status,qty in state['rows'] if branch==params[0] and status in params[1:]]
        return {'held_quantity':sum(values),'holding_count':len(values)}
    cursor.fetchone.side_effect=fetch
    app.dependency_overrides[feature.get_db]=lambda:db
    app.dependency_overrides[current_employee]=lambda:employee
    try:
        with TestClient(app) as c:yield c,db,cursor,state,employee
    finally:app.dependency_overrides.clear()

def test_sums_current_physical_quantities_not_history_or_row_count(client):
    c,db,cursor,*_=client
    response=c.get('/api/v1/dashboard/branches/1/inventory')
    assert response.status_code==200,response.text
    assert response.json()['data']=={'branch_id':1,'branch_name':'branch-1','held_quantity':13,'holding_count':4}
    query,params=cursor.execute.call_args.args
    assert 'SUM(quantity)' in query and 'LIMIT' not in query
    assert params==(1,'INSPECTING','READY_FOR_PICKUP','RECALLING','DAMAGED')
    db.commit.assert_not_called()

def test_selected_branch_and_empty_holdings(client):
    c,_,_,state,_=client
    assert c.get('/api/v1/dashboard/branches/2/inventory').json()['data']['held_quantity']==11
    state['rows']=[]
    assert c.get('/api/v1/dashboard/branches/1/inventory').json()['data']['held_quantity']==0

def test_other_branch_is_forbidden_and_inactive_branch_is_missing(client):
    c,_,cursor,state,*_=client
    assert c.get('/api/v1/dashboard/branches/3/inventory').status_code==403
    cursor.execute.assert_not_called()
    state['exists']=False
    assert c.get('/api/v1/dashboard/branches/1/inventory').status_code==404

def test_unauthenticated_and_invalid_branch(client):
    c,_,cursor,*_=client
    assert c.get('/api/v1/dashboard/branches/0/inventory').status_code==400
    cursor.execute.assert_not_called()
    del app.dependency_overrides[current_employee]
    assert c.get('/api/v1/dashboard/branches/1/inventory').status_code==401
