from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.features.order_history import authenticated_customer,CustomerScope,get_db

def test_confirmation_and_replay():
 db=MagicMock();c=db.cursor.return_value.__enter__.return_value
 app.dependency_overrides[get_db]=lambda:db
 app.dependency_overrides[authenticated_customer]=lambda:CustomerScope(8)
 try:
  with TestClient(app) as client:
   path='/api/v1/order-history/customer/1/purchase-confirmation'
   c.fetchone.side_effect=[{'order_status':'COMPLETED','pickup_branch_id':3,'purchase_confirmed_at':None},{'pickup_id':1},None,{'purchase_confirmed_at':'DB-TIME'}]
   r=client.post(path,json={});assert r.status_code==200
   assert r.json()['data']['purchase_confirmed_at']=='DB-TIME'
   assert c.execute.call_args_list[0].args[1]==(1,8)
   db.commit.assert_called_once()
   c.execute.reset_mock()
   c.fetchone.side_effect=[{'order_status':'COMPLETED','purchase_confirmed_at':'DB-TIME'}]
   assert client.post(path,json={}).status_code==200
   assert len(c.execute.call_args_list)==1
 finally:app.dependency_overrides.clear()

@pytest.mark.parametrize('order,receipt,status',[(None,None,404),({'order_status':'READY_FOR_PICKUP'},None,409),({'order_status':'COMPLETED','pickup_branch_id':3,'purchase_confirmed_at':None},None,409)])
def test_invalid_confirmation(order,receipt,status):
 db=MagicMock();c=db.cursor.return_value.__enter__.return_value;c.fetchone.side_effect=[order,receipt]
 app.dependency_overrides[get_db]=lambda:db;app.dependency_overrides[authenticated_customer]=lambda:CustomerScope(8)
 try:
  with TestClient(app) as client:assert client.post('/api/v1/order-history/customer/1/purchase-confirmation').status_code==status
  db.commit.assert_not_called();db.rollback.assert_called()
 finally:app.dependency_overrides.clear()
