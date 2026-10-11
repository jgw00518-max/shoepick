"""C 전체 주문의 배송 준비 기록. 실제 출고와 재고 소비는 수행하지 않는다."""
import pymysql
from uuid import uuid4
from .order_history import OrderReadError


def record_dispatched_fulfillment(db, *, order_id: int, fulfillment_id: int, employee: dict):
    """D 소비가 같은 연결에서 완료된 뒤 C 배송 출고를 기록한다. 저장 확정은 호출자 책임이다."""
    if not any(role['role_code'] == 'HQ_STAFF' for role in employee['roles']):
        raise OrderReadError(403, 'FORBIDDEN', '출고 실행 권한이 없습니다.')
    if any(type(value) is not int or value < 1 for value in (order_id, fulfillment_id, employee['employee_id'])):
        raise OrderReadError(400, 'INVALID_INPUT', '출고 처리 정보를 확인해주세요.')
    def invalid():
        raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '배송 준비와 주문 전체 재고 소비 기록을 확인해주세요.')
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute('SELECT order_status, pickup_branch_id FROM orders WHERE order_id=%s FOR UPDATE', (order_id,))
        order = cursor.fetchone()
        if order is None:
            raise OrderReadError(404, 'NOT_FOUND', '주문을 찾을 수 없습니다.')
        if order['order_status'] != 'PAID':
            invalid()
        cursor.execute("SELECT payment_id FROM payments WHERE order_id=%s AND payment_status='PAID' LIMIT 1 FOR UPDATE", (order_id,))
        if cursor.fetchone() is None:
            invalid()
        cursor.execute('SELECT fulfillment_id, destination_branch_id, fulfillment_status, shipped_at, arrived_at, inspected_at, completed_at '
                       'FROM fulfillments WHERE order_id=%s ORDER BY fulfillment_id FOR UPDATE', (order_id,))
        deliveries = cursor.fetchall()
        if len(deliveries) != 1:
            invalid()
        delivery = deliveries[0]
        if (delivery['fulfillment_id'] != fulfillment_id or delivery['destination_branch_id'] != order['pickup_branch_id']
                or delivery['fulfillment_status'] != 'PREPARING'
                or any(delivery[field] is not None for field in ('shipped_at','arrived_at','inspected_at','completed_at'))):
            invalid()
        cursor.execute('SELECT order_item_id, product_variant_id, quantity FROM order_items WHERE order_id=%s ORDER BY order_item_id FOR UPDATE', (order_id,))
        items = cursor.fetchall()
        cursor.execute('SELECT order_item_id, product_variant_id, reserved_quantity, reservation_status, consumed_at '
                       'FROM inventory_reservations WHERE order_id=%s ORDER BY order_item_id FOR UPDATE', (order_id,))
        reservations = cursor.fetchall()
        if (not items or any(item['quantity'] < 1 for item in items)
                or [(i['order_item_id'],i['product_variant_id'],i['quantity']) for i in items] !=
                [(r['order_item_id'],r['product_variant_id'],r['reserved_quantity']) for r in reservations]
                or any(r['reservation_status'] != 'CONSUMED' or r['consumed_at'] is None for r in reservations)):
            invalid()
        cursor.execute('SELECT order_id, order_item_id, quantity FROM fulfillment_items WHERE fulfillment_id=%s ORDER BY order_item_id FOR UPDATE', (fulfillment_id,))
        linked = cursor.fetchall()
        if [(order_id,i['order_item_id'],i['quantity']) for i in items] != [(i['order_id'],i['order_item_id'],i['quantity']) for i in linked]:
            invalid()
        cursor.execute("UPDATE fulfillments SET fulfillment_status='IN_TRANSIT', shipped_at=CURRENT_TIMESTAMP "
                       "WHERE fulfillment_id=%s AND fulfillment_status='PREPARING' AND shipped_at IS NULL", (fulfillment_id,))
        if cursor.rowcount != 1:
            invalid()
        cursor.execute('INSERT INTO fulfillment_status_history (fulfillment_id, previous_status, new_status, change_source, '
                       'change_reason, actor_type, actor_employee_id) '
                       "VALUES (%s,'PREPARING','IN_TRANSIT','STAFF_DISPATCH',%s,'EMPLOYEE',%s)",
                       (fulfillment_id, f'order_id={order_id}', employee['employee_id']))
    return {'order_id':order_id,'fulfillment_id':fulfillment_id,'fulfillment_status':'IN_TRANSIT'}


