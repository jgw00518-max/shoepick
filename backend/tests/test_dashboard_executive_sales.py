from datetime import datetime
from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.features import dashboard as feature
from backend.features.authentication import current_employee

@pytest.fixture
def client(monkeypatch):
    db=MagicMock();cursor=db.cursor.return_value.__enter__.return_value
    cursor.fetchone.return_value={'sales_quantity':5,'revenue_amount':120000,'order_count':2}
    employee={'roles':[{'role_code':'EXECUTIVE'}]}
    monkeypatch.setattr(feature,'_sales_period',lambda:(datetime(2026,9,14),datetime(2026,10,11,12)))
    app.dependency_overrides[feature.get_db]=lambda:db
    app.dependency_overrides[current_employee]=lambda:employee
    try:
        with TestClient(app) as c:yield c,db,cursor,employee
    finally:app.dependency_overrides.clear()

def test_sales_uses_payment_period_and_preaggregates_to_avoid_double_count(client):
    c,db,cursor,_=client
    response=c.get('/api/v1/dashboard/executive/sales')
    assert response.status_code==200,response.text
    assert response.json()['data']['sales_quantity']==5
    assert response.json()['data']['revenue_amount']==120000
    sql,params=cursor.execute.call_args.args
    assert 'MIN(paid_at)' in sql and sql.count('GROUP BY order_id')==2
    assert 'SUM(o.paid_total)' in sql and 'SUM(q.quantity)' in sql
    assert params==(datetime(2026,9,14),datetime(2026,10,11,12),'PAID','PREPARING','SHIPPING','READY_FOR_PICKUP','COMPLETED')
    db.commit.assert_not_called()

def test_empty_sales_returns_zero(client):
    c,_,cursor,_=client
    cursor.fetchone.return_value={'sales_quantity':0,'revenue_amount':0,'order_count':0}
    assert c.get('/api/v1/dashboard/executive/sales').json()['data']['order_count']==0

@pytest.mark.parametrize('role',['HQ_STAFF','TEAM_LEAD','DIRECTOR','BRANCH_STAFF'])
def test_nonexecutive_cannot_read(client,role):
    c,_,cursor,employee=client
    employee['roles']=[{'role_code':role}]
    assert c.get('/api/v1/dashboard/executive/sales').status_code==403
    cursor.execute.assert_not_called()

def test_admin_and_unauthenticated(client):
    c,_,_,employee=client
    employee['roles']=[{'role_code':'ADMIN'}]
    assert c.get('/api/v1/dashboard/executive/sales').status_code==200
    del app.dependency_overrides[current_employee]
    assert c.get('/api/v1/dashboard/executive/sales').status_code==401


def test_sql_aggregation_with_multiple_items_and_payment_attempts(monkeypatch):
    import sqlite3
    connection=sqlite3.connect(':memory:')
    connection.row_factory=sqlite3.Row
    connection.executescript('CREATE TABLE orders (order_id INTEGER,paid_total INTEGER,order_status TEXT);'
        'CREATE TABLE payments (order_id INTEGER,paid_at TEXT,payment_status TEXT);'
        'CREATE TABLE order_items (order_id INTEGER,quantity INTEGER);')
    connection.executemany('INSERT INTO orders VALUES (?,?,?)',[(1,100000,'PAID'),(2,20000,'COMPLETED'),
        (3,10000,'CANCELED'),(4,10000,'REFUNDED'),(5,10000,'PAID'),(6,10000,'PENDING_PAYMENT'),(7,10000,'PAID')])
    connection.executemany('INSERT INTO payments VALUES (?,?,?)',[(1,'2026-10-01 12:00:00','PAID'),
        (1,'2026-10-01 12:00:00','PAID'),(1,'2026-10-01 12:00:00','FAILED'),
        (2,'2026-10-01 12:00:00','PARTIALLY_REFUNDED'),(3,'2026-10-01 12:00:00','PAID'),
        (4,'2026-10-01 12:00:00','REFUNDED'),(5,'2026-09-13 23:59:59','PAID'),
        (6,None,'PENDING'),(7,'2026-10-12 12:00:00','PAID')])
    connection.executemany('INSERT INTO order_items VALUES (?,?)',[(1,2),(1,3),(2,2),(3,9),(4,9),(5,9),(6,9),(7,9)])
    class Cursor:
        def __enter__(self):self.cursor=connection.cursor();return self
        def __exit__(self,*args):self.cursor.close()
        def execute(self,sql,params):
            self.cursor.execute(sql.replace('%s','?'),tuple(value.isoformat(sep=' ') if isinstance(value,datetime) else value for value in params))
        def fetchone(self):return dict(self.cursor.fetchone())
    db=MagicMock();db.cursor.side_effect=lambda *_:Cursor()
    monkeypatch.setattr(feature,'_sales_period',lambda:(datetime(2026,9,14),datetime(2026,10,11,12)))
    try:
        result=feature.get_executive_sales(employee={'roles':[{'role_code':'EXECUTIVE'}]},db=db)
        assert (result.data.sales_quantity,result.data.revenue_amount,result.data.order_count)==(7,120000,2)
    finally:connection.close()
