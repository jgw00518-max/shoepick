"""결제 완료 주문 조회, 주문 상세 조회, 모의 결제 API."""

from datetime import datetime, timedelta
from hashlib import sha256
import json
from uuid import uuid4

from pymysql import IntegrityError

from fastapi import APIRouter, Depends, HTTPException, Path
from pydantic import BaseModel
from pymysql.connections import Connection
from pymysql.cursors import DictCursor

if __package__ == "backend.features":
    from ..dependencies import get_db
    from .authentication import current_customer
    from .inventory import reserve_order_inventory, release_order_inventory
else:
    from dependencies import get_db
    from features.authentication import current_customer
    from features.inventory import reserve_order_inventory, release_order_inventory


router = APIRouter(prefix="/orders", tags=["주문·결제"])


def refund_return_order_mock(db: Connection, *, order_id: int, return_request_id: int,
                             employee_id: int, request_id: str) -> dict:
    """C가 실행 권한·전체 반품 조건을 검증한 동일 트랜잭션에서 호출하는 모의 환불.

    결제와 환불 기록만 변경한다. 주문·반품 완료, 재고·혜택 처리 및
    commit/rollback은 호출자 책임이며 실제 결제 사업자를 호출하지 않는다.
    """
    if (any(type(value) is not int or value < 1 for value in
            (order_id, return_request_id, employee_id))
            or not isinstance(request_id, str) or not request_id.strip() or len(request_id) > 100):
        raise HTTPException(400, detail={'code': 'INVALID_INPUT', 'message': '환불 요청 정보를 확인해주세요.'})
    key = 'mock-return:' + sha256(request_id.encode('utf-8')).hexdigest()
    def conflict(message):
        raise HTTPException(409, detail={'code': 'INVALID_STATE_TRANSITION', 'message': message})

    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT order_status, paid_total, purchase_confirmed_at FROM orders '
                       'WHERE order_id=%s FOR UPDATE', (order_id,))
        order = cursor.fetchone()
        if order is None:
            raise HTTPException(404, detail={'code': 'NOT_FOUND', 'message': '주문을 찾을 수 없습니다.'})
        cursor.execute('SELECT order_id, request_status FROM return_requests '
                       'WHERE return_request_id=%s FOR UPDATE', (return_request_id,))
        request = cursor.fetchone()
        if request is None or request['order_id'] != order_id:
            conflict('주문과 반품 접수가 일치하지 않습니다.')
        cursor.execute('SELECT refund_id, order_id, return_request_id, refund_type, refund_status, '
                       'refund_amount, completed_at FROM refunds WHERE idempotency_key=%s FOR UPDATE', (key,))
        previous_key = cursor.fetchone()
        if previous_key is not None and (previous_key['order_id'] != order_id
                or previous_key['return_request_id'] != return_request_id or previous_key['refund_type'] != 'RETURN'):
            conflict('같은 요청 번호를 다른 환불에 사용할 수 없습니다.')
        if previous_key is not None and previous_key['refund_status'] == 'CANCELED':
            conflict('취소된 환불 요청 번호는 다시 사용할 수 없습니다.')
        cursor.execute('SELECT r.refund_id, r.order_id, r.return_request_id, r.refund_type, r.refund_status, '
                       'r.refund_amount, r.completed_at, p.payment_method FROM refunds r '
                       'JOIN payments p ON p.payment_id=r.payment_id AND p.order_id=r.order_id WHERE r.order_id=%s '
                       "AND r.refund_status <> 'CANCELED' FOR UPDATE", (order_id,))
        refunds = cursor.fetchall()
        if refunds:
            if (len(refunds) == 1 and refunds[0]['return_request_id'] == return_request_id
                    and refunds[0]['refund_type'] == 'RETURN' and refunds[0]['refund_status'] == 'SUCCEEDED'
                    and refunds[0]['payment_method'] == 'MOCK'):
                result = {key: value for key, value in refunds[0].items() if key != 'payment_method'}
                return {**result, 'replayed': True, 'is_mock': True}
            conflict('기존 환불 기록을 확인한 뒤 처리해야 합니다.')
        if order['order_status'] != 'COMPLETED' or order['purchase_confirmed_at'] is not None or request['request_status'] != 'APPROVED':
            conflict('구매 미확정·반품 최종 승인 주문만 처리할 수 있습니다.')
        cursor.execute('SELECT payment_id, payment_method, payment_status, payment_amount FROM payments '
                       "WHERE order_id=%s AND payment_status IN ('PAID','PARTIALLY_REFUNDED','REFUNDED') FOR UPDATE", (order_id,))
        payments = cursor.fetchall()
        if (len(payments) != 1 or payments[0]['payment_method'] != 'MOCK'
                or payments[0]['payment_status'] != 'PAID'
                or payments[0]['payment_amount'] != order['paid_total'] or order['paid_total'] < 0):
            conflict('전체 금액이 일치하는 단일 모의 결제만 환불할 수 있습니다.')
        payment = payments[0]
        cursor.execute('INSERT INTO refunds (refund_number, payment_id, order_id, return_request_id, '
                       'refund_type, refund_status, refund_amount, idempotency_key, processing_at, completed_at) '
                       "VALUES (%s,%s,%s,%s,'RETURN','SUCCEEDED',%s,%s,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",
                       (uuid4().hex, payment['payment_id'], order_id, return_request_id, payment['payment_amount'], key))
        refund_id = cursor.lastrowid
        cursor.execute("UPDATE payments SET payment_status='REFUNDED' WHERE payment_id=%s AND payment_status='PAID'",
                       (payment['payment_id'],))
        if cursor.rowcount != 1:
            conflict('결제 상태가 변경되었습니다.')
        cursor.execute('INSERT INTO audit_logs (actor_type, actor_employee_id, action_code, entity_type, '
                       'entity_id, request_id) VALUES (\'EMPLOYEE\',%s,\'MOCK_RETURN_REFUND\',\'refunds\',%s,%s)',
                       (employee_id, refund_id, request_id))
        cursor.execute('SELECT refund_id, order_id, return_request_id, refund_type, refund_status, '
                       'refund_amount, completed_at FROM refunds WHERE refund_id=%s', (refund_id,))
        result = cursor.fetchone()
    return {**result, 'replayed': False, 'is_mock': True}


