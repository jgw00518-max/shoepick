from decimal import Decimal
from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.features import dashboard as feature
from backend.features.authentication import current_employee

@pytest.fixture
def client():
    db=MagicMock();cursor=db.cursor.return_value.__enter__.return_value
    employee={'roles':[{'role_code':'HQ_STAFF'}]}
    state={'rows':[
      dict(available=29,initial=None,percent=None,active=True),
      dict(available=30,initial=None,percent=None,active=True),
      dict(available=0,initial=100,percent=30,active=True),
      dict(available=59,initial=200,percent=30,active=True),
      dict(available=60,initial=200,percent=30,active=True),
      dict(available=19,initial=100,percent=20,active=True),
      dict(available=20,initial=100,percent=20,active=True),
      dict(available=0,initial=100,percent=30,active=False)]}
    def fetch():
        default_initial,default_percent=cursor.execute.call_args.args[1]
        rows=[r for r in state['rows'] if r['active']]
        low=sum(Decimal(r['available'])*100 < Decimal(r['initial'] or default_initial)*Decimal(r['percent'] or default_percent) for r in rows)
        return {'low_stock_variant_count':low,'monitored_variant_count':len(rows)}
    cursor.fetchone.side_effect=fetch
    app.dependency_overrides[feature.get_db]=lambda:db
    app.dependency_overrides[current_employee]=lambda:employee
    try:
        with TestClient(app) as c:yield c,db,cursor,state,employee
    finally:app.dependency_overrides.clear()

def test_strict_threshold_policies_default_and_option_count(client):
    c,db,cursor,*_=client
    response=c.get('/api/v1/dashboard/headquarters/low-stock')
    assert response.status_code==200,response.text
    assert response.json()['data']=={'low_stock_variant_count':4,'monitored_variant_count':7}
    sql,params=cursor.execute.call_args.args
    assert 'hi.available_quantity * 100' in sql and ' < ' in sql
    assert 'LEFT JOIN inventory_policies' in sql and 'ip.is_active=1' in sql
    assert 'pv.is_active=1' in sql and 'p.is_active=1' in sql
    assert 'LIMIT' not in sql and params==(100,30)
    db.commit.assert_not_called()

def test_empty_and_no_shortage(client):
    c,_,_,state,_=client
    state['rows']=[]
    assert c.get('/api/v1/dashboard/headquarters/low-stock').json()['data']['low_stock_variant_count']==0
    state['rows']=[dict(available=100,initial=None,percent=None,active=True)]
    assert c.get('/api/v1/dashboard/headquarters/low-stock').json()['data']['low_stock_variant_count']==0

@pytest.mark.parametrize('role',['TEAM_LEAD','DIRECTOR','EXECUTIVE','ADMIN'])
def test_all_headquarters_roles_can_read(client,role):
    c,_,_,_,employee=client
    employee['roles']=[{'role_code':role}]
    assert c.get('/api/v1/dashboard/headquarters/low-stock').status_code==200

def test_branch_role_and_unauthenticated_blocked(client):
    c,_,cursor,_,employee=client
    employee['roles']=[{'role_code':'BRANCH_STAFF'}]
    assert c.get('/api/v1/dashboard/headquarters/low-stock').status_code==403
    cursor.execute.assert_not_called()
    del app.dependency_overrides[current_employee]
    assert c.get('/api/v1/dashboard/headquarters/low-stock').status_code==401
