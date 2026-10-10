from datetime import datetime
import json
from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.features import manufacturer_orders as feature
from backend.features.authentication import current_employee


@pytest.fixture
def client():
    db=MagicMock();cursor=db.cursor.return_value.__enter__.return_value
    employee={'employee_id':15,'permissions':[],'roles':[{'role_code':'HQ_STAFF'}]}
    snapshot=dict(order_number='PO-000040',purchase_requisition_id=40,title='original title',reason='original reason',
        manufacturer_id=1,manufacturer_name='original manufacturer',transmission_status='NOT_SENT',
        total_requested_quantity=100,items=[dict(purchase_requisition_item_id=1,product_variant_id=12,
            product_code='SKU',product_name='original product',color_name='black',size_mm=250,requested_quantity=100)])
    row=dict(audit_log_id=10,after_data=json.dumps(snapshot),registered_at=datetime(2026,10,11,12),
        registered_by_employee_id=99,registered_by_name='director',requested_by_employee_id=15,
        requested_by_name='author',requisition_status='ORDERED')
    state={'rows':[row]}
    def rows():
        sql,params=cursor.execute.call_args.args
        result=state['rows']
        if 'pr.requested_by_employee_id=%s' in sql:
            result=[r for r in result if r['requested_by_employee_id']==params[2]]
        if 'a.audit_log_id=%s' in sql:result=[r for r in result if r['audit_log_id']==params[-1]]
        return result
    cursor.fetchone.side_effect=lambda: {'total_count':len(rows())} if cursor.execute.call_args.args[0].startswith('SELECT COUNT') else next(iter(rows()),None)
    cursor.fetchall.side_effect=rows
    app.dependency_overrides[feature.get_db]=lambda:db
    app.dependency_overrides[current_employee]=lambda:employee
    try:
        with TestClient(app) as c:yield c,db,cursor,employee,state
    finally:app.dependency_overrides.clear()


def test_own_list_and_detail_use_snapshot_and_never_write(client):
    c,db,cursor,_,_=client
    response=c.get('/api/v1/manufacturer-orders')
    assert response.status_code==200,response.text
    assert response.json()['pagination']=={'page':1,'page_size':20,'total_count':1}
    assert response.json()['data'][0]['manufacturer_name']=='original manufacturer'
    sql,params=cursor.execute.call_args.args
    assert 'pr.requested_by_employee_id=%s' in sql
    assert params==('PURCHASE_REQUISITION','PROCUREMENT_ORDER_PLACED',15,20,0)
    response=c.get('/api/v1/manufacturer-orders/10')
    assert response.json()['data']['items'][0]['product_name']=='original product'
    assert response.json()['data']['reason']=='original reason'
    assert 'JOIN products' not in cursor.execute.call_args.args[0]
    db.commit.assert_not_called()


def test_hq_staff_cannot_see_other_authors_even_with_query_role(client):
    c,_,_,employee,_=client
    employee['employee_id']=22
    assert c.get('/api/v1/manufacturer-orders?role=EXECUTIVE&employee_id=15').json()['data']==[]
    assert c.get('/api/v1/manufacturer-orders/10').status_code==404


@pytest.mark.parametrize('role',['TEAM_LEAD','DIRECTOR','EXECUTIVE','ADMIN'])
def test_management_reads_other_authors(client,role):
    c,_,cursor,employee,_=client
    employee['employee_id']=22;employee['roles']=[{'role_code':role}]
    assert len(c.get('/api/v1/manufacturer-orders').json()['data'])==1
    assert 'pr.requested_by_employee_id=%s' not in cursor.execute.call_args.args[0]
    assert c.get('/api/v1/manufacturer-orders/10').status_code==200


@pytest.mark.parametrize('role',['BRANCH_STAFF','BRANCH_MANAGER','OTHER'])
def test_branch_and_unknown_role_cannot_read(client,role):
    c,_,cursor,employee,_=client
    employee['roles']=[{'role_code':role}]
    assert c.get('/api/v1/manufacturer-orders').status_code==403
    assert c.get('/api/v1/manufacturer-orders/10').status_code==403
    cursor.execute.assert_not_called()


def test_sort_search_and_page_are_bound(client):
    c,_,cursor,*_=client
    assert c.get('/api/v1/manufacturer-orders',params={'order':'asc','page':2,'keyword':'%_!'}).status_code==200
    sql,params=cursor.execute.call_args.args
    assert 'ORDER BY a.created_at ASC,a.audit_log_id ASC' in sql
    assert '%_!' not in sql
    assert params[-5:]==('%!%!_!!%','%!%!_!!%','%!%!_!!%',20,20)


@pytest.mark.parametrize('path',['?page=0','?page_size=101','?order=bad','/0'])
def test_invalid_query_returns_400(client,path):
    c,_,cursor,*_=client
    assert c.get('/api/v1/manufacturer-orders'+path).status_code==400
    cursor.execute.assert_not_called()


def test_missing_and_unauthenticated(client):
    c,_,_,_,state=client
    state['rows']=[]
    assert c.get('/api/v1/manufacturer-orders/10').status_code==404
    del app.dependency_overrides[current_employee]
    assert c.get('/api/v1/manufacturer-orders').status_code==401
