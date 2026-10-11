"""실제 C/D/A 함수를 같은 가짜 DB 연결로 호출하는 연결 검사."""
from unittest.mock import MagicMock
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from backend.features import order_history as c


@pytest.mark.parametrize('fail_payment', [False, True])
def test_real_c_d_a_functions_share_transaction_without_b_or_external_payment(fail_payment):
    db=MagicMock();db.get_autocommit.return_value=False
    cur=db.cursor.return_value.__enter__.return_value
    cur.rowcount=1;cur.lastrowid=9
    inspected={'inspection_decision':'ACCEPTED','has_wear_marks':0,'has_product_damage':0,
               'has_customer_fault':0,'has_product_defect':0,'is_wrong_item':0,
               'components_complete':1,'packaging_intact':1}
    order={'order_status':'COMPLETED','purchase_confirmed_at':None,'pickup_branch_id':3,'paid_total':59000}
    request={'order_id':1,'request_status':'APPROVED'}
    refund={'order_id':1,'return_request_id':7,'refund_id':9,'refund_type':'RETURN',
            'refund_status':'SUCCEEDED','refund_amount':59000,'completed_at':'RAW'}
    cur.fetchone.side_effect=[
        {'order_id':1},{'coupon_discount':0,'points_used':0},request,None,None,None,
        {'order_id':1},order,request,{'after_sales_inspection_id':2},{'pickup_id':3},
        order,{'purchase_confirmed_at':None},request,inspected,
        {'product_variant_id':3,'on_hand_quantity':10,'reserved_quantity':0,'defective_quantity':0},None,
        order,request,None,refund,
    ]
    items=[{'order_item_id':2,'quantity':1}]
    cur.fetchall.side_effect=[items,items,[{'order_item_id':2,'product_variant_id':3,'quantity':1}],items,
                             [],[{'payment_id':4,'payment_method':'MOCK','payment_status':'PAID','payment_amount':59000}]]
    app=FastAPI();app.include_router(c.router,prefix='/api/v1')
    app.dependency_overrides[c.get_db]=lambda:db
    app.dependency_overrides[c.current_employee]=lambda:{'employee_id':4,'roles':[{'role_code':'HQ_STAFF'}]}
    if fail_payment:
        def execute(sql,args=None):
            if sql.startswith('UPDATE payments'):
                raise RuntimeError('simulated payment storage failure')
        cur.execute.side_effect=execute
    response=TestClient(app).post('/api/v1/order-history/staff/returns/7/complete-mock',
                                  json={'request_id':'KEY','resale_confirmed':True})
    sql=[x.args[0] for x in cur.execute.call_args_list]
    stock=next(i for i,x in enumerate(sql) if x.startswith('UPDATE headquarters_inventory'))
    financial=next(i for i,x in enumerate(sql) if x.startswith('UPDATE payments'))
    if fail_payment:
        assert response.status_code==500
        assert stock < financial
        assert not any(x.startswith('UPDATE return_requests') for x in sql)
        db.rollback.assert_called_once();db.commit.assert_not_called()
        return
    assert response.status_code==200, response.text
    assert response.json()['data']['request_status']=='COMPLETED'
    completed=next(i for i,x in enumerate(sql) if x.startswith('UPDATE return_requests'))
    assert stock < financial < completed
    assert not any(x.startswith('UPDATE orders') for x in sql)
    db.commit.assert_called_once();db.rollback.assert_not_called()
