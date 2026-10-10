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
    db=MagicMock();cursor=db.cursor.return_value.__enter__.return_value
    employee={'employee_id':15,'permissions':[],'roles':[{'role_code':'EXECUTIVE'}]}
    row=dict(purchase_requisition_id=40,title='전체 결재 현황',employee_name='다른 작성자',branch_name=None,
      requisition_status='REJECTED',submitted_at=datetime(2026,10,10,12),team_approval_status='APPROVED',
      team_approver_name='팀장',director_approval_status='REJECTED',director_approver_name='이사',item_count=2,total_requested_quantity=100)
    state={'rows':[row],'total_count':21}
    cursor.fetchone.side_effect=lambda:{'total_count':state['total_count']}
    cursor.fetchall.side_effect=lambda:[] if cursor.execute.call_args.args[0].startswith('SELECT pa.approval_sequence') else state['rows']
    document=RequisitionDetail(purchase_requisition_id=40,requested_by_employee_id=24,branch_id=None,
      approval_workflow_id=1,title='전체 결재 현황',reason='구매 사유',requisition_status='REJECTED',
      submitted_at=datetime(2026,10,10,12),created_at=datetime(2026,10,10,11),revision='a'*64,items=[])
    read=MagicMock(return_value=SimpleNamespace(data=document));monkeypatch.setattr(feature,'_read_requisition_detail',read)
    app.dependency_overrides[feature.get_db]=lambda:db
    app.dependency_overrides[current_employee]=lambda:employee
    try:
      with TestClient(app) as c:yield c,db,cursor,employee,state,document,read
    finally:app.dependency_overrides.clear()

def test_monitor_pagination_excludes_unsubmitted_and_drafts_without_duplicates(client):
    c,db,cursor,*_=client
    r=c.get('/api/v1/purchase-approvals/overview?page=2')
    assert r.status_code==200
    assert r.json()['pagination']=={'page':2,'page_size':20,'total_count':21}
    assert r.json()['data'][0]['team_approval_status']=='APPROVED'
    assert r.json()['data'][0]['requisition_status']=='REJECTED'
    sql,params=cursor.execute.call_args.args
    assert "pr.requisition_status<>'DRAFT'" in sql and 'pr.submitted_at IS NOT NULL' in sql
    assert 'ta.approval_sequence=1' in sql and 'da.approval_sequence=2' in sql
    assert 'ORDER BY pr.submitted_at DESC,pr.purchase_requisition_id DESC' in sql
    assert params==(20,20)
    db.commit.assert_not_called()

def test_monitor_filters_are_bound_and_date_range_includes_whole_last_day(client):
    c,_,cursor,*_=client
    r=c.get('/api/v1/purchase-approvals/overview',params={'status':'REJECTED','keyword':'%_!',
      'submitted_from':'2026-10-01','submitted_to':'2026-10-10'})
    assert r.status_code==200
    sql,params=cursor.execute.call_args.args
    assert params==('REJECTED','%!%!_!!%','%!%!_!!%',datetime(2026,10,1),datetime(2026,10,10,23,59,59,999999),20,0)
    assert '%_!' not in sql

@pytest.mark.parametrize('query',['status=DRAFT','page=0','page_size=101','submitted_from=bad',
  'submitted_from=2026-10-10&submitted_to=2026-10-01'])
def test_invalid_monitor_filters(client,query):
    c,_,cursor,*_=client
    assert c.get('/api/v1/purchase-approvals/overview?'+query).status_code==400
    cursor.execute.assert_not_called()

def test_monitor_access_uses_server_role_or_audit_permission(client):
    c,_,cursor,employee,*_=client
    employee['roles']=[{'role_code':'HQ_STAFF'}]
    employee['permissions']=['PROCUREMENT_APPROVE_TEAM_LEAD']
    assert c.get('/api/v1/purchase-approvals/overview?role=EXECUTIVE').status_code==403
    cursor.execute.assert_not_called()
    employee['permissions']=['AUDIT_LOG_READ']
    assert c.get('/api/v1/purchase-approvals/overview').status_code==200
    del app.dependency_overrides[current_employee]
    assert c.get('/api/v1/purchase-approvals/overview').status_code==401

def test_monitor_detail_checks_publication_after_authorized_role(client):
    c,_,_,_,_,document,read=client
    assert c.get('/api/v1/purchase-approvals/overview/40').status_code==200
    assert read.call_args.kwargs['allow_monitor'] is True
    document.requisition_status='DRAFT'
    assert c.get('/api/v1/purchase-approvals/overview/40').status_code==404
    document.requisition_status='CANCELED';document.submitted_at=None
    assert c.get('/api/v1/purchase-approvals/overview/40').status_code==404


def test_monitor_ascending_order_and_invalid_direction(client):
    c,_,cursor,*_=client
    assert c.get('/api/v1/purchase-approvals/overview?order=asc').status_code==200
    assert 'ORDER BY pr.submitted_at ASC,pr.purchase_requisition_id ASC' in cursor.execute.call_args.args[0]
    cursor.execute.reset_mock()
    assert c.get('/api/v1/purchase-approvals/overview?order=bad').status_code==400
    cursor.execute.assert_not_called()
