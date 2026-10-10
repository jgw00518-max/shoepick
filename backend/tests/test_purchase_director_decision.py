from copy import deepcopy
import pytest
from backend.tests.test_purchase_approval_decision import client as team_client, body
from backend.tests.test_purchase_requisition_edit import client as edit_client


@pytest.fixture
def client(team_client):
    c,db,cursor,state,employee=team_client
    employee['permissions']=['PROCUREMENT_APPROVE_DIRECTOR']
    state['header']['requisition_status']='PENDING_DIRECTOR'
    state['approvals'][1].update(approval_status='APPROVED',approver_employee_id=88)
    snapshot=deepcopy(state)
    db.commit.side_effect=lambda: (snapshot.clear(),snapshot.update(deepcopy(state)))
    db.rollback.side_effect=lambda: (state.clear(),state.update(deepcopy(snapshot)))
    yield c,db,cursor,state,employee


@pytest.mark.parametrize('action,status',[('approve','APPROVED'),('reject','REJECTED')])
def test_director_finishes_approval_and_preserves_team_result(client,action,status):
    c,db,_,state,_=client
    request=body(c)
    if action=='approve':request['comment']=''
    path=f'/api/v1/purchase-approvals/2/{action}?stage=DIRECTOR'
    response=c.post(path,json=request)
    assert response.status_code==200,response.text
    data=response.json()['data']
    assert data['requisition_status']==('ORDERED' if action=='approve' else status)
    assert data['approval_status']==status
    assert data['approver_employee_id']==99
    assert data['decided_at']
    assert state['approvals'][1]['approval_status']=='APPROVED'
    assert state['approvals'][1]['approver_employee_id']==88
    if action=='approve':
        assert data['manufacturer_order']['order_number']=='PO-000040'
        assert data['manufacturer_order']['transmission_status']=='NOT_SENT'
        assert len(state['audit_logs'])==1
        log=state['audit_logs'][0]
        assert log['actor_employee_id']==99
        assert log['action_code']=='PROCUREMENT_ORDER_PLACED'
        assert log['after_data']['manufacturer_id']==1
        assert log['after_data']['items'][0]['requested_quantity']==100
    else:
        assert data['manufacturer_order'] is None
        assert state['audit_logs']==[]
    db.commit.assert_called_once()
    assert c.post(path,json=request).status_code==409
    assert len(state['audit_logs'])==(1 if action=='approve' else 0)


@pytest.mark.parametrize('case,code',[
    ('team_pending',409),('team_rejected',409),('team_missing',409),
    ('wrong_state',409),('wrong_role',403),('inactive_role',403),
    ('team_permission_only',403),('stale',409),('blank',400),('forged',400)])
def test_director_cannot_skip_team_or_submit_invalid_decision(client,case,code):
    c,db,cursor,state,employee=client
    request=body(c)
    if case=='team_pending':state['approvals'][1]['approval_status']='PENDING'
    elif case=='team_rejected':state['approvals'][1]['approval_status']='REJECTED'
    elif case=='team_missing':del state['approvals'][1]
    elif case=='wrong_state':state['header']['requisition_status']='PENDING_TEAM_LEAD'
    elif case=='wrong_role':state['approvals'][2]['role_code']='TEAM_LEAD'
    elif case=='inactive_role':state['approvals'][2]['is_active']=0
    elif case=='team_permission_only':employee['permissions']=['PROCUREMENT_APPROVE_TEAM_LEAD']
    elif case=='stale':request['revision']='a'*64
    elif case=='blank':request['comment']='  '
    elif case=='forged':request['approver_employee_id']=88
    response=c.post('/api/v1/purchase-approvals/2/reject?stage=DIRECTOR',json=request)
    assert response.status_code==code,response.text
    db.commit.assert_not_called()
    assert not any(call.args[0].startswith('UPDATE') for call in cursor.execute.call_args_list)


def test_director_failure_rolls_back_decision(client):
    c,db,_,state,_=client
    request=body(c)
    state['fail']=True
    response=c.post('/api/v1/purchase-approvals/2/approve?stage=DIRECTOR',json=request)
    assert response.status_code==500
    assert state['approvals'][2]['approval_status']=='PENDING'
    assert state['header']['requisition_status']=='PENDING_DIRECTOR'
    assert state['approvals'][1]['approval_status']=='APPROVED'
    assert state['audit_logs']==[]
    db.commit.assert_not_called()
    db.rollback.assert_called_once()


@pytest.mark.parametrize('case', ['audit_failure','existing_order','inactive_product','no_manufacturer','mixed_manufacturers','no_items'])
def test_failed_auto_order_rolls_back_director_approval(client,case):
    c,db,_,state,_=client
    if case=='audit_failure':state['fail_audit']=True
    elif case=='existing_order':state['audit_logs'].append({'existing':True})
    elif case=='inactive_product':state['inactive_product']=True
    elif case=='no_manufacturer':state['items'][0]['manufacturer_id']=None
    elif case=='mixed_manufacturers':
        second=deepcopy(state['items'][0])
        second.update(product_variant_id=13,purchase_requisition_item_id=2,manufacturer_id=2)
        state['items'].append(second)
    else:state['items'].clear()
    request=body(c)
    response=c.post('/api/v1/purchase-approvals/2/approve?stage=DIRECTOR',json=request)
    assert response.status_code==(500 if case=='audit_failure' else 409),response.text
    assert state['approvals'][2]['approval_status']=='PENDING'
    assert state['header']['requisition_status']=='PENDING_DIRECTOR'
    db.commit.assert_not_called()
    db.rollback.assert_called_once()