def cancel_paid_order_mock(db: Connection, *, order_id: int, customer_id: int,
                           request_id: str, reason: str) -> dict:
    """검증된 고객의 출고 전 주문에 모의 환불 기록만 생성한다.

    주문 잠금 안에서 배송·소비 흔적을 재검사한다. D 예약 해제와 B 혜택,
    주문 최종 취소 및 commit/rollback은 최상위 호출자가 책임진다.
    """
    if (any(type(value) is not int or value < 1 for value in (order_id, customer_id))
            or not isinstance(request_id, str) or not request_id.strip() or len(request_id) > 100
            or not isinstance(reason, str) or not reason.strip() or len(reason.strip()) > 255):
        raise HTTPException(400, detail={'code': 'INVALID_INPUT', 'message': '취소 요청 정보를 확인해주세요.'})
    request_id, reason = request_id.strip(), reason.strip()
    key = 'mock-cancel:' + sha256(request_id.encode('utf-8')).hexdigest()

    def conflict(message):
        raise HTTPException(409, detail={'code': 'INVALID_STATE_TRANSITION', 'message': message})

    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT order_status, paid_total FROM orders WHERE order_id=%s '
                       'AND customer_id=%s FOR UPDATE', (order_id, customer_id))
        order = cursor.fetchone()
        if order is None:
            raise HTTPException(404, detail={'code': 'NOT_FOUND', 'message': '주문을 찾을 수 없습니다.'})
        cursor.execute('SELECT refund_id, order_id, refund_type, refund_status FROM refunds '
                       'WHERE idempotency_key=%s FOR UPDATE', (key,))
        previous = cursor.fetchone()
        if previous is not None and (previous['order_id'] != order_id or previous['refund_type'] != 'ORDER_CANCEL'
                                     or previous['refund_status'] == 'CANCELED'):
            conflict('같은 요청 번호를 다른 취소에 사용할 수 없습니다.')
        cursor.execute('SELECT r.refund_id, r.order_id, r.return_request_id, r.refund_type, r.refund_status, '
                       'r.refund_amount, r.completed_at, p.payment_method FROM refunds r JOIN payments p '
                       'ON p.payment_id=r.payment_id AND p.order_id=r.order_id WHERE r.order_id=%s '
                       "AND r.refund_status <> 'CANCELED' FOR UPDATE", (order_id,))
        refunds = cursor.fetchall()
        if refunds:
            row = refunds[0]
            if (len(refunds) == 1 and row['refund_type'] == 'ORDER_CANCEL' and row['return_request_id'] is None
                    and row['refund_status'] == 'SUCCEEDED' and row['payment_method'] == 'MOCK'):
                # 동일 키의 본문 변경은 차단하고, 새 키의 업무 재전송은 기존 결과를 반환한다.
                if previous is not None:
                    cursor.execute("SELECT after_data FROM audit_logs WHERE action_code='MOCK_ORDER_CANCEL' "
                                   "AND entity_type='refunds' AND entity_id=%s AND actor_customer_id=%s AND request_id=%s",
                                   (row['refund_id'], customer_id, request_id))
                    audit = cursor.fetchone()
                    payload = json.loads(audit['after_data']) if audit and isinstance(audit['after_data'], str) else (audit or {}).get('after_data')
                    if payload != {'reason': reason}:
                        conflict('같은 요청 번호의 취소 사유가 다릅니다.')
                return {**{name: value for name, value in row.items() if name != 'payment_method'},
                        'replayed': True, 'is_mock': True}
            conflict('기존 환불 기록을 확인한 뒤 처리해야 합니다.')
        if order['order_status'] != 'PAID':
            conflict('결제 완료 후 출고 전 주문만 취소할 수 있습니다.')
        cursor.execute('SELECT fulfillment_status, shipped_at, arrived_at, inspected_at, completed_at '
                       'FROM fulfillments WHERE order_id=%s ORDER BY fulfillment_id FOR UPDATE', (order_id,))
        deliveries = cursor.fetchall()
        if len(deliveries) > 1 or any(row['fulfillment_status'] != 'PREPARING' or
                any(row[field] is not None for field in ('shipped_at', 'arrived_at', 'inspected_at', 'completed_at')) for row in deliveries):
            conflict('출고 진행 기록이 있거나 확인이 필요한 배송입니다.')
        cursor.execute("SELECT inventory_reservation_id FROM inventory_reservations WHERE order_id=%s "
                       "AND (reservation_status='CONSUMED' OR consumed_at IS NOT NULL) LIMIT 1 FOR UPDATE", (order_id,))
        if cursor.fetchone() is not None:
            conflict('이미 출고 재고 처리 기록이 있습니다.')
        cursor.execute('SELECT payment_id, payment_method, payment_status, payment_amount FROM payments WHERE order_id=%s '
                       "AND payment_status IN ('PAID','PARTIALLY_REFUNDED','REFUNDED') FOR UPDATE", (order_id,))
        payments = cursor.fetchall()
        if (len(payments) != 1 or payments[0]['payment_method'] != 'MOCK' or payments[0]['payment_status'] != 'PAID'
                or payments[0]['payment_amount'] != order['paid_total'] or order['paid_total'] < 0):
            conflict('전체 금액이 일치하는 단일 모의 결제만 취소할 수 있습니다.')
        payment = payments[0]
        cursor.execute('INSERT INTO refunds (refund_number, payment_id, order_id, refund_type, refund_status, '
                       'refund_amount, idempotency_key, processing_at, completed_at) '
                       "VALUES (%s,%s,%s,'ORDER_CANCEL','SUCCEEDED',%s,%s,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",
                       (uuid4().hex, payment['payment_id'], order_id, payment['payment_amount'], key))
        refund_id = cursor.lastrowid
        cursor.execute("UPDATE payments SET payment_status='REFUNDED' WHERE payment_id=%s AND payment_status='PAID'", (payment['payment_id'],))
        if cursor.rowcount != 1:
            conflict('결제 상태가 변경되었습니다.')
        cursor.execute('INSERT INTO audit_logs (actor_type, actor_customer_id, action_code, entity_type, entity_id, after_data, request_id) '
                       "VALUES ('CUSTOMER',%s,'MOCK_ORDER_CANCEL','refunds',%s,%s,%s)",
                       (customer_id, refund_id, json.dumps({'reason': reason}, ensure_ascii=False), request_id))
        cursor.execute('SELECT refund_id, order_id, return_request_id, refund_type, refund_status, refund_amount, completed_at '
                       'FROM refunds WHERE refund_id=%s', (refund_id,))
        result = cursor.fetchone()
    return {**result, 'replayed': False, 'is_mock': True}


