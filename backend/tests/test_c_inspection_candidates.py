from unittest.mock import MagicMock
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from backend.features import order_history as c

@pytest.fixture
def api():
    db=MagicMock();cur=db.cursor.return_value.__enter__.return_value
    cur.fetchone.return_value={'total_count':0};cur.fetchall.return_value=[]
    app=FastAPI();app.include_router(c.router,prefix='/api/v1')
    app.dependency_overrides[c.authorized_dispatch]=lambda:c.DispatchScope((3,),('PAID',))
    app.dependency_overrides[c.get_db]=lambda:db
    return TestClient(app),db,cur

def test_inspection_list_filters_arrived_uninspected_and_stable_sort(api):
    client,db,cur=api
    r=client.get('/api/v1/order-history/staff/arrival-candidates?stage=inspection')
    assert r.status_code==200 and r.json()['data']==[]
    sql=cur.execute.call_args_list[1].args[0]
    assert "f.fulfillment_status IN ('ARRIVED','INSPECTING')" in sql and 'f.completed_at IS NULL' in sql
    assert 'ORDER BY f.arrived_at DESC,f.fulfillment_id DESC' in sql
    assert cur.execute.call_args_list[1].args[1]==(3,20,0)
    db.commit.assert_not_called()

def test_nonmember_branch_is_blocked(api):
    client,db,cur=api
    assert client.get('/api/v1/order-history/staff/arrival-candidates?stage=inspection&branch_id=9').status_code==403
    cur.execute.assert_not_called()

def test_unknown_stage_is_rejected(api):
    client,db,cur=api
    assert client.get('/api/v1/order-history/staff/arrival-candidates?stage=unknown').status_code==400

def test_inspection_detail_checks_branch_and_reuses_item_snapshot(api):
    client,db,cur=api
    cur.fetchone.return_value={'order_id':1,'branch_id':3,'fulfillment_id':7}
    cur.fetchall.return_value=[{'product_name':'test','quantity':1}]
    response=client.get('/api/v1/order-history/staff/inspection-candidates/7')
    assert response.status_code==200 and response.json()['data']['items'][0]['quantity']==1
    assert "f.fulfillment_status IN ('ARRIVED','INSPECTING')" in cur.execute.call_args_list[0].args[0]

def test_foreign_detail_is_404_without_items_query(api):
    client,db,cur=api
    cur.fetchone.return_value={'order_id':1,'branch_id':9,'fulfillment_id':7}
    assert client.get('/api/v1/order-history/staff/inspection-candidates/7').status_code==404
    assert cur.execute.call_count==1
