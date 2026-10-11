import json
from copy import deepcopy
from datetime import datetime
import pytest
from pymysql import OperationalError
from backend.tests.test_manufacturer_order_read import client as read_client

@pytest.fixture
def client(read_client):
    c,db,cursor,employee,state=read_client
    state['reception']=None
    state.update(receipt=None,movements=[],balances={12:{'on_hand_quantity':20,'reserved_quantity':5,'defective_quantity':2}})
    snapshot=deepcopy(state)
    db.commit.side_effect=lambda:(snapshot.clear(),snapshot.update(deepcopy(state)))
    db.rollback.side_effect=lambda:(state.clear(),state.update(deepcopy(snapshot)))
    original=cursor.fetchone.side_effect
    def fetch():
        sql,params=cursor.execute.call_args.args
        if sql.startswith('SELECT a.entity_id'):
            row=original();return {'entity_id':40} if row else None
        if sql.startswith('SELECT requisition_status,requested_by_employee_id'):
            return state['rows'][0]
        if sql.startswith('SELECT r.audit_log_id'):return state['reception']
        if sql.startswith('SELECT after_data FROM audit_logs'):return state['rows'][0]
        if sql.startswith('SELECT audit_log_id,after_data,created_at FROM audit_logs'):return state['receipt']
        if sql.startswith('SELECT product_variant_id FROM product_variants'):return {'product_variant_id':params[0]}
        if sql.startswith('SELECT inventory_movement_id'):
            return {'inventory_movement_id':1} if any(m[0]==params[2] for m in state['movements']) else None
        if sql.startswith('SELECT on_hand_quantity'):return state['balances'][params[0]]
        if sql.startswith('SELECT created_at FROM audit_logs'):return {'created_at':datetime(2026,10,11,12)}
        if sql.startswith('SELECT a.created_at,e.employee_name'):
            return {'created_at':datetime(2026,10,11,12),'employee_name':'recorder'}
        return original()
    def execute(sql,params):
        if sql.startswith('INSERT INTO headquarters_inventory'):
            state['balances'].setdefault(params[0],{'on_hand_quantity':0,'reserved_quantity':0,'defective_quantity':0})
        elif sql.startswith('UPDATE headquarters_inventory'):
            if state.get('fail_inventory'):raise OperationalError(2000,'private inventory failure')
            state['balances'][params[1]]['on_hand_quantity']=params[0]
        elif sql.startswith('INSERT INTO inventory_movements'):
            state['movements'].append(params)
        if sql.startswith('INSERT INTO audit_logs'):
            if state.get('fail'):raise OperationalError(2000,'private SQL failure')
            if state.get('fail_reception') and params[1]=='PROCUREMENT_ORDER_RECEPTION':
                raise OperationalError(2000,'private reception failure')
            if params[1]=='PROCUREMENT_GOODS_RECEIVED':
                cursor.lastrowid=19
                state['receipt']={'audit_log_id':19,'after_data':params[4],'created_at':datetime(2026,10,11,12)}
                return
            cursor.lastrowid=20
            state['reception']=dict(audit_log_id=20,after_data=params[4],request_id=params[5],
                created_at=datetime(2026,10,11,12),actor_employee_id=params[0],employee_name='recorder')
            state['rows'][0]['reception_data']=json.dumps({'audit_log_id':20,'payload':json.loads(params[4]),
                'recorded_at':'2026-10-11T12:00:00','recorded_by_employee_id':params[0],'recorded_by_name':'recorder'})
    cursor.execute.side_effect=execute;cursor.fetchone.side_effect=fetch
    yield c,db,cursor,employee,state

def body(decision='ACCEPTED'):
    return {'decision':decision,'confirmation_method':'PHONE','comment':'confirmed','request_id':'request_1234567890'}

@pytest.mark.parametrize('decision',['ACCEPTED','REJECTED'])
def test_records_result_and_auto_receives_only_acceptance(client,decision):
    c,db,cursor,_,state=client
    request=body(decision)
    response=c.post('/api/v1/manufacturer-orders/10/reception',json=request)
    assert response.status_code==200,response.text
    assert response.json()['data']['recorded_by_employee_id']==15
    assert response.json()['data']['decision']==decision
    result=c.get('/api/v1/manufacturer-orders/10').json()['data']
    assert result['reception_status']==decision
    assert result['can_record_reception'] is False
    assert result['reception']['comment']=='confirmed'
    assert c.get('/api/v1/manufacturer-orders').json()['data'][0]['reception_status']==decision
    assert c.post('/api/v1/manufacturer-orders/10/reception',json=request).status_code==200
    assert sum(call.args[0].startswith('INSERT INTO audit_logs') for call in cursor.execute.call_args_list)==(2 if decision=='ACCEPTED' else 1)
    assert state['rows'][0]['requisition_status']=='ORDERED'
    assert state['balances'][12]['on_hand_quantity']==(120 if decision=='ACCEPTED' else 20)
    assert state['balances'][12]['reserved_quantity']==5
    assert state['balances'][12]['defective_quantity']==2
    if decision=='ACCEPTED':
        assert response.json()['data']['goods_receipt']['total_received_quantity']==100
        assert len(state['movements'])==1
    else:
        assert response.json()['data']['goods_receipt'] is None
        assert state['movements']==[]
    assert c.post('/api/v1/manufacturer-orders/10/reception',json=request|{'request_id':'another_1234567890'}).status_code==409