def mark_order_canceled_mock(db: Connection, *, order_id: int, customer_id: int,
                             refund_id: int, reason: str) -> dict:
    """모의 환불 후 D 예약 해제 전에 호출하는 주문 상태 변경 단계.

    금융·재고·혜택을 실행하거나 commit하지 않는다. 호출자는 같은 연결에서
    D와 나머지 처리를 마친 뒤 commit하고, 실패하면 전체 rollback한다.
    """
    if (any(type(value) is not int or value < 1 for value in (order_id, customer_id, refund_id))
            or not isinstance(reason, str) or not reason.strip() or len(reason.strip()) > 255):
        raise HTTPException(400, detail={'code': 'INVALID_INPUT', 'message': '255자 이내의 취소 사유와 처리 정보를 확인해주세요.'})
    reason = reason.strip()

    def conflict(message):
        raise HTTPException(409, detail={'code': 'INVALID_STATE_TRANSITION', 'message': message})

    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT order_status, paid_total, canceled_at FROM orders WHERE order_id=%s '
                       'AND customer_id=%s FOR UPDATE', (order_id, customer_id))
        order = cursor.fetchone()
        if order is None:
            raise HTTPException(404, detail={'code': 'NOT_FOUND', 'message': '주문을 찾을 수 없습니다.'})
        if order['order_status'] not in ('PAID', 'CANCELED'):
            conflict('출고 전 결제 완료 주문만 취소 상태로 변경할 수 있습니다.')
        cursor.execute('SELECT r.refund_type, r.refund_status, r.refund_amount, r.return_request_id, r.completed_at, '
                       'p.payment_method, p.payment_status, p.payment_amount FROM refunds r JOIN payments p '
                       'ON p.payment_id=r.payment_id AND p.order_id=r.order_id '
                       'WHERE r.refund_id=%s AND r.order_id=%s FOR UPDATE', (refund_id, order_id))
        refund = cursor.fetchone()
        if (refund is None or refund['refund_type'] != 'ORDER_CANCEL' or refund['refund_status'] != 'SUCCEEDED'
                or refund['return_request_id'] is not None or refund['completed_at'] is None
                or refund['payment_method'] != 'MOCK' or refund['payment_status'] != 'REFUNDED'
                or refund['refund_amount'] != order['paid_total'] or refund['payment_amount'] != order['paid_total']):
            conflict('주문 전체 금액의 모의 취소 환불 기록이 필요합니다.')
        cursor.execute('SELECT fulfillment_status, shipped_at, arrived_at, inspected_at, completed_at '
                       'FROM fulfillments WHERE order_id=%s ORDER BY fulfillment_id FOR UPDATE', (order_id,))
        deliveries = cursor.fetchall()
        if len(deliveries) > 1 or any(row['fulfillment_status'] != 'PREPARING' or
                any(row[field] is not None for field in ('shipped_at', 'arrived_at', 'inspected_at', 'completed_at')) for row in deliveries):
            conflict('출고 진행 기록이 있거나 확인이 필요한 배송입니다.')
        cursor.execute("SELECT inventory_reservation_id FROM inventory_reservations WHERE order_id=%s "
                       "AND (reservation_status='CONSUMED' OR consumed_at IS NOT NULL) LIMIT 1 FOR UPDATE", (order_id,))
        if cursor.fetchone() is not None:
            conflict('이미 출고 재고 처리 기록이 있습니다.')
        cursor.execute("SELECT after_data FROM audit_logs WHERE action_code='MOCK_ORDER_CANCEL' "
                       "AND entity_type='refunds' AND entity_id=%s AND actor_customer_id=%s", (refund_id, customer_id))
        audit = cursor.fetchone()
        payload = json.loads(audit['after_data']) if audit and isinstance(audit['after_data'], str) else (audit or {}).get('after_data')
        if payload != {'reason': reason}:
            conflict('모의 환불 요청의 취소 사유를 확인해주세요.')
        replayed = order['order_status'] == 'CANCELED'
        if replayed:
            if order['canceled_at'] is None:
                conflict('기존 취소 처리 시각을 확인해주세요.')
            cursor.execute("SELECT order_status_history_id FROM order_status_history WHERE order_id=%s "
                           "AND new_status='CANCELED' AND change_source='MOCK_ORDER_CANCEL' "
                           'AND actor_customer_id=%s AND change_reason=%s LIMIT 1', (order_id, customer_id, reason))
            if cursor.fetchone() is None:
                conflict('기존 취소 상태 변경 이력을 확인해주세요.')
        else:
            if order['canceled_at'] is not None:
                conflict('기존 취소 처리 흔적을 확인해주세요.')
            cursor.execute("UPDATE orders SET order_status='CANCELED', canceled_at=CURRENT_TIMESTAMP "
                           "WHERE order_id=%s AND order_status='PAID'", (order_id,))
            if cursor.rowcount != 1:
                conflict('주문 상태가 변경되었습니다.')
            cursor.execute('INSERT INTO order_status_history (order_id, previous_status, new_status, change_source, '
                           'change_reason, actor_type, actor_customer_id) '
                           "VALUES (%s,'PAID','CANCELED','MOCK_ORDER_CANCEL',%s,'CUSTOMER',%s)",
                           (order_id, reason, customer_id))
    return {'order_id': order_id, 'order_status': 'CANCELED', 'refund_id': refund_id,
            'replayed': replayed, 'is_mock': True}


