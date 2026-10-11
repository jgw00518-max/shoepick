from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.features.order_history import authorized_dispatch,DispatchScope,get_db

@pytest.mark.parametrize('route,table,sort',[('arrival-candidates','fulfillments','f.shipped_at DESC,f.fulfillment_id DESC'),('pickup-candidates','pickups','p.ready_at DESC,p.pickup_id DESC')])
def test_candidate_scope_paging_and_filters(route,table,sort):
 db=MagicMock();c=db.cursor.return_value.__enter__.return_value;c.fetchone.return_value={'total_count':0};c.fetchall.return_value=[]
 app.dependency_overrides[get_db]=lambda:db
 app.dependency_overrides[authorized_dispatch]=lambda:DispatchScope((3,),('PAID',))
 try:
  with TestClient(app) as client:
   path='/api/v1/order-history/staff/'+route
   r=client.get(path+'?branch_id=3&page=2');assert r.status_code==200 and r.json()['data']==[]
   sql,args=c.execute.call_args.args
   assert sort in sql and table in sql and args==(3,3,20,20)
   assert client.get(path+'?branch_id=4').status_code==403
   assert client.get(path+'?page=0').status_code==400
   app.dependency_overrides[authorized_dispatch]=lambda:DispatchScope((),('PAID',),True)
   assert client.get(path).status_code==200
   assert c.execute.call_args.args[1]==(20,0)
   app.dependency_overrides.pop(authorized_dispatch)
   assert client.get(path).status_code==401
  db.commit.assert_not_called()
 finally:app.dependency_overrides.clear()

@pytest.mark.parametrize('arrival',[True,False])
def test_detail_scope_and_snapshot(arrival):
 from backend.features.order_history import read_pickup_candidate_detail,OrderReadError
 db=MagicMock();c=db.cursor.return_value.__enter__.return_value
 c.fetchone.return_value={'branch_id':4,'order_id':1}
 with pytest.raises(OrderReadError):read_pickup_candidate_detail(db,record_id=7,arrival=arrival,scope=DispatchScope((3,),('PAID',)))
 c.fetchall.assert_not_called()
 c.fetchone.return_value={'branch_id':3,'order_id':1}
 c.fetchall.return_value=[{'product_name':'snapshot','quantity':2}]
 result=read_pickup_candidate_detail(db,record_id=7,arrival=arrival,scope=DispatchScope((3,),('PAID',)))
 assert result['data']['items'][0]['product_name']=='snapshot'
 assert ('fulfillment_items' if arrival else 'order_items') in c.execute.call_args.args[0]
 db.commit.assert_not_called()
