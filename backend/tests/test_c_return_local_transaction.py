"""승인 반품 fixture를 이용한 로컬 SQL 검사. 실제 수령 인증 검증과 구분한다."""
import os
from uuid import uuid4
import pytest
import pymysql
from backend.database import connect
from backend.features import order_history as c


class UncommittedConnection:
    def __init__(self, connection):
        self.connection = connection
    def __getattr__(self, name):
        return getattr(self.connection, name)
    def commit(self):
        pass


@pytest.mark.skipif(os.getenv('SHOEPICK_LOCAL_DB_TEST') != '1', reason='explicit local DB test only')
def test_real_return_restore_refund_complete_then_rollback():
    if os.getenv('DB_HOST','127.0.0.1') not in ('localhost','127.0.0.1','::1'):
        pytest.fail('Local DB only')
    db=connect()
    order_id=None
    try:
        with db.cursor(pymysql.cursors.DictCursor) as cur:
            cur.execute('SELECT customer_id FROM customers WHERE deleted_at IS NULL LIMIT 1');customer=cur.fetchone()
            cur.execute('SELECT branch_id FROM branches LIMIT 1');branch=cur.fetchone()
            cur.execute('SELECT employee_id FROM employees WHERE is_active=1 LIMIT 1');employee=cur.fetchone()
            cur.execute('SELECT oi.* FROM order_items oi JOIN headquarters_inventory hi ON hi.product_variant_id=oi.product_variant_id LIMIT 1');item=cur.fetchone()
            if not all((customer,branch,employee,item)):
                pytest.skip('Existing local fixture references required')
            variant=item['product_variant_id']
            cur.execute('SELECT on_hand_quantity,reserved_quantity,defective_quantity FROM headquarters_inventory WHERE product_variant_id=%s FOR UPDATE',(variant,));before=cur.fetchone()
            cur.execute("INSERT INTO orders (order_number,customer_id,pickup_branch_id,fulfillment_type,order_status,subtotal_amount,paid_total) VALUES (%s,%s,%s,'PICKUP','COMPLETED',%s,%s)",
                        ('C-RETURN-'+uuid4().hex[:20],customer['customer_id'],branch['branch_id'],item['unit_price'],item['unit_price']))
            order_id=cur.lastrowid
            cur.execute('INSERT INTO order_items (order_id,product_variant_id,product_name,product_code,color_name,size_mm,unit_price,quantity) VALUES (%s,%s,%s,%s,%s,%s,%s,1)',
                        (order_id,variant,item['product_name'],item['product_code'],item['color_name'],item['size_mm'],item['unit_price']))
            item_id=cur.lastrowid
            cur.execute("INSERT INTO payments (order_id,payment_method,payment_status,payment_amount,paid_at) VALUES (%s,'MOCK','PAID',%s,CURRENT_TIMESTAMP)",(order_id,item['unit_price']))
            cur.execute("INSERT INTO pickups (order_id,branch_id,pickup_status,ready_at,picked_up_at) VALUES (%s,%s,'COMPLETED',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",(order_id,branch['branch_id']))
            cur.execute("INSERT INTO return_requests (order_id,customer_id,branch_id,request_status,return_reason) VALUES (%s,%s,%s,'APPROVED','local transaction test')",(order_id,customer['customer_id'],branch['branch_id']))
            request_id=cur.lastrowid
            cur.execute('INSERT INTO return_items (return_request_id,order_item_id,quantity) VALUES (%s,%s,1)',(request_id,item_id))
            cur.execute("INSERT INTO after_sales_inspections (return_request_id,inspection_stage,inspected_by_employee_id,inspection_decision) VALUES (%s,'HEADQUARTERS',%s,'ACCEPTED')",(request_id,employee['employee_id']))
        staff={'employee_id':employee['employee_id'],'roles':[{'role_code':'HQ_STAFF'}]}
        result=c.complete_staff_return_mock(c.ReturnCompleteMockRequest(request_id=uuid4().hex,resale_confirmed=True),request_id,staff,UncommittedConnection(db))
        assert result['data']['completed'] and result['data']['is_mock']
        with db.cursor(pymysql.cursors.DictCursor) as cur:
            cur.execute('SELECT on_hand_quantity,reserved_quantity,defective_quantity FROM headquarters_inventory WHERE product_variant_id=%s',(variant,))
            assert cur.fetchone()=={**before,'on_hand_quantity':before['on_hand_quantity']+1}
            cur.execute('SELECT payment_status FROM payments WHERE order_id=%s',(order_id,));assert cur.fetchone()['payment_status']=='REFUNDED'
            cur.execute('SELECT request_status FROM return_requests WHERE return_request_id=%s',(request_id,));assert cur.fetchone()['request_status']=='COMPLETED'
            cur.execute('SELECT order_status,purchase_confirmed_at FROM orders WHERE order_id=%s',(order_id,));assert cur.fetchone()=={'order_status':'COMPLETED','purchase_confirmed_at':None}
            cur.execute("SELECT COUNT(*) AS n FROM inventory_movements WHERE reference_type='RETURN' AND reference_id=%s",(request_id,));assert cur.fetchone()['n']==1
    finally:
        db.rollback()
        try:
            if order_id is not None:
                with db.cursor() as cur:
                    cur.execute('SELECT COUNT(*) FROM orders WHERE order_id=%s',(order_id,));assert cur.fetchone()[0]==0
                with db.cursor(pymysql.cursors.DictCursor) as cur:
                    cur.execute('SELECT on_hand_quantity,reserved_quantity,defective_quantity FROM headquarters_inventory WHERE product_variant_id=%s',(variant,))
                    assert cur.fetchone()==before
        finally:
            db.close()