class PaidOrder(BaseModel):
    order_id: int
    order_number: str
    order_status: str
    pickup_branch_id: int | None
    branch_name: str | None
    paid_total: int
    ordered_at: datetime
    paid_at: datetime | None


class PaidOrderListResponse(BaseModel):
    data: list[PaidOrder]


class OrderItem(BaseModel):
    order_item_id: int
    product_variant_id: int
    product_name: str
    product_code: str
    color_name: str
    size_mm: int
    unit_price: int
    quantity: int
    line_total: int


class Payment(BaseModel):
    payment_id: int
    payment_method: str
    payment_status: str
    payment_amount: int
    paid_at: datetime | None


class OrderDetail(BaseModel):
    order_id: int
    order_number: str
    order_status: str
    pickup_branch_id: int | None
    branch_name: str | None
    paid_total: int
    ordered_at: datetime
    items: list[OrderItem]
    payments: list[Payment]


class OrderDetailResponse(BaseModel):
    data: OrderDetail


class MockPaymentRequest(BaseModel):
    transaction_key: str


class MockPaymentResult(BaseModel):
    order_id: int
    payment_id: int
    order_status: str
    payment_status: str
    paid_total: int


class MockPaymentResponse(BaseModel):
    data: MockPaymentResult
    message: str

class OrderCreateItem(BaseModel):
    product_variant_id: int
    quantity: int


class OrderCreateRequest(BaseModel):
    branch_id: int
    order_request_key: str
    items: list[OrderCreateItem]


def check_order_request(request: OrderCreateRequest) -> str:
    """주문 요청의 기본 입력값을 확인한다."""

    request_key = request.order_request_key.strip()

    if request.branch_id <= 0 or not request.items:
        raise HTTPException(
            status_code=400,
            detail={"code": "INVALID_INPUT", "message": "주문 내용을 확인해 주세요."},
        )

    if not request_key or len(request_key) > 100:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "INVALID_INPUT",
                "message": "주문 요청 식별자를 확인해 주세요.",
            },
        )

    variant_ids = set()

    for item in request.items:
        if item.product_variant_id <= 0 or item.quantity <= 0:
            raise HTTPException(
                status_code=400,
                detail={
                    "code": "INVALID_INPUT",
                    "message": "상품 옵션과 수량을 확인해 주세요.",
                },
            )

        if item.product_variant_id in variant_ids:
            raise HTTPException(
                status_code=400,
                detail={
                    "code": "INVALID_INPUT",
                    "message": "같은 상품 옵션이 중복되었습니다.",
                },
            )

        variant_ids.add(item.product_variant_id)

    return request_key

def check_pickup_branch(db: Connection, branch_id: int) -> None:
    """선택한 수령 대리점이 사용 가능한지 확인한다."""

    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            """
            SELECT branch_id
            FROM branches
            WHERE branch_id = %s
              AND is_active = TRUE
            """,
            (branch_id,),
        )

        if cursor.fetchone() is None:
            raise HTTPException(
                status_code=404,
                detail={
                    "code": "NOT_FOUND",
                    "message": "사용 가능한 수령 대리점을 찾을 수 없습니다.",
                },
            )

def check_product_option(
    db: Connection,
    product_variant_id: int,
    quantity: int,
) -> dict:
    """상품 옵션의 판매 상태·가격·재고를 확인한다."""

    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            """
            SELECT
                v.product_variant_id,
                v.product_code,
                v.color_name,
                v.size_mm,
                p.product_name,
                p.price + v.additional_price AS unit_price,
                COALESCE(i.available_quantity, 0) AS available_quantity
            FROM product_variants AS v
            JOIN products AS p ON p.product_id = v.product_id
            LEFT JOIN headquarters_inventory AS i
                ON i.product_variant_id = v.product_variant_id
            WHERE v.product_variant_id = %s
              AND v.is_active = TRUE
              AND p.is_active = TRUE
            FOR UPDATE
            """,
            (product_variant_id,),
        )
        product = cursor.fetchone()

    if product is None:
        raise HTTPException(
            status_code=404,
            detail={"code": "NOT_FOUND", "message": "상품 옵션을 찾을 수 없습니다."},
        )

    product["unit_price"] = int(product["unit_price"])

    if product["unit_price"] < 0:
        raise HTTPException(
            status_code=409,
            detail={
                "code": "INVALID_STATE_TRANSITION",
                "message": "상품 가격을 확인할 수 없습니다.",
            },
        )

    if quantity > int(product["available_quantity"]):
        raise HTTPException(
            status_code=409,
            detail={
                "code": "INSUFFICIENT_STOCK",
                "message": "상품 재고가 부족합니다.",
            },
        )

    return product

