from datetime import datetime
from copy import deepcopy
import pytest
import json
from pymysql import OperationalError
from backend.tests.test_purchase_requisition_edit import client as edit_client


@pytest.fixture
def client(edit_client):
    c,db,cursor,state,employee,_=edit_client
    employee['permissions'].append('PROCUREMENT_APPROVE_TEAM_LEAD')
    employee['employee_id']=99  # Approver need not be the author.
    state['header']['requisition_status']='PENDING_TEAM_LEAD'
    state['approvals']={1:dict(purchase_approval_id=1,purchase_requisition_id=40,
        approval_sequence=1,approval_status='PENDING',role_code='TEAM_LEAD',is_active=1),
        2:dict(purchase_approval_id=2,purchase_requisition_id=40,approval_sequence=2,
        approval_status='PENDING',role_code='DIRECTOR',is_active=1)}
    state['audit_logs']=[]
    snapshot=deepcopy(state)
    db.rollback.side_effect=lambda: (state.clear(),state.update(deepcopy(snapshot)))
    original_execute=cursor.execute.side_effect
    original_fetch=cursor.fetchone.side_effect
    def execute(query,params):
        if query.startswith('UPDATE purchase_approvals SET approval_status=%s'):
            state['approvals'][params[3]].update(approval_status=params[0],
                approver_employee_id=params[1],approval_comment=params[2],decided_at=datetime(2026,10,10,14))
        elif query.startswith("UPDATE purchase_approvals SET approval_status='WAIVED'"):
            state['approvals'][params[1]].update(approval_status='WAIVED',approver_employee_id=None,
                approval_comment=params[0],decided_at=datetime(2026,10,10,14))
        elif query.startswith('UPDATE purchase_requisitions SET requisition_status='):
            if state.get('fail'): raise OperationalError(2000,'private failure')
            state['header']['requisition_status']=params[0]
        elif query.startswith('INSERT INTO audit_logs'):
            if state.get('fail_audit'): raise OperationalError(2000,'private audit failure')
            state['audit_logs'].append({'actor_employee_id':params[0], 'action_code':params[1],
                'entity_type':params[2], 'entity_id':params[3], 'after_data':json.loads(params[5])})
            cursor.lastrowid=10
        else: original_execute(query,params)
    def fetch():
        query,params=cursor.execute.call_args.args
        if query.startswith('SELECT purchase_requisition_id FROM purchase_approvals'):
            return state['approvals'].get(params[0])
        if 'FROM purchase_approvals' in query:
            return state['approvals'].get(params[2] if 'JOIN approval_workflow_steps' in query else params[0])
        if 'FROM audit_logs WHERE entity_type=' in query:
            return {'audit_log_id':10} if state['audit_logs'] else None
        if query.startswith('SELECT created_at FROM audit_logs'):
            return {'created_at':datetime(2026,10,11,12)}
        if 'FROM manufacturers' in query:
            return {'manufacturer_id':1,'manufacturer_name':'manufacturer'}
        return original_fetch()
    original_fetchall=cursor.fetchall.side_effect
    def fetchall():
        if cursor.execute.call_args.args[0].startswith('SELECT pv.product_variant_id FROM product_variants'):
            return [] if state.get('inactive_product') else [{'product_variant_id':i['product_variant_id']} for i in state['items']]
        return original_fetchall()
    cursor.execute.side_effect=execute
    cursor.fetchone.side_effect=fetch
    cursor.fetchall.side_effect=fetchall
    yield c,db,cursor,state,employee


def body(c):
    return {'revision':c.get('/api/v1/purchase-requisitions/40').json()['data']['revision'],'comment':'checked'}


@pytest.mark.parametrize('action,status,next_status', [('approve','APPROVED','PENDING_DIRECTOR'),('reject','REJECTED','REJECTED')])
def test_decision_records_verified_employee_and_advances_atomically(client,action,status,next_status):
    c,db,cursor,state,_=client
    request=body(c)
    response=c.post(f'/api/v1/purchase-approvals/1/{action}',json=request)
    assert response.status_code==200,response.text
    result=response.json()['data']
    assert result['approver_employee_id']==99
    assert result['approval_status']==status
    assert result['requisition_status']==next_status
    assert result['decided_at'] and result['approval_comment']=='checked'
    assert state['approvals'][2]['approval_status']==('PENDING' if action=='approve' else 'WAIVED')
    db.commit.assert_called_once()
    assert c.post(f'/api/v1/purchase-approvals/1/{action}',json=request).status_code==409


@pytest.mark.parametrize('case,code', [('permission',403),('director',403),('stale',409),('processed',409),('missing',404),('blank',400),('forged',400)])
def test_invalid_decision_never_writes(client,case,code):
    c,db,cursor,state,employee=client
    request=body(c)
    if case=='permission':employee['permissions']=[]
    elif case=='director':state['approvals'][1]['role_code']='DIRECTOR'
    elif case=='stale':request['revision']='a'*64
    elif case=='processed':state['header']['requisition_status']='PENDING_DIRECTOR'
    elif case=='missing':state['approvals'].clear()
    elif case=='blank':request['comment']='   '
    elif case=='forged':request['approver_employee_id']=15
    response=c.post('/api/v1/purchase-approvals/1/reject',json=request)
    assert response.status_code==code,response.text
    db.commit.assert_not_called()
    assert not any(call.args[0].startswith('UPDATE') for call in cursor.execute.call_args_list)


def test_partial_write_failure_rolls_back_all_decisions(client):
    c,db,_,state,_=client
    request=body(c)
    state['fail']=True
    response=c.post('/api/v1/purchase-approvals/1/reject',json=request)
    assert response.status_code==500
    assert 'private failure' not in response.text
    assert state['header']['requisition_status']=='PENDING_TEAM_LEAD'
    assert all(a['approval_status']=='PENDING' for a in state['approvals'].values())
    db.commit.assert_not_called()
    db.rollback.assert_called_once()
