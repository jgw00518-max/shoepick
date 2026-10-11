from unittest.mock import MagicMock, patch
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from backend.features import order_history as c

@pytest.fixture
def api():
    db=MagicMock();db.get_autocommit.return_value=False
    cursor=db.cursor.return_value.__enter__.return_value
    cursor.fetchone.side_effect=[{'order_status':'PAID'},None,None]
    employee={'employee_id':4,'roles':[{'role_code':'HQ_STAFF'}]}
    app=FastAPI();app.include_router(c.router,prefix='/api/v1')
    app.dependency_overrides[c.current_employee]=lambda:employee
    app.dependency_overrides[c.get_db]=lambda:db
    with patch('backend.features.c_dispatch.prepare_order_fulfillment',return_value={'fulfillment_id':7,'fulfillment_number':'TEST'}) as prepare, \
         patch.object(c,'consume_order_inventory') as consume, \
         patch('backend.features.c_dispatch.record_dispatched_fulfillment') as record, \
         patch.object(c,'transition_dispatched_order',return_value={'order_id':1,'order_status':'SHIPPING','fulfillment_id':7}) as transition:
        yield TestClient(app),db,cursor,employee,(prepare,consume,record,transition)

def post(client,**changes):
    return client.post('/api/v1/order-history/staff/dispatch/1/confirm',json={'request_id':'KEY','confirmed':True,**changes})

def test_full_chain_order_single_commit(api):
    client,db,cursor,employee,steps=api
    manager=MagicMock()
    for name,step in zip(('prepare','consume','record','transition'),steps):manager.attach_mock(step,name)
    response=post(client)
    assert response.status_code==200 and response.json()['data']['completed']
    assert [call[0] for call in manager.mock_calls]==['prepare','consume','record','transition']
    steps[1].assert_called_once_with(db,order_id=1,employee_id=4)
    db.commit.assert_called_once();db.rollback.assert_not_called()

@pytest.mark.parametrize('role',['BRANCH_STAFF','BRANCH_MANAGER','TEAM_LEAD','DIRECTOR'])
def test_other_roles_cannot_execute(api,role):
    client,db,cursor,employee,steps=api;employee['roles']=[{'role_code':role}]
    assert post(client).status_code==403
    for step in steps:step.assert_not_called()

@pytest.mark.parametrize('index',[0,1,2,3])
def test_failure_at_any_stage_rolls_back(api,index):
    client,db,cursor,employee,steps=api;steps[index].side_effect=RuntimeError('test failure')
    assert post(client).status_code==500
    db.rollback.assert_called_once();db.commit.assert_not_called()
    for step in steps[index+1:]:step.assert_not_called()

def test_same_request_replay(api):
    client,db,cursor,employee,steps=api
    cursor.fetchone.side_effect=[{'order_status':'SHIPPING'},{'after_data':{'request':{'order_id':1,'confirmed':True},'result':{'order_id':1,'completed':True}}}]
    assert post(client).json()['data']['replayed']
    for step in steps:step.assert_not_called()
    db.commit.assert_not_called()

def test_confirmation_required(api):
    client,db,cursor,employee,steps=api
    assert post(client,confirmed=False).status_code==400
    for step in steps:step.assert_not_called()

def test_missing_authentication_is_blocked(api):
    client,db,cursor,employee,steps=api
    client.app.dependency_overrides.pop(c.current_employee)
    assert post(client).status_code==401
    for step in steps:step.assert_not_called()