@pytest.mark.parametrize('case,code',[('executive',403),('branch',403),('other_author',404),('canceled',409),
    ('blank',400),('forged',400),('invalid_method',400)])
def test_invalid_reception_cannot_write(client,case,code):
    c,db,cursor,employee,state=client
    request=body('REJECTED')
    if case=='executive':employee['roles']=[{'role_code':'EXECUTIVE'}]
    elif case=='branch':employee['roles']=[{'role_code':'BRANCH_STAFF'}]
    elif case=='other_author':employee['employee_id']=33
    elif case=='canceled':state['rows'][0]['requisition_status']='CANCELED'
    elif case=='blank':request['comment']=' '
    elif case=='forged':request['recorded_by_employee_id']=99
    else:request['confirmation_method']='APP'
    response=c.post('/api/v1/manufacturer-orders/10/reception',json=request)
    assert response.status_code==code,response.text
    assert not any(call.args[0].startswith('INSERT') for call in cursor.execute.call_args_list)
    db.commit.assert_not_called()

def test_failure_rolls_back_and_hides_database_detail(client):
    c,db,_,_,state=client
    state['fail']=True
    response=c.post('/api/v1/manufacturer-orders/10/reception',json=body())
    assert response.status_code==500
    assert 'private' not in response.text
    assert state['reception'] is None
    db.rollback.assert_called_once()

@pytest.mark.parametrize('role',['TEAM_LEAD','DIRECTOR','ADMIN'])
def test_manager_can_record_other_authors(client,role):
    c,_,_,employee,_=client
    employee.update(employee_id=99,roles=[{'role_code':role}])
    response=c.post('/api/v1/manufacturer-orders/10/reception',json=body())
    assert response.status_code==200,response.text
    assert response.json()['data']['recorded_by_employee_id']==99


@pytest.mark.parametrize('case',['inventory_failure','reception_failure','overflow','existing_movement','empty_items'])
def test_auto_receipt_failure_rolls_back_everything(client,case):
    c,db,_,_,state=client
    if case=='inventory_failure':state['fail_inventory']=True
    elif case=='reception_failure':state['fail_reception']=True
    elif case=='overflow':state['balances'][12]['on_hand_quantity']=4294967295
    elif case=='existing_movement':state['movements']=[(12,)]
    else:
        payload=json.loads(state['rows'][0]['after_data']);payload.update(items=[],total_requested_quantity=0)
        state['rows'][0]['after_data']=json.dumps(payload)
    db.commit()  # establish fixture baseline for rollback
    db.commit.reset_mock()
    before=deepcopy(state)
    response=c.post('/api/v1/manufacturer-orders/10/reception',json=body())
    assert response.status_code==(500 if case.endswith('failure') else 409),response.text
    assert state==before
    db.commit.assert_not_called()
    db.rollback.assert_called_once()


def test_inventory_row_created_if_missing(client):
    c,_,_,_,state=client
    state['balances'].clear()
    response=c.post('/api/v1/manufacturer-orders/10/reception',json=body())
    assert response.status_code==200,response.text
    assert state['balances'][12]=={'on_hand_quantity':100,'reserved_quantity':0,'defective_quantity':0}


def test_receives_all_snapshot_items_in_variant_lock_order(client):
    c,_,cursor,_,state=client
    payload=json.loads(state['rows'][0]['after_data'])
    second=deepcopy(payload['items'][0]);second.update(product_variant_id=11,purchase_requisition_item_id=2,requested_quantity=50)
    payload['items'].append(second);payload['total_requested_quantity']=150
    state['rows'][0]['after_data']=json.dumps(payload)
    response=c.post('/api/v1/manufacturer-orders/10/reception',json=body())
    assert response.status_code==200,response.text
    assert response.json()['data']['goods_receipt']['total_received_quantity']==150
    assert [m[0] for m in state['movements']]==[11,12]
    assert state['balances'][11]['on_hand_quantity']==50
    assert state['balances'][12]['on_hand_quantity']==120


def test_quantity_outside_signed_movement_range_is_rejected(client):
    c,_,_,_,state=client
    payload=json.loads(state['rows'][0]['after_data'])
    payload['items'][0]['requested_quantity']=2147483648;payload['total_requested_quantity']=2147483648
    state['rows'][0]['after_data']=json.dumps(payload)
    assert c.post('/api/v1/manufacturer-orders/10/reception',json=body()).status_code==409


def test_old_acceptance_retry_does_not_retroactively_receive(client):
    c,_,_,_,state=client
    state['reception']=dict(audit_log_id=20,after_data=json.dumps({'schema_version':1,'order_audit_log_id':10,
        'decision':'ACCEPTED','confirmation_method':'PHONE','comment':'confirmed'}),request_id='request_1234567890',
        created_at=datetime(2026,10,11,12),actor_employee_id=15,employee_name='recorder')
    response=c.post('/api/v1/manufacturer-orders/10/reception',json=body())
    assert response.status_code==200,response.text
    assert response.json()['data']['goods_receipt'] is None
    assert state['balances'][12]['on_hand_quantity']==20
