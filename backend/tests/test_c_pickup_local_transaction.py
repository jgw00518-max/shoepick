"""명시적으로 실행하는 로컬 MySQL 검사. 모든 검증 데이터를 rollback한다."""
import os
from uuid import uuid4
import pytest
import pymysql
from backend.database import connect
from backend.features import order_history as c


class UncommittedConnection:
    """실제 SQL은 실행하되 업무 함수의 commit을 억제해 검증 데이터를 보존하지 않는다."""
    def __init__(self, connection):
        self.connection = connection
    def __getattr__(self, name):
        return getattr(self.connection, name)
    def commit(self):
        pass


@pytest.mark.skipif(os.getenv('SHOEPICK_LOCAL_DB_TEST') != '1', reason='explicit local DB test only')
def test_arrival_inspection_ready_with_real_mysql_and_final_rollback():
    if os.getenv('DB_HOST', '127.0.0.1') not in ('127.0.0.1', 'localhost', '::1'):
        pytest.fail('Local DB only; remote DB tests are prohibited')
    db = connect()
    order_id = None
    try:
        with db.cursor(pymysql.cursors.DictCursor) as cur:
            cur.execute('SELECT customer_id FROM customers WHERE deleted_at IS NULL LIMIT 1')
            customer = cur.fetchone()
            cur.execute('SELECT branch_id FROM branches LIMIT 1')
            branch = cur.fetchone()
            cur.execute('SELECT employee_id FROM employees WHERE is_active=1 LIMIT 1')
            employee = cur.fetchone()
            cur.execute('SELECT product_variant_id,product_name,product_code,color_name,size_mm,unit_price FROM order_items LIMIT 1')
            item = cur.fetchone()
            if not all((customer, branch, employee, item)):
                pytest.skip('Existing local customer/branch/employee/order snapshot required')
            branch_id = branch['branch_id']
            # 인증 검증과 구분해 직원 정보 형식을 전달하는 업무 SQL 검사다.
            staff = {'employee_id': employee['employee_id'], 'roles': [{'role_code': 'BRANCH_STAFF'}], 'branches': [{'branch_id': branch_id}]}
            cur.execute("INSERT INTO orders (order_number,customer_id,pickup_branch_id,fulfillment_type,order_status,subtotal_amount,paid_total) VALUES (%s,%s,%s,'PICKUP','SHIPPING',%s,%s)",
                        ('C-TEST-' + uuid4().hex[:20], customer['customer_id'], branch_id, item['unit_price'], item['unit_price']))
            order_id = cur.lastrowid
            cur.execute('INSERT INTO order_items (order_id,product_variant_id,product_name,product_code,color_name,size_mm,unit_price,quantity) VALUES (%s,%s,%s,%s,%s,%s,%s,1)',
                        (order_id, item['product_variant_id'], item['product_name'], item['product_code'], item['color_name'], item['size_mm'], item['unit_price']))
            item_id = cur.lastrowid
            cur.execute("INSERT INTO fulfillments (fulfillment_number,order_id,destination_branch_id,fulfillment_status,shipped_at) VALUES (%s,%s,%s,'IN_TRANSIT',CURRENT_TIMESTAMP)",
                        (uuid4().hex, order_id, branch_id))
            fulfillment_id = cur.lastrowid
            cur.execute('INSERT INTO fulfillment_items (fulfillment_id,order_id,order_item_id,quantity) VALUES (%s,%s,%s,1)', (fulfillment_id,order_id,item_id))
        connection = UncommittedConnection(db)
        assert c.confirm_staff_arrival(c.ArrivalConfirmRequest(request_id=uuid4().hex,received_product=True),fulfillment_id,staff,connection)['data']['fulfillment_status'] == 'ARRIVED'
        assert c.confirm_staff_normal_inspection(c.NormalInspectionRequest(request_id=uuid4().hex,all_items_normal=True),fulfillment_id,staff,connection)['data']['fulfillment_status'] == 'INSPECTING'
        assert c.confirm_staff_pickup_ready(c.PickupReadyRequest(request_id=uuid4().hex,confirmed=True),fulfillment_id,staff,connection)['data']['order_status'] == 'READY_FOR_PICKUP'
        scope = c.DispatchScope((branch_id,), ('PAID',))
        result = c.pickup_candidates(page=1,page_size=100,branch_id=branch_id,scope=scope,db=db)
        assert any(row['order_id'] == order_id for row in result['data'])
        with db.cursor(pymysql.cursors.DictCursor) as cur:
            cur.execute('SELECT purchase_confirmed_at FROM orders WHERE order_id=%s',(order_id,))
            assert cur.fetchone()['purchase_confirmed_at'] is None
            cur.execute('SELECT ph.holding_status,ph.quantity FROM pickup_holdings ph JOIN fulfillment_items fi USING (fulfillment_item_id) WHERE fi.fulfillment_id=%s',(fulfillment_id,))
            assert cur.fetchone() == {'holding_status':'READY_FOR_PICKUP','quantity':1}
    finally:
        db.rollback()
        if order_id is not None:
            with db.cursor() as cur:
                cur.execute('SELECT COUNT(*) FROM orders WHERE order_id=%s',(order_id,))
                assert cur.fetchone()[0] == 0
        db.close()