def prepare_order(request: OrderCreateRequest, db: Connection) -> dict:
    """주문 저장에 필요한 상품과 금액을 준비한다."""

    request_key = check_order_request(request)
    check_pickup_branch(db, request.branch_id)

    order_items = []
    subtotal_amount = 0

    for item in sorted(request.items, key=lambda item: item.product_variant_id):
        product = check_product_option(
            db,
            item.product_variant_id,
            item.quantity,
        )

        product["quantity"] = item.quantity
        order_items.append(product)
        subtotal_amount += product["unit_price"] * item.quantity

    return {
        "order_request_key": request_key,
        "branch_id": request.branch_id,
        "items": order_items,
        "subtotal_amount": subtotal_amount,
    }

PAYMENT_WAIT_MINUTES = 30


class OrderCreateResult(BaseModel):
    order_id: int
    order_number: str
    order_status: str
    paid_total: int
    expires_at: datetime


class OrderCreateResponse(BaseModel):
    data: OrderCreateResult


def cancel_expired_order(db: Connection, order_id: int) -> bool:
    """주문 잠금 후 만료를 다시 검사한다. 호출자가 commit한다."""
    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            "SELECT order_status FROM orders WHERE order_id = %s FOR UPDATE",
            (order_id,),
        )
        order = cursor.fetchone()
        if order is None or order["order_status"] != "PENDING_PAYMENT":
            return False
        cursor.execute(
            """SELECT inventory_reservation_id FROM inventory_reservations
               WHERE order_id = %s AND reservation_status = 'RESERVED'
                 AND expires_at <= CURRENT_TIMESTAMP FOR UPDATE""",
            (order_id,),
        )
        if cursor.fetchone() is None:
            return False
        # 재고의 직접 UPDATE 대신 D가 제공한 공통 함수를 사용한다.
        release_order_inventory(db, order_id=order_id, reason="결제 대기 30분 만료")
        cursor.execute(
            "UPDATE orders SET order_status = 'CANCELED', canceled_at = CURRENT_TIMESTAMP WHERE order_id = %s",
            (order_id,),
        )
        cursor.execute(
            """INSERT INTO order_status_history
               (order_id, previous_status, new_status, change_source, change_reason, actor_type)
               VALUES (%s, 'PENDING_PAYMENT', 'CANCELED', 'PAYMENT_TIMEOUT',
                       '결제 대기 30분 만료', 'SYSTEM')""",
            (order_id,),
        )
    return True