def prepare_order_fulfillment(db, *, order_id: int, employee: dict):
    """최상위 출고 트랜잭션에서 호출한다. 같은 연결을 쓰며 commit/rollback하지 않는다.

    주문 잠금으로 동일 주문 준비 생성을 직렬화한다. 실패 시 호출자가 전체 rollback한다.
    새 배송 번호는 UUID 32자리이며 시각은 기존 DB 기본값을 사용한다.
    """
    if not any(role['role_code'] == 'HQ_STAFF' for role in employee['roles']):
        raise OrderReadError(403, 'FORBIDDEN', '출고 실행 권한이 없습니다.')
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute('SELECT order_status, pickup_branch_id FROM orders WHERE order_id=%s FOR UPDATE', (order_id,))
        order = cursor.fetchone()
        if order is None:
            raise OrderReadError(404, 'NOT_FOUND', '주문을 찾을 수 없습니다.')
        if order['order_status'] != 'PAID' or order['pickup_branch_id'] is None:
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '결제 완료와 수령 대리점을 확인해주세요.')
        cursor.execute("SELECT payment_id FROM payments WHERE order_id=%s AND payment_status='PAID' LIMIT 1", (order_id,))
        if cursor.fetchone() is None:
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '결제 완료 기록이 없습니다.')
        cursor.execute('SELECT order_item_id, quantity FROM order_items WHERE order_id=%s ORDER BY order_item_id FOR UPDATE', (order_id,))
        items = cursor.fetchall()
        if not items or any(row['quantity'] <= 0 for row in items):
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '주문 항목을 확인해주세요.')
        cursor.execute('SELECT fulfillment_id, fulfillment_number, destination_branch_id, fulfillment_status, shipped_at, '
                       'arrived_at, inspected_at, completed_at FROM fulfillments WHERE order_id=%s ORDER BY fulfillment_id FOR UPDATE', (order_id,))
        deliveries = cursor.fetchall()
        if deliveries:
            if len(deliveries) != 1:
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '여러 배송 기록이 있어 자동 출고할 수 없습니다.')
            delivery = deliveries[0]
            if (delivery['destination_branch_id'] != order['pickup_branch_id'] or delivery['fulfillment_status'] != 'PREPARING'
                    or any(delivery.get(field) is not None for field in ('shipped_at','arrived_at','inspected_at','completed_at'))):
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '재사용할 수 있는 배송 준비 기록이 아닙니다.')
            cursor.execute('SELECT order_id, order_item_id, quantity FROM fulfillment_items WHERE fulfillment_id=%s '
                           'ORDER BY order_item_id FOR UPDATE', (delivery['fulfillment_id'],))
            linked = cursor.fetchall()
            expected = [(order_id, item['order_item_id'], item['quantity']) for item in items]
            actual = [(item['order_id'], item['order_item_id'], item['quantity']) for item in linked]
            if actual != expected:
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '배송 항목과 주문 전체 수량이 일치하지 않습니다.')
            return {'fulfillment_id':delivery['fulfillment_id'], 'fulfillment_number':delivery['fulfillment_number'], 'created':False}
        fulfillment_number = uuid4().hex
        cursor.execute('INSERT INTO fulfillments (fulfillment_number, order_id, destination_branch_id) VALUES (%s,%s,%s)',
                       (fulfillment_number, order_id, order['pickup_branch_id']))
        fulfillment_id = cursor.lastrowid
        cursor.executemany('INSERT INTO fulfillment_items (fulfillment_id, order_id, order_item_id, quantity) VALUES (%s,%s,%s,%s)',
                           [(fulfillment_id, order_id, item['order_item_id'], item['quantity']) for item in items])
        cursor.execute("INSERT INTO fulfillment_status_history (fulfillment_id, previous_status, new_status, change_source, change_reason, actor_type, actor_employee_id) "
                       "VALUES (%s,NULL,'PREPARING','STAFF_DISPATCH',%s,'EMPLOYEE',%s)",
                       (fulfillment_id, f'전체 주문 배송 준비 order_id={order_id}', employee['employee_id']))
        return {'fulfillment_id':fulfillment_id,'fulfillment_number':fulfillment_number,'created':True}
