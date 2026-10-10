from datetime import datetime
from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from pymysql import OperationalError
from backend.main import app
from backend.features import purchase_requisitions as feature
from backend.features.authentication import current_employee


@pytest.fixture
def client():
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    header = dict(purchase_requisition_id=40,requested_by_employee_id=15,branch_id=None,
        approval_workflow_id=1,title='기존 제목',reason='기존 사유',requisition_status='DRAFT',
        created_at=datetime(2026,10,10,12),submitted_at=None)
    variants = {i: dict(product_variant_id=i,product_code=f'SKU-{i}',product_name='운동화',
        color_name='검정',size_mm=250,manufacturer_id=1,manufacturer_name='제조사',
        variant_active=1,product_active=1) for i in (12,13)}
    state = {'header':header, 'items':[{**variants[12], 'purchase_requisition_item_id':1,'requested_quantity':100}],
             'fail_item':False}
    employee = {'employee_id':15,'permissions':['PROCUREMENT_REQUISITION_CREATE'],'branches':[]}

    def execute(query, params):
        if query.startswith('UPDATE purchase_requisitions'):
            header.update(title=params[0],reason=params[1])
        elif query.startswith('DELETE FROM purchase_requisition_items'):
            state['items'].clear()
        elif query.startswith('INSERT INTO purchase_requisition_items'):
            if state['fail_item']: raise OperationalError(2000,'private database error')
            state['items'].append({**variants[params[1]],'purchase_requisition_item_id':len(state['items'])+10,
                'requested_quantity':params[2]})

    def fetchone():
        query = cursor.execute.call_args.args[0]
        return {'manufacturer_id':1} if 'FROM manufacturers' in query else state['header']

    def fetchall():
        query = cursor.execute.call_args.args[0]
        if 'FROM purchase_requisition_items' in query:
            return [{k:v for k,v in row.items() if k not in ('variant_active','product_active')} for row in state['items']]
        return [variants[i] for i in cursor.execute.call_args.args[1] if i in variants]

    cursor.execute.side_effect=execute
    cursor.fetchone.side_effect=fetchone
    cursor.fetchall.side_effect=fetchall
    app.dependency_overrides[feature.get_db]=lambda: db
    app.dependency_overrides[current_employee]=lambda: employee
    try:
        with TestClient(app) as c: yield c,db,cursor,state,employee,variants
    finally: app.dependency_overrides.clear()


def body(c):
    return {'manufacturer_id':1,'title':' 수정 제목 ','reason':'수정 사유',
        'items':[{'product_variant_id':12,'requested_quantity':50}, {'product_variant_id':13,'requested_quantity':20}],
        'revision':c.get('/api/v1/purchase-requisitions/40').json()['data']['revision']}


def test_detail_and_patch_replace_all_items_keep_document_identity(client):
    c,db,cursor,state,*_=client
    request=body(c)
    r=c.patch('/api/v1/purchase-requisitions/40',json=request)
    assert r.status_code==200
    data=r.json()['data']
    assert data['purchase_requisition_id']==40
    assert data['title']=='수정 제목'
    assert data['requested_by_employee_id']==15
    assert data['approval_workflow_id']==1
    assert data['requisition_status']=='DRAFT'
    assert [i['requested_quantity'] for i in data['items']]==[50,20]
    assert data['revision']!=request['revision']
    assert any(call.args[0].endswith('FOR UPDATE') for call in cursor.execute.call_args_list)
    db.commit.assert_called_once()


@pytest.mark.parametrize('status',['SUBMITTED','PENDING_TEAM_LEAD','APPROVED','REJECTED','ORDERED','CANCELED'])
def test_non_draft_cannot_be_modified(client,status):
    c,db,cursor,state,*_=client
    request=body(c)
    state['header']['requisition_status']=status
    assert c.patch('/api/v1/purchase-requisitions/40',json=request).status_code==409
    assert not any(call.args[0].startswith(('UPDATE','DELETE','INSERT')) for call in cursor.execute.call_args_list)
    db.commit.assert_not_called()


def test_stale_revision_is_rejected(client):
    c,db,cursor,state,*_=client
    request=body(c)
    state['header']['title']='다른 기기에서 수정'
    r=c.patch('/api/v1/purchase-requisitions/40',json=request)
    assert r.status_code==409
    assert r.json()['error']['code']=='CONFLICT'
    db.commit.assert_not_called()


def test_other_author_cannot_modify_even_with_review_permissions(client):
    c,db,cursor,state,employee,*_=client
    request=body(c)
    employee['employee_id']=99
    employee['permissions'].append('PROCUREMENT_APPROVE_DIRECTOR')
    assert c.get('/api/v1/purchase-requisitions/40').status_code==200
    assert c.patch('/api/v1/purchase-requisitions/40',json=request).status_code==403
    db.commit.assert_not_called()


def test_detail_is_scoped_and_missing_document_returns_404(client):
    c,_,_,state,employee,*_=client
    employee['employee_id']=99
    assert c.get('/api/v1/purchase-requisitions/40').status_code==403
    state['header']=None
    assert c.get('/api/v1/purchase-requisitions/40').status_code==404


def test_invalid_patch_and_missing_permissions(client):
    c,db,_,_,employee,*_=client
    request=body(c)
    assert c.patch('/api/v1/purchase-requisitions/40',json=request|{'requested_by_employee_id':99}).status_code==400
    assert c.patch('/api/v1/purchase-requisitions/40',json=request|{'items':[]}).status_code==400
    employee['permissions']=[]
    assert c.patch('/api/v1/purchase-requisitions/40',json=request).status_code==403
    db.commit.assert_not_called()


def test_item_failure_rolls_back_title_and_item_replacement(client):
    c,db,_,state,*_=client
    request=body(c)
    state['fail_item']=True
    r=c.patch('/api/v1/purchase-requisitions/40',json=request)
    assert r.status_code==500
    assert 'private' not in r.text
    db.commit.assert_not_called()
    db.rollback.assert_called()