@router.post("", response_model=OrderCreateResponse)
def create_order(
    request: OrderCreateRequest,
    customer: dict = Depends(current_customer),
    db: Connection = Depends(get_db),
) -> OrderCreateResponse:
    """고객 주문·품목·재고 예약·이력을 하나의 트랜잭션으로 저장한다."""
    request_key = check_order_request(request)
    try:
        with db.cursor(DictCursor) as cursor:
            # 같은 고객의 동시 주문 요청을 순서대로 처리한다.
            cursor.execute(
                "SELECT customer_id FROM customers WHERE customer_id = %s AND deleted_at IS NULL FOR UPDATE",
                (customer["customer_id"],),
            )
            if cursor.fetchone() is None:
                raise HTTPException(403, detail={"code": "FORBIDDEN", "message": "주문할 수 없는 회원입니다."})
            cursor.execute(
                """SELECT order_id, order_number, customer_id, pickup_branch_id,
                          order_status, paid_total, ordered_at
                   FROM orders WHERE order_request_key = %s FOR UPDATE""",
                (request_key,),
            )
            previous = cursor.fetchone()
            if previous is not None:
                cursor.execute(
                    "SELECT product_variant_id, quantity FROM order_items WHERE order_id = %s ORDER BY product_variant_id",
                    (previous["order_id"],),
                )
                saved_items = [(row["product_variant_id"], row["quantity"]) for row in cursor.fetchall()]
                requested_items = sorted((item.product_variant_id, item.quantity) for item in request.items)
                if (previous["customer_id"] != customer["customer_id"]
                        or previous["pickup_branch_id"] != request.branch_id
                        or saved_items != requested_items):
                    raise HTTPException(409, detail={"code": "ALREADY_PROCESSED", "message": "다른 주문에 사용된 요청 식별자입니다."})
                if cancel_expired_order(db, previous["order_id"]):
                    previous["order_status"] = "CANCELED"
                result = OrderCreateResult(
                    **{key: previous[key] for key in ("order_id", "order_number", "order_status", "paid_total")},
                    expires_at=previous["ordered_at"] + timedelta(minutes=PAYMENT_WAIT_MINUTES),
                )
            else:
                prepared = prepare_order(request, db)
                cursor.execute("SELECT CURRENT_TIMESTAMP AS db_now")
                ordered_at = cursor.fetchone()["db_now"]
                expires_at = ordered_at + timedelta(minutes=PAYMENT_WAIT_MINUTES)
                order_number = uuid4().hex
                cursor.execute(
                    """INSERT INTO orders
                       (order_number, order_request_key, customer_id, pickup_branch_id,
                        fulfillment_type, order_status, subtotal_amount, paid_total, ordered_at)
                       VALUES (%s, %s, %s, %s, 'PICKUP', 'PENDING_PAYMENT', %s, %s, %s)""",
                    (order_number, request_key, customer["customer_id"], request.branch_id,
                     prepared["subtotal_amount"], prepared["subtotal_amount"], ordered_at),
                )
                order_id = cursor.lastrowid
                for item in prepared["items"]:
                    cursor.execute(
                        """INSERT INTO order_items
                           (order_id, product_variant_id, product_name, product_code,
                            color_name, size_mm, unit_price, quantity)
                           VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
                        (order_id, item["product_variant_id"], item["product_name"],
                         item["product_code"], item["color_name"], item["size_mm"],
                         item["unit_price"], item["quantity"]),
                    )
                reserve_order_inventory(db, order_id=order_id, expires_at=expires_at)
                cursor.execute(
                    """INSERT INTO order_status_history
                       (order_id, new_status, change_source, actor_type, actor_customer_id)
                       VALUES (%s, 'PENDING_PAYMENT', 'ORDER_CREATE', 'CUSTOMER', %s)""",
                    (order_id, customer["customer_id"]),
                )
                result = OrderCreateResult(
                    order_id=order_id, order_number=order_number,
                    order_status="PENDING_PAYMENT", paid_total=prepared["subtotal_amount"],
                    expires_at=expires_at,
                )
        db.commit()
    except IntegrityError as error:
        db.rollback()
        if error.args[0] != 1062:
            raise
        raise HTTPException(409, detail={"code": "ALREADY_PROCESSED", "message": "주문 요청 식별자가 중복되었습니다. 다시 확인해 주세요."}) from None
    except Exception:
        db.rollback()
        raise
    return OrderCreateResponse(data=result)


@router.get("/paid", response_model=PaidOrderListResponse)
def get_paid_orders(
    db: Connection = Depends(get_db),
) -> PaidOrderListResponse:
    """주문과 결제 기록이 모두 PAID인 주문을 조회한다."""

    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            """
            SELECT
                o.order_id,
                o.order_number,
                o.order_status,
                o.pickup_branch_id,
                b.branch_name,
                o.paid_total,
                o.ordered_at,
                (
                    SELECT MAX(p.paid_at)
                    FROM payments AS p
                    WHERE p.order_id = o.order_id
                      AND p.payment_status = 'PAID'
                ) AS paid_at
            FROM orders AS o
            LEFT JOIN branches AS b
                ON b.branch_id = o.pickup_branch_id
            WHERE o.order_status = 'PAID'
              AND EXISTS (
                  SELECT 1
                  FROM payments AS p
                  WHERE p.order_id = o.order_id
                    AND p.payment_status = 'PAID'
              )
            ORDER BY o.ordered_at DESC, o.order_id DESC
            """
        )
        rows = cursor.fetchall()

    return PaidOrderListResponse(
        data=[PaidOrder(**row) for row in rows]
    )


@router.get("/{order_id}", response_model=OrderDetailResponse)
def get_order_detail(
    order_id: int = Path(gt=0),
    db: Connection = Depends(get_db),
) -> OrderDetailResponse:
    """주문 한 건의 상품 항목과 결제 기록을 조회한다."""

    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            """
            SELECT
                o.order_id,
                o.order_number,
                o.order_status,
                o.pickup_branch_id,
                b.branch_name,
                o.paid_total,
                o.ordered_at
            FROM orders AS o
            LEFT JOIN branches AS b
                ON b.branch_id = o.pickup_branch_id
            WHERE o.order_id = %s
            """,
            (order_id,),
        )
        order = cursor.fetchone()

        if order is None:
            raise HTTPException(
                status_code=404,
                detail={
                    "code": "NOT_FOUND",
                    "message": "주문을 찾을 수 없습니다.",
                },
            )

        cursor.execute(
            """
            SELECT
                order_item_id,
                product_variant_id,
                product_name,
                product_code,
                color_name,
                size_mm,
                unit_price,
                quantity,
                line_total
            FROM order_items
            WHERE order_id = %s
            ORDER BY order_item_id
            """,
            (order_id,),
        )
        items = cursor.fetchall()

        cursor.execute(
            """
            SELECT
                payment_id,
                payment_method,
                payment_status,
                payment_amount,
                paid_at
            FROM payments
            WHERE order_id = %s
            ORDER BY payment_id
            """,
            (order_id,),
        )
        payments = cursor.fetchall()

    return OrderDetailResponse(
        data=OrderDetail(
            **order,
            items=[OrderItem(**item) for item in items],
            payments=[Payment(**payment) for payment in payments],
        )
    )


@router.post(
    "/{order_id}/mock-payment",
    response_model=MockPaymentResponse,
)
def pay_order_mock(
    request: MockPaymentRequest,
    customer: dict = Depends(current_customer),
    order_id: int = Path(gt=0),
    db: Connection = Depends(get_db),
) -> MockPaymentResponse:
    """기존 주문을 모의 결제하고 주문·결제 상태를 함께 저장한다."""

    transaction_key = request.transaction_key.strip()
    if not transaction_key or len(transaction_key) > 100:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "INVALID_INPUT",
                "message": "결제 요청 식별자를 확인해 주세요.",
            },
        )

    try:
        with db.cursor(DictCursor) as cursor:
            # 같은 주문에 결제가 동시에 들어오면 한 요청씩 처리한다.
            cursor.execute(
                """
                SELECT order_id, order_status, paid_total
                FROM orders
                WHERE order_id = %s AND customer_id = %s
                FOR UPDATE
                """,
                (order_id, customer["customer_id"]),
            )
            order = cursor.fetchone()

            if order is None:
                raise HTTPException(
                    status_code=404,
                    detail={
                        "code": "NOT_FOUND",
                        "message": "주문을 찾을 수 없습니다.",
                    },
                )

            # 같은 요청을 다시 보냈다면 기존 결제 결과를 반환한다.
            cursor.execute(
                """
                SELECT payment_id, order_id, payment_status
                FROM payments
                WHERE transaction_key = %s
                """,
                (transaction_key,),
            )
            previous_payment = cursor.fetchone()

            if previous_payment is not None:
                if (
                    previous_payment["order_id"] == order_id
                    and previous_payment["payment_status"] == "PAID"
                    and order["order_status"] == "PAID"
                ):
                    result = MockPaymentResult(
                        order_id=order_id,
                        payment_id=previous_payment["payment_id"],
                        order_status="PAID",
                        payment_status="PAID",
                        paid_total=order["paid_total"],
                    )
                    db.commit()
                    return MockPaymentResponse(
                        data=result,
                        message="이미 완료된 결제입니다.",
                    )

                raise HTTPException(
                    status_code=409,
                    detail={
                        "code": "ALREADY_PROCESSED",
                        "message": "이미 사용한 결제 요청 식별자입니다.",
                    },
                )

            if order["order_status"] != "PENDING_PAYMENT":
                raise HTTPException(
                    status_code=409,
                    detail={
                        "code": "INVALID_STATE_TRANSITION",
                        "message": "결제 대기 중인 주문만 결제할 수 있습니다.",
                    },
                )

            # 만료 취소는 저장한 뒤 오류를 반환한다. 아래 rollback으로 취소가 사라지지 않는다.
            if cancel_expired_order(db, order_id):
                db.commit()
                raise HTTPException(409, detail={
                    "code": "PAYMENT_EXPIRED", "message": "결제 대기 30분이 지났습니다. 다시 주문해 주세요.",
                })
            cursor.execute(
                """SELECT i.order_item_id FROM order_items i
                   LEFT JOIN inventory_reservations r
                     ON r.order_item_id = i.order_item_id AND r.order_id = i.order_id
                   WHERE i.order_id = %s AND (r.inventory_reservation_id IS NULL
                     OR r.reservation_status <> 'RESERVED' OR r.expires_at <= CURRENT_TIMESTAMP
                     OR r.reserved_quantity <> i.quantity
                     OR r.product_variant_id <> i.product_variant_id) LIMIT 1""",
                (order_id,),
            )
            if cursor.fetchone() is not None:
                raise HTTPException(409, detail={
                    "code": "INVALID_STATE_TRANSITION", "message": "유효한 재고 예약이 없는 주문입니다.",
                })

            cursor.execute(
                """
                SELECT payment_id
                FROM payments
                WHERE order_id = %s AND payment_status = 'PAID'
                LIMIT 1
                """,
                (order_id,),
            )
            if cursor.fetchone() is not None:
                raise HTTPException(
                    status_code=409,
                    detail={
                        "code": "ALREADY_PROCESSED",
                        "message": "이미 결제된 주문입니다.",
                    },
                )

            cursor.execute(
                """
                INSERT INTO payments (
                    order_id,
                    payment_method,
                    payment_status,
                    payment_amount,
                    transaction_key,
                    paid_at
                )
                VALUES (%s, 'MOCK', 'PAID', %s, %s, NOW())
                """,
                (order_id, order["paid_total"], transaction_key),
            )
            payment_id = cursor.lastrowid

            cursor.execute(
                """
                UPDATE orders
                SET order_status = 'PAID'
                WHERE order_id = %s
                """,
                (order_id,),
            )

            cursor.execute(
                """
                INSERT INTO order_status_history (
                    order_id,
                    previous_status,
                    new_status,
                    change_source,
                    actor_type
                )
                VALUES (
                    %s,
                    'PENDING_PAYMENT',
                    'PAID',
                    'MOCK_PAYMENT',
                    'SYSTEM'
                )
                """,
                (order_id,),
            )

        db.commit()

    except Exception:
        db.rollback()
        raise

    return MockPaymentResponse(
        data=MockPaymentResult(
            order_id=order_id,
            payment_id=payment_id,
            order_status="PAID",
            payment_status="PAID",
            paid_total=order["paid_total"],
        ),
        message="모의 결제가 완료되었습니다.",
    )


def mark_order_shipping(db: Connection, *, order_id: int, fulfillment_id: int, employee_id: int) -> dict:
    """C 출고 트랜잭션 안에서만 호출한다. 결제·재고 처리는 실행하지 않고 commit하지 않는다.

    호출자는 D 예약 소비와 배송 IN_TRANSIT 기록을 같은 연결에서 먼저 수행하고,
    이 함수 실패 시 전체 rollback한다. 서버 인증에서 얻은 직원 ID만 전달한다.
    """
    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT order_status, pickup_branch_id FROM orders WHERE order_id=%s FOR UPDATE', (order_id,))
        order = cursor.fetchone()
        if order is None:
            raise HTTPException(404, detail={'code': 'NOT_FOUND', 'message': '주문을 찾을 수 없습니다.'})
        if order['order_status'] != 'PAID':
            raise HTTPException(409, detail={'code': 'INVALID_STATE_TRANSITION', 'message': '결제 완료 주문만 출고 상태로 변경할 수 있습니다.'})
        cursor.execute("SELECT payment_id FROM payments WHERE order_id=%s AND payment_status='PAID' LIMIT 1", (order_id,))
        if cursor.fetchone() is None:
            raise HTTPException(409, detail={'code': 'INVALID_STATE_TRANSITION', 'message': '결제 완료 기록이 없습니다.'})
        cursor.execute('SELECT order_id, destination_branch_id, fulfillment_status, shipped_at FROM fulfillments '
                       'WHERE fulfillment_id=%s FOR UPDATE', (fulfillment_id,))
        fulfillment = cursor.fetchone()
        if (fulfillment is None or fulfillment['order_id'] != order_id
                or fulfillment['destination_branch_id'] != order['pickup_branch_id']
                or fulfillment['fulfillment_status'] != 'IN_TRANSIT' or fulfillment['shipped_at'] is None):
            raise HTTPException(409, detail={'code': 'INVALID_STATE_TRANSITION', 'message': '주문과 일치하는 출고 기록이 필요합니다.'})
        cursor.execute("UPDATE orders SET order_status='SHIPPING' WHERE order_id=%s AND order_status='PAID'", (order_id,))
        if cursor.rowcount != 1:
            raise HTTPException(409, detail={'code': 'INVALID_STATE_TRANSITION', 'message': '주문 상태가 변경되었습니다.'})
        cursor.execute("INSERT INTO order_status_history (order_id, previous_status, new_status, change_source, change_reason, actor_type, actor_employee_id) "
                       "VALUES (%s,'PAID','SHIPPING','STAFF_DISPATCH',%s,'EMPLOYEE',%s)",
                       (order_id, f'출고 확인 fulfillment_id={fulfillment_id}', employee_id))
    return {'order_id': order_id, 'order_status': 'SHIPPING', 'fulfillment_id': fulfillment_id}


def mark_order_ready_for_pickup(db: Connection, *, order_id: int, fulfillment_id: int,
                              pickup_id: int, branch_id: int, employee_id: int) -> dict:
    """정상 입고·검수 및 D 보관 처리를 완료한 C 트랜잭션에서 호출한다."""
    return _mark_order_pickup_stage(db, order_id=order_id, fulfillment_id=fulfillment_id,
                                   pickup_id=pickup_id, branch_id=branch_id, employee_id=employee_id,
                                   completed=False)


def mark_order_received(db: Connection, *, order_id: int, fulfillment_id: int,
                        pickup_id: int, branch_id: int, employee_id: int) -> dict:
    """수령 인증·실물 전달 및 D 처리를 완료한 C 트랜잭션에서 호출한다. 구매확정은 하지 않는다."""
    return _mark_order_pickup_stage(db, order_id=order_id, fulfillment_id=fulfillment_id,
                                   pickup_id=pickup_id, branch_id=branch_id, employee_id=employee_id,
                                   completed=True)


def _mark_order_pickup_stage(db: Connection, *, order_id: int, fulfillment_id: int,
                           pickup_id: int, branch_id: int, employee_id: int, completed: bool) -> dict:
    """주문 상태와 이력만 변경한다. 재고·인증은 호출자 책임이며 commit/rollback하지 않는다."""
    if min(order_id, fulfillment_id, pickup_id, branch_id, employee_id) < 1:
        raise HTTPException(400, detail={'code':'INVALID_INPUT','message':'처리 정보를 확인해주세요.'})
    before, after = ('READY_FOR_PICKUP', 'COMPLETED') if completed else ('SHIPPING', 'READY_FOR_PICKUP')
    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT order_status, pickup_branch_id FROM orders WHERE order_id=%s FOR UPDATE', (order_id,))
        order = cursor.fetchone()
        if order is None:
            raise HTTPException(404, detail={'code':'NOT_FOUND','message':'주문을 찾을 수 없습니다.'})
        if order['pickup_branch_id'] != branch_id or order['order_status'] not in (before, after):
            raise HTTPException(409, detail={'code':'INVALID_STATE_TRANSITION','message':'주문 상태·수령 대리점을 확인해주세요.'})
        cursor.execute('SELECT order_id, destination_branch_id, fulfillment_status, shipped_at, arrived_at, inspected_at, completed_at '
                       'FROM fulfillments WHERE fulfillment_id=%s FOR UPDATE', (fulfillment_id,))
        delivery = cursor.fetchone()
        if (delivery is None or delivery['order_id'] != order_id or delivery['destination_branch_id'] != branch_id
                or delivery['fulfillment_status'] != after or any(delivery[field] is None for field in ('shipped_at','arrived_at','inspected_at'))
                or (completed and delivery['completed_at'] is None) or (not completed and delivery['completed_at'] is not None)):
            raise HTTPException(409, detail={'code':'INVALID_STATE_TRANSITION','message':'일치하는 정상 입고·수령 배송 기록이 필요합니다.'})
        cursor.execute('SELECT order_id, branch_id, pickup_status, ready_at, picked_up_at FROM pickups WHERE pickup_id=%s FOR UPDATE', (pickup_id,))
        pickup = cursor.fetchone()
        if (pickup is None or pickup['order_id'] != order_id or pickup['branch_id'] != branch_id or pickup['pickup_status'] != after
                or pickup['ready_at'] is None or (completed and pickup['picked_up_at'] is None)
                or (not completed and pickup['picked_up_at'] is not None)):
            raise HTTPException(409, detail={'code':'INVALID_STATE_TRANSITION','message':'일치하는 수령 기록이 필요합니다.'})
        replay = order['order_status'] == after
        if not replay:
            cursor.execute('UPDATE orders SET order_status=%s WHERE order_id=%s AND order_status=%s', (after, order_id, before))
            if cursor.rowcount != 1:
                raise HTTPException(409, detail={'code':'INVALID_STATE_TRANSITION','message':'주문 상태가 변경되었습니다.'})
            cursor.execute('INSERT INTO order_status_history (order_id, previous_status, new_status, change_source, '
                           'change_reason, actor_type, actor_employee_id) VALUES (%s,%s,%s,%s,%s,\'EMPLOYEE\',%s)',
                           (order_id, before, after, 'STAFF_PICKUP' if completed else 'STAFF_ARRIVAL',
                            f'fulfillment_id={fulfillment_id}, pickup_id={pickup_id}', employee_id))
    return {'order_id':order_id,'order_status':after,'fulfillment_id':fulfillment_id,'pickup_id':pickup_id,'replayed':replay}
