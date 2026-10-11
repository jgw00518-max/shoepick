from unittest.mock import MagicMock
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from backend.features import order_history as c, order as a

@pytest.fixture
def api(monkeypatch):
    db=MagicMock();db.get_autocommit.return_value=False
    cur=db.cursor.return_value.__enter__.return_value;cur.rowcount=1
    cur.fetchone.side_effect=[{'order_id':1},{'coupon_discount':0,'points_used':0},{'order_id':1,'request_status':'APPROVED'},None,None,None]
    employee={'employee_id':4,'roles':[{'role_code':'HQ_STAFF'}]}
    prepare=MagicMock(return_value={'order_id':1,'return_request_id':7,'employee_id':4,'request_id':'KEY'})
    restore=MagicMock();refund=MagicMock(return_value={'order_id':1,'return_request_id':7,'refund_id':9,'refund_status':'SUCCEEDED','is_mock':True})
    monkeypatch.setattr(c,'prepare_approved_return_refund',prepare)
    monkeypatch.setattr(c,'restore_return_inventory',restore)
    monkeypatch.setattr(a,'refund_return_order_mock',refund)
    app=FastAPI();app.include_router(c.router,prefix='/api/v1')
    app.dependency_overrides[c.current_employee]=lambda:employee
    app.dependency_overrides[c.get_db]=lambda:db
    return TestClient(app),db,cur,employee,prepare,restore,refund

def post(client):
    return client.post('/api/v1/order-history/staff/returns/7/complete-mock',json={'request_id':'KEY','resale_confirmed':True})

def test_success_sequence_and_single_commit(api):
    client,db,cur,employee,prepare,restore,refund=api
    tracker=MagicMock()
    for name,func in [('prepare',prepare),('restore',restore),('refund',refund),('commit',db.commit)]:tracker.attach_mock(func,name)
    assert post(client).json()['data']['completed'] is True
    assert [x[0] for x in tracker.mock_calls]==['prepare','restore','refund','commit']
    assert not any(x.args[0].startswith('UPDATE orders') for x in cur.execute.call_args_list)

@pytest.mark.parametrize('stage',['prepare','restore','refund','audit','commit'])
def test_failure_rolls_back(api,stage):
    client,db,cur,employee,prepare,restore,refund=api
    if stage=='audit':
        def execute(sql,args):
            if sql.startswith('INSERT INTO audit_logs'):raise RuntimeError('failed')
        cur.execute.side_effect=execute
    else:{'prepare':prepare,'restore':restore,'refund':refund,'commit':db.commit}[stage].side_effect=RuntimeError('failed')
    assert post(client).status_code==500
    db.rollback.assert_called_once()
    if stage!='commit':db.commit.assert_not_called()

def test_benefit_blocks_before_restore(api):
    client,db,cur,employee,prepare,restore,refund=api
    cur.fetchone.side_effect=[{'order_id':1},{'coupon_discount':1,'points_used':0},{'order_id':1},None,None]
    assert post(client).status_code==409
    restore.assert_not_called();refund.assert_not_called()

def test_replay_no_new_work(api):
    client,db,cur,employee,prepare,restore,refund=api
    cur.fetchone.side_effect=[{'order_id':1},{'coupon_discount':0,'points_used':0},{'order_id':1},
        {'after_data':{'request':{'return_request_id':7,'resale_confirmed':True},'result':{'completed':True}}}]
    assert post(client).json()['data']['replayed']
    prepare.assert_not_called();restore.assert_not_called();refund.assert_not_called()

def test_wrong_role(api):
    client,db,cur,employee,*_=api
    employee['roles']=[{'role_code':'BRANCH_MANAGER'}]
    assert post(client).status_code==403
    cur.execute.assert_not_called()
