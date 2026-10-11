from unittest.mock import MagicMock
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from backend.features import order_history as c

@pytest.fixture
def api():
 db=MagicMock();db.get_autocommit.return_value=False
 cur=db.cursor.return_value.__enter__.return_value;cur.rowcount=1
 order={'order_status':'SHIPPING','pickup_branch_id':3}
 delivery={'order_id':1,'destination_branch_id':3,'fulfillment_status':'IN_TRANSIT','shipped_at':'time','arrived_at':None}
 cur.fetchone.side_effect=[{'order_id':1},order,delivery,None,{'arrived_at':'DB time'}]
 employee={'employee_id':4,'roles':[{'role_code':'BRANCH_STAFF'}],'branches':[{'branch_id':3}]}
 app=FastAPI();app.include_router(c.router,prefix='/api/v1')
 app.dependency_overrides[c.current_employee]=lambda:employee
 app.dependency_overrides[c.get_db]=lambda:db
 return TestClient(app),db,cur,employee

def post(client):return client.post('/api/v1/order-history/staff/fulfillments/7/arrival',json={'request_id':'KEY','received_product':True})

def test_success_only_records_arrival(api):
 client,db,cur,employee=api
 response=post(client)
 assert response.status_code==200 and response.json()['data']['fulfillment_status']=='ARRIVED'
 assert not any(call.args[0].startswith(('UPDATE orders','UPDATE inventory')) for call in cur.execute.call_args_list)
 db.commit.assert_called_once()

@pytest.mark.parametrize('role',['HQ_STAFF','TEAM_LEAD','DIRECTOR'])
def test_wrong_roles(api,role):
 client,db,cur,employee=api;employee['roles']=[{'role_code':role}]
 assert post(client).status_code==403
 cur.execute.assert_not_called()

def test_wrong_branch(api):
 client,db,cur,employee=api;employee['branches']=[]
 assert post(client).status_code==403
 db.commit.assert_not_called()

def test_failure_rolls_back(api):
 client,db,cur,employee=api
 def execute(sql,args):
  if sql.startswith('INSERT INTO fulfillment_status_history'):raise RuntimeError('failure')
 cur.execute.side_effect=execute
 assert post(client).status_code==500
 db.rollback.assert_called_once();db.commit.assert_not_called()


def test_replayed_arrival_has_no_second_write(api):
 client,db,cur,employee=api
 stored={'request':{'fulfillment_id':7,'received_product':True},
         'result':{'fulfillment_id':7,'fulfillment_status':'ARRIVED'}}
 cur.fetchone.side_effect=[{'order_id':1},{'order_status':'SHIPPING','pickup_branch_id':3},
                          {'order_id':1,'destination_branch_id':3,'fulfillment_status':'ARRIVED','shipped_at':'raw','arrived_at':'raw'},
                          {'after_data':stored}]
 assert post(client).json()['data']['replayed'] is True
 assert all(x.args[0].startswith('SELECT') for x in cur.execute.call_args_list)
 db.commit.assert_not_called()


def test_arrival_request_key_conflict_is_blocked(api):
 client,db,cur,employee=api
 stored={'request':{'fulfillment_id':99,'received_product':True},'result':{}}
 cur.fetchone.side_effect=[{'order_id':1},{'order_status':'SHIPPING','pickup_branch_id':3},
                          {'order_id':1,'destination_branch_id':3,'fulfillment_status':'IN_TRANSIT','shipped_at':'raw','arrived_at':None},
                          {'after_data':stored}]
 response=post(client)
 assert response.status_code==409 and response.json()['error']['code']=='ALREADY_PROCESSED'
 assert all(x.args[0].startswith('SELECT') for x in cur.execute.call_args_list)
 db.commit.assert_not_called()


@pytest.mark.parametrize('failure_point',['audit','commit'])
def test_arrival_late_failure_rolls_back(api,failure_point):
 client,db,cur,employee=api
 if failure_point=='commit':
  db.commit.side_effect=RuntimeError('commit failed')
 else:
  def execute(sql,args):
   if sql.startswith('INSERT INTO audit_logs'):raise RuntimeError('audit failed')
  cur.execute.side_effect=execute
 assert post(client).status_code==500
 db.rollback.assert_called_once()
 if failure_point=='audit':db.commit.assert_not_called()
