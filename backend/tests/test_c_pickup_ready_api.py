from unittest.mock import MagicMock
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from backend.features import order_history as c

@pytest.fixture
def api(monkeypatch):
    db=MagicMock(); db.get_autocommit.return_value=False
    cur=db.cursor.return_value.__enter__.return_value
    cur.fetchone.side_effect=[{'order_id':1},{'pickup_branch_id':3},{'order_id':1,'destination_branch_id':3},None,None]
    employee={'employee_id':4,'roles':[{'role_code':'BRANCH_STAFF'}],'branches':[{'branch_id':3}]}
    d=MagicMock(); record=MagicMock(return_value={'order_id':1,'pickup_id':8,'order_status':'READY_FOR_PICKUP'})
    monkeypatch.setattr(c,'prepare_pickup_holdings',d); monkeypatch.setattr(c,'record_staff_pickup_ready',record)
    app=FastAPI();app.include_router(c.router,prefix='/api/v1')
    app.dependency_overrides[c.current_employee]=lambda:employee
    app.dependency_overrides[c.get_db]=lambda:db
    return TestClient(app),db,cur,employee,d,record

def post(client):
    return client.post('/api/v1/order-history/staff/fulfillments/7/ready',json={'request_id':'KEY','confirmed':True})

def test_success_chain_and_single_commit(api):
    client,db,cur,employee,d,record=api
    tracker=MagicMock();tracker.attach_mock(d,'d');tracker.attach_mock(record,'c');tracker.attach_mock(db.commit,'commit')
    assert post(client).json()['data']['completed'] is True
    assert [x[0] for x in tracker.mock_calls]==['d','c','commit']
    d.assert_called_once_with(db,order_id=1,fulfillment_id=7,branch_id=3)

@pytest.mark.parametrize('stage',['d','c','audit','commit'])
def test_failure_rollback(api,stage):
    client,db,cur,employee,d,record=api
    if stage=='d': d.side_effect=RuntimeError('failed')
    elif stage=='c': record.side_effect=RuntimeError('failed')
    elif stage=='commit': db.commit.side_effect=RuntimeError('failed')
    else:
        def execute(sql,args):
            if sql.startswith('INSERT'):raise RuntimeError('failed')
        cur.execute.side_effect=execute
    assert post(client).status_code==500
    db.rollback.assert_called_once()
    if stage!='commit':db.commit.assert_not_called()

def test_replay_no_inventory_or_record_write(api):
    client,db,cur,employee,d,record=api
    cur.fetchone.side_effect=[{'order_id':1},{'pickup_branch_id':3},{'order_id':1,'destination_branch_id':3},
        {'after_data':{'request':{'fulfillment_id':7,'confirmed':True},'result':{'completed':True}}}]
    assert post(client).json()['data']['replayed'] is True
    d.assert_not_called();record.assert_not_called();db.commit.assert_not_called()

@pytest.mark.parametrize('foreign',[True,False])
def test_scope_blocks_before_inventory(api,foreign):
    client,db,cur,employee,d,record=api
    if foreign:employee['branches']=[]
    else:employee['roles']=[{'role_code':'HQ_STAFF'}]
    assert post(client).status_code==403
    d.assert_not_called();record.assert_not_called()
