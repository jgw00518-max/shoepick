from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.features.order_history import authenticated_customer, CustomerScope, get_db

@pytest.fixture
def setup():
    db=MagicMock()
    cursor=db.cursor.return_value.__enter__.return_value
    app.dependency_overrides[get_db]=lambda:db
    with TestClient(app) as client:
        yield client,cursor
    app.dependency_overrides.clear()

@pytest.mark.parametrize('path',['','/1'])
def test_auth_required(setup,path):
    assert setup[0].get('/api/v1/order-history/inquiries/customer'+path).status_code==401

def test_list_owner_paging_empty(setup):
    client,cursor=setup
    app.dependency_overrides[authenticated_customer]=lambda:CustomerScope(8)
    cursor.fetchone.return_value={'total_count':0}
    cursor.fetchall.return_value=[]
    response=client.get('/api/v1/order-history/inquiries/customer?page=2&customer_id=999')
    assert response.json()['data']==[]
    sql,args=cursor.execute.call_args.args
    assert 'created_at DESC, inquiry_id DESC' in sql
    assert args==(8,20,20)
    assert client.get('/api/v1/order-history/inquiries/customer?page=0').status_code==400
    assert client.get('/api/v1/order-history/inquiries/customer?page_size=101').status_code==400

def test_detail_owner_and_responses(setup):
    client,cursor=setup
    app.dependency_overrides[authenticated_customer]=lambda:CustomerScope(8)
    cursor.fetchone.return_value=None
    assert client.get('/api/v1/order-history/inquiries/customer/99').status_code==404
    assert cursor.execute.call_args.args[1]==(8,99)
    cursor.fetchone.return_value={'inquiry_id':1,'title':'test'}
    cursor.fetchall.return_value=[{'response_content':'answer'}]
    response=client.get('/api/v1/order-history/inquiries/customer/1')
    assert response.json()['data']['responses'][0]['response_content']=='answer'
    assert 'responded_at ASC, inquiry_response_id ASC' in cursor.execute.call_args.args[0]

def test_invalid_auth_blocked(setup):
    from backend.features.authentication import verified_uid, AuthError
    def invalid():
        raise AuthError('UNAUTHENTICATED')
    app.dependency_overrides[verified_uid]=invalid
    response=setup[0].get('/api/v1/order-history/inquiries/customer')
    assert response.status_code==401
    setup[1].execute.assert_not_called()

def test_create_and_replay(setup):
    client,cursor=setup
    app.dependency_overrides[authenticated_customer]=lambda:CustomerScope(8)
    body={'inquiry_type':'OTHER','title':' test ','inquiry_content':' content ','request_id':'r1'}
    cursor.fetchone.side_effect=[{'customer_id':8},None]
    cursor.lastrowid=12
    response=client.post('/api/v1/order-history/inquiries/customer',json=body)
    assert response.status_code==201
    assert response.json()['data']['inquiry_id']==12
    assert cursor.execute.call_args_list[2].args[1]==(8,None,'OTHER','test','content')
    import json
    stored={'inquiry_type':'OTHER','title':'test','inquiry_content':'content','product_id':None}
    cursor.fetchone.side_effect=[{'customer_id':8},{'entity_id':12,'after_data':json.dumps(stored)}]
    cursor.execute.reset_mock()
    assert client.post('/api/v1/order-history/inquiries/customer',json=body).status_code==200
    assert len(cursor.execute.call_args_list)==2
    cursor.fetchone.side_effect=[{'customer_id':8},{'entity_id':12,'after_data':'{}'}]
    assert client.post('/api/v1/order-history/inquiries/customer',json=body).status_code==409

def test_create_invalid_and_rollback(setup):
    client,cursor=setup
    app.dependency_overrides[authenticated_customer]=lambda:CustomerScope(8)
    base={'inquiry_type':'PRODUCT','title':'test','inquiry_content':'body','request_id':'r'}
    for change in ({'inquiry_type':'UNKNOWN'},{'title':' '},{'title':'x'*151},{'customer_id':999}):
        assert client.post('/api/v1/order-history/inquiries/customer',json={**base,**change}).status_code==400
    cursor.fetchone.side_effect=[{'customer_id':8},None,None]
    assert client.post('/api/v1/order-history/inquiries/customer',json={**base,'product_id':999}).status_code==404
    cursor.execute.side_effect=RuntimeError('internal')
    response=client.post('/api/v1/order-history/inquiries/customer',json=base)
    assert response.status_code==500
    assert 'internal' not in response.text

@pytest.mark.parametrize('role',['BRANCH_STAFF','BRANCH_MANAGER','TEAM_LEAD','DIRECTOR','EXECUTIVE'])
def test_staff_inquiry_forbidden(setup,role):
    from backend.features.authentication import current_employee
    app.dependency_overrides[current_employee]=lambda:{'employee_id':4,'roles':[{'role_code':role}]}
    client,cursor=setup
    for method,path in [('get',''),('get','/1'),('post','/1/responses')]:
        response=getattr(client,method)('/api/v1/order-history/inquiries/staff'+path,**({'json':{'response_content':'answer','request_id':'r'}} if method=='post' else {}))
        assert response.status_code==403
    cursor.execute.assert_not_called()

def test_staff_list_detail_and_answer(setup):
    from backend.features.order_history import authorized_inquiry_staff
    import json
    app.dependency_overrides[authorized_inquiry_staff]=lambda:{'employee_id':4}
    client,cursor=setup
    cursor.fetchone.return_value={'total_count':0}
    cursor.fetchall.return_value=[]
    assert client.get('/api/v1/order-history/inquiries/staff?inquiry_status=OPEN&page=2').status_code==200
    assert cursor.execute.call_args.args[1]==('OPEN',20,20)
    cursor.fetchone.return_value=None
    assert client.get('/api/v1/order-history/inquiries/staff/1').status_code==404
    cursor.fetchone.side_effect=[{'inquiry_status':'OPEN'},None,None]
    cursor.lastrowid=5
    body={'response_content':' answer ','request_id':'r'}
    response=client.post('/api/v1/order-history/inquiries/staff/1/responses',json=body)
    assert response.status_code==201
    assert response.json()['data']['inquiry_response_id']==5
    assert cursor.execute.call_args_list[-3].args[1]==(1,4,'answer')
    cursor.fetchone.side_effect=[{'inquiry_status':'ANSWERED'},{'entity_id':5,'after_data':json.dumps({'inquiry_id':1,'response_content':'answer'})}]
    assert client.post('/api/v1/order-history/inquiries/staff/1/responses',json=body).status_code==200
    cursor.fetchone.side_effect=[{'inquiry_status':'ANSWERED'},None]
    assert client.post('/api/v1/order-history/inquiries/staff/1/responses',json=body).status_code==409
    cursor.fetchone.side_effect=None
    cursor.execute.side_effect=RuntimeError('sql secret')
    response=client.post('/api/v1/order-history/inquiries/staff/1/responses',json=body)
    assert response.status_code==500
    assert 'sql secret' not in response.text

def test_hq_role_and_unauthenticated_answer(setup):
    from backend.features.order_history import authorized_inquiry_staff
    employee={'employee_id':4,'roles':[{'role_code':'HQ_STAFF'}]}
    assert authorized_inquiry_staff(employee)==employee
    response=setup[0].post('/api/v1/order-history/inquiries/staff/1/responses',json={'response_content':'answer','request_id':'r'})
    assert response.status_code==401
    setup[1].execute.assert_not_called()
