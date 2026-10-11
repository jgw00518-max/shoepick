from datetime import datetime
from types import SimpleNamespace
from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.features import purchase_approvals as feature
from backend.features.authentication import current_employee
from backend.features.purchase_requisitions import RequisitionDetail


@pytest.fixture
def client(monkeypatch):
    db=MagicMock()
    cursor=db.cursor.return_value.__enter__.return_value
    row=dict(purchase_approval_id=1,purchase_requisition_id=40,approval_sequence=1,title='실제 결재 품의',
        employee_name='작성 직원',branch_name=None,requisition_status='PENDING_TEAM_LEAD',approval_status='PENDING',
        submitted_at=datetime(2026,10,10,12),decided_at=None,approval_comment=None,item_count=2,total_requested_quantity=100)
    state={'rows':[row],'detail':row,'count':21}
    cursor.fetchone.side_effect=lambda: {'total_count':state['count']} if cursor.execute.call_args.args[0].startswith('SELECT COUNT') else state['detail']
    steps=[dict(approval_sequence=1,role_code='TEAM_LEAD',role_name='팀장',approval_status='PENDING',
        approver_name=None,approval_comment=None,decided_at=None)]
    cursor.fetchall.side_effect=lambda:steps if cursor.execute.call_args.args[0].startswith('SELECT pa.approval_sequence,r.role_code') else state['rows']
    document=RequisitionDetail(purchase_requisition_id=40,requested_by_employee_id=24,branch_id=None,
        approval_workflow_id=1,title='실제 결재 품의',reason='구매 사유',requisition_status='PENDING_TEAM_LEAD',
        created_at=datetime(2026,10,10,11),submitted_at=datetime(2026,10,10,12),items=[],revision='a'*64)
    monkeypatch.setattr(feature,'_read_requisition_detail',lambda *_:SimpleNamespace(data=document))
    employee={'employee_id':15,'permissions':['PROCUREMENT_APPROVE_TEAM_LEAD']}
    app.dependency_overrides[feature.get_db]=lambda:db
    app.dependency_overrides[current_employee]=lambda:employee
    try:
        with TestClient(app) as c:yield c,db,cursor,state,employee
    finally:app.dependency_overrides.clear()


def test_team_pending_is_paginated_and_excludes_drafts_and_wrong_stage(client):
    c,db,cursor,*_=client
    r=c.get('/api/v1/purchase-approvals/pending?stage=TEAM_LEAD&page=2')
    assert r.status_code==200
    assert r.json()['pagination']=={'page':2,'page_size':20,'total_count':21}
    sql,params=cursor.execute.call_args.args
    assert params==('TEAM_LEAD',1,'PENDING_TEAM_LEAD',20,20)
    assert "pr.requisition_status<>'DRAFT'" in sql and "pa.approval_status='PENDING'" in sql
    assert 'ORDER BY pr.submitted_at DESC,pa.purchase_approval_id DESC' in sql
    db.commit.assert_not_called()


def test_director_pending_requires_team_approval_and_director_permission(client):
    c,_,cursor,_,employee=client
    assert c.get('/api/v1/purchase-approvals/pending?stage=DIRECTOR').status_code==403
    cursor.execute.assert_not_called()
    employee['permissions']=['PROCUREMENT_APPROVE_DIRECTOR']
    assert c.get('/api/v1/purchase-approvals/pending?stage=DIRECTOR').status_code==200
    sql,params=cursor.execute.call_args.args
    assert params==('DIRECTOR',2,'PENDING_DIRECTOR',20,0)
    assert "prior_role.role_code='TEAM_LEAD'" in sql and "prior.approval_status='APPROVED'" in sql


def test_history_is_only_current_employee_and_keeps_result_separate(client):
    c,_,cursor,state,_=client
    state['rows'][0].update(approval_status='APPROVED',requisition_status='REJECTED')
    r=c.get('/api/v1/purchase-approvals/history?stage=TEAM_LEAD&employee_id=999')
    assert r.status_code==200
    assert r.json()['data'][0]['approval_status']=='APPROVED'
    assert r.json()['data'][0]['requisition_status']=='REJECTED'
    sql,params=cursor.execute.call_args.args
    assert params==('TEAM_LEAD',1,15,20,0)
    assert 'pa.approver_employee_id=%s' in sql
    assert "pa.approval_status IN ('APPROVED','REJECTED')" in sql


def test_detail_requires_pending_or_own_history_scope(client):
    c,db,cursor,state,_=client
    r=c.get('/api/v1/purchase-approvals/1?stage=TEAM_LEAD')
    assert r.status_code==200
    assert r.json()['data']['requisition']['reason']=='구매 사유'
    sql,params=cursor.execute.call_args_list[0].args
    assert params==('TEAM_LEAD',1,'PENDING_TEAM_LEAD',15,1)
    assert 'pa.approver_employee_id=%s' in sql
    assert r.json()['data']['steps'][0]['role_code']=='TEAM_LEAD'
    state['detail']=None
    assert c.get('/api/v1/purchase-approvals/999?stage=TEAM_LEAD').status_code==404
    db.commit.assert_not_called()


@pytest.mark.parametrize('query',['stage=ADMIN','stage=TEAM_LEAD&page=0','stage=TEAM_LEAD&page_size=101',''])
def test_invalid_query(client,query):
    c,_,cursor,*_=client
    assert c.get('/api/v1/purchase-approvals/pending?'+query).status_code==400
    cursor.execute.assert_not_called()


def test_missing_permission_and_auth(client):
    c,_,cursor,_,employee=client
    employee['permissions']=['PROCUREMENT_REQUISITION_CREATE']
    assert c.get('/api/v1/purchase-approvals/history?stage=TEAM_LEAD').status_code==403
    del app.dependency_overrides[current_employee]
    assert c.get('/api/v1/purchase-approvals/pending?stage=TEAM_LEAD').status_code==401
    cursor.execute.assert_not_called()


def test_empty_pending(client):
    c,_,_,state,_=client
    state.update(rows=[],count=0)
    r=c.get('/api/v1/purchase-approvals/pending?stage=TEAM_LEAD')
    assert r.status_code==200
    assert r.json()['data']==[] and r.json()['pagination']['total_count']==0


@pytest.mark.parametrize('stage,view',[('TEAM_LEAD','pending'),('DIRECTOR','pending'),('TEAM_LEAD','history'),('DIRECTOR','history')])
def test_stage_sorting_ascending_and_invalid_order(client,stage,view):
    c,_,cursor,_,employee=client
    employee['permissions']=['PROCUREMENT_APPROVE_TEAM_LEAD','PROCUREMENT_APPROVE_DIRECTOR']
    assert c.get(f'/api/v1/purchase-approvals/{view}?stage={stage}&order=asc').status_code==200
    column='pr.submitted_at' if view=='pending' else 'pa.decided_at'
    assert f'ORDER BY {column} ASC,pa.purchase_approval_id ASC' in cursor.execute.call_args.args[0]
    cursor.execute.reset_mock()
    assert c.get(f'/api/v1/purchase-approvals/{view}?stage={stage}&order=bad').status_code==400
    cursor.execute.assert_not_called()
