from datetime import datetime
import pytest
from pymysql import OperationalError
from backend.tests.test_purchase_requisition_edit import client as edit_client


@pytest.fixture
def client(edit_client):
    c,db,cursor,state,employee,variants=edit_client
    employee['permissions'].append('PROCUREMENT_REQUISITION_SUBMIT')
    state.update(approvals=[],steps=[{'step_order':1,'required_role_id':3,'role_code':'TEAM_LEAD','is_active':1},
        {'step_order':2,'required_role_id':4,'role_code':'DIRECTOR','is_active':1}],workflow=True,fail_approval=False)
    old_execute=cursor.execute.side_effect
    old_fetchone=cursor.fetchone.side_effect
    old_fetchall=cursor.fetchall.side_effect
    def execute(query,params):
        if query.startswith('INSERT INTO purchase_approvals'):
            if state['fail_approval'] and state['approvals']: raise OperationalError(2000,'private SQL')
            state['approvals'].append({'purchase_requisition_id':params[0],'approval_sequence':params[1],
                'required_role_id':params[2],'approval_status':'PENDING'})
        elif query.startswith("UPDATE purchase_requisitions SET requisition_status="):
            state['header'].update(requisition_status='PENDING_TEAM_LEAD',submitted_at=datetime(2026,10,10,13))
        else: return old_execute(query,params)
    def fetchone():
        query=cursor.execute.call_args.args[0]
        if 'FROM approval_workflows' in query: return {'approval_workflow_id':1} if state['workflow'] else None
        return old_fetchone()
    def fetchall():
        query=cursor.execute.call_args.args[0]
        if 'FROM approval_workflow_steps' in query:return state['steps']
        if 'FROM purchase_approvals' in query:return state['approvals']
        if 'WHERE pv.is_active=1' in query:
            return [v for v in variants.values() if v['variant_active'] and v['product_active']
                and v['product_variant_id'] in cursor.execute.call_args.args[1]]
        return old_fetchall()
    cursor.execute.side_effect=execute
    cursor.fetchone.side_effect=fetchone
    cursor.fetchall.side_effect=fetchall
    yield c,db,cursor,state,employee,variants


def request(c):
    return {'revision':c.get('/api/v1/purchase-requisitions/40').json()['data']['revision']}


def test_submit_creates_two_pending_steps_atomically_and_stops_retry(client):
    c,db,cursor,state,*_=client
    body=request(c)
    response=c.post('/api/v1/purchase-requisitions/40/submit',json=body)
    assert response.status_code==200
    assert response.json()['data']['requisition_status']=='PENDING_TEAM_LEAD'
    assert response.json()['data']['submitted_at'] is not None
    assert [a['approval_sequence'] for a in state['approvals']]==[1,2]
    assert all(a['approval_status']=='PENDING' for a in state['approvals'])
    db.commit.assert_called_once()
    assert c.post('/api/v1/purchase-requisitions/40/submit',json=body).status_code==409
    assert len(state['approvals'])==2
    assert any(call.args[0].endswith('FOR UPDATE') for call in cursor.execute.call_args_list)


@pytest.mark.parametrize('case',['non_draft','stale','missing_workflow','wrong_steps','existing_approval','empty_items','inactive_product'])
def test_invalid_submit_does_not_write(client,case):
    c,db,cursor,state,_,variants=client
    body=request(c)
    if case=='non_draft':state['header']['requisition_status']='APPROVED'
    elif case=='stale':state['header']['title']='changed elsewhere'
    elif case=='missing_workflow':state['workflow']=False
    elif case=='wrong_steps':state['steps'][0]['is_active']=0
    elif case=='existing_approval':state['approvals'].append({'purchase_approval_id':99})
    elif case=='empty_items':state['items'].clear();body=request(c)
    else:variants[12]['variant_active']=0
    response=c.post('/api/v1/purchase-requisitions/40/submit',json=body)
    assert response.status_code==409
    assert not any(call.args[0].startswith(('INSERT','UPDATE')) for call in cursor.execute.call_args_list)
    db.commit.assert_not_called()


def test_other_author_and_missing_submit_permission_are_rejected(client):
    c,db,_,_,employee,*_=client
    body=request(c)
    employee['employee_id']=99
    employee['permissions'].append('PROCUREMENT_APPROVE_DIRECTOR')
    assert c.post('/api/v1/purchase-requisitions/40/submit',json=body).status_code==403
    employee['permissions']=['PROCUREMENT_REQUISITION_CREATE']
    assert c.post('/api/v1/purchase-requisitions/40/submit',json=body).status_code==403
    db.commit.assert_not_called()


def test_approval_failure_rolls_back_submission(client):
    c,db,_,state,*_=client
    body=request(c)
    state['fail_approval']=True
    response=c.post('/api/v1/purchase-requisitions/40/submit',json=body)
    assert response.status_code==500
    assert 'private' not in response.text
    assert state['header']['requisition_status']=='DRAFT'
    db.commit.assert_not_called()
    db.rollback.assert_called()


def test_invalid_body_cannot_supply_approver_or_status(client):
    c,db,_,_,*_=client
    assert c.post('/api/v1/purchase-requisitions/40/submit',json={'revision':'a'*64,'approver_employee_id':15}).status_code==400
    assert c.post('/api/v1/purchase-requisitions/40/submit',json={}).status_code==400
    db.commit.assert_not_called()
