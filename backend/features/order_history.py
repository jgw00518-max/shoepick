"""C 담당의 주문 조회. 인증과 출고 조건은 B/A의 합의된 의존성으로 연결한다."""

from dataclasses import dataclass

from fastapi import APIRouter, Depends, Query, Path
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from fastapi.routing import APIRoute
import pymysql
from .authentication import AuthError, current_customer, current_employee, require_permission
if __package__ and __package__.startswith("backend."):
    from ..auth_policy import DISPATCH_READ
else:
    from auth_policy import DISPATCH_READ
from .order import get_paid_orders, mark_order_shipping, mark_order_ready_for_pickup, mark_order_received
from .order import cancel_paid_order_mock, mark_order_canceled_mock
from .inventory import release_order_inventory, consume_order_inventory, prepare_pickup_holdings, restore_return_inventory

if __package__ and __package__.startswith('backend.'):
    from ..dependencies import get_db
else:
    from dependencies import get_db


class OrderReadError(Exception):
    def __init__(self, status: int, code: str, message: str):
        self.status, self.code, self.message = status, code, message


@dataclass(frozen=True)
class CustomerScope:
    customer_id: int


@dataclass(frozen=True)
class DispatchScope:
    # 본사 전체 접근 여부·대리점·업무 조건은 인증/권한 검사 후 서버에서 제공한다.
    branch_ids: tuple[int, ...]
    order_statuses: tuple[str, ...]
    all_branches: bool = False


def transition_dispatched_order(db, *, order_id: int, fulfillment_id: int, employee: dict):
    """B가 검증한 직원만 받아 C 출고 트랜잭션에서 A 상태 변경으로 연결한다."""
    from fastapi import HTTPException
    if not any(role['role_code'] == 'HQ_STAFF' for role in employee['roles']):
        raise OrderReadError(403, 'FORBIDDEN', '출고 실행 권한이 없습니다.')
    try:
        return mark_order_shipping(db, order_id=order_id, fulfillment_id=fulfillment_id,
                                   employee_id=employee['employee_id'])
    except HTTPException as error:
        raise OrderReadError(error.status_code, error.detail['code'], error.detail['message']) from error


def authenticated_customer(customer=Depends(current_customer)) -> CustomerScope:
    """B가 검증한 고객 ID만 주문 조회에 전달한다."""
    return CustomerScope(customer['customer_id'])


def transition_pickup_order(db, *, order_id: int, fulfillment_id: int, pickup_id: int,
                            branch_id: int, employee: dict, completed: bool):
    """검증된 대리점 직원만 A 상태 전이로 연결한다. 아직 공개 실행 API는 아니다."""
    from fastapi import HTTPException
    roles = {role['role_code'] for role in employee['roles']}
    if not roles & {'BRANCH_STAFF','BRANCH_MANAGER'} or branch_id not in {b['branch_id'] for b in employee['branches']}:
        raise OrderReadError(403, 'FORBIDDEN', '활성 소속 대리점의 직원·점장만 처리할 수 있습니다.')
    action = mark_order_received if completed else mark_order_ready_for_pickup
    try:
        return action(db, order_id=order_id, fulfillment_id=fulfillment_id, pickup_id=pickup_id,
                      branch_id=branch_id, employee_id=employee['employee_id'])
    except HTTPException as error:
        raise OrderReadError(error.status_code, error.detail['code'], error.detail['message']) from error


def authorized_dispatch(employee=Depends(require_permission(DISPATCH_READ))) -> DispatchScope:
    roles = {role['role_code'] for role in employee['roles']}
    if 'HQ_STAFF' in roles:
        return DispatchScope((), ('PAID',), all_branches=True)
    if roles & {'BRANCH_STAFF', 'BRANCH_MANAGER'}:
        return DispatchScope(tuple(branch['branch_id'] for branch in employee['branches']), ('PAID',))
    raise OrderReadError(403, 'FORBIDDEN', '출고 조회 권한이 없습니다.')


class OrderReadRoute(APIRoute):
    def get_route_handler(self):
        handler = super().get_route_handler()

        async def handle(request):
            from fastapi.exceptions import RequestValidationError
            try:
                return await handler(request)
            except OrderReadError as error:
                return JSONResponse(status_code=error.status, content={
                    'error': {'code': error.code, 'message': error.message},
                })
            except AuthError as error:
                return JSONResponse(status_code=401 if error.code == 'UNAUTHENTICATED' else 403,
                    content={'error': {'code': error.code, 'message':
                        '로그인이 필요합니다.' if error.code == 'UNAUTHENTICATED' else '접근 권한이 없습니다.'}})
            except RequestValidationError:
                return JSONResponse(status_code=400, content={'error': {
                    'code': 'INVALID_INPUT', 'message': '입력값을 확인해주세요.',
                }})
            except Exception:
                return JSONResponse(status_code=500, content={'error': {
                    'code': 'INTERNAL_ERROR', 'message': '주문 조회 중 오류가 발생했습니다.',
                }})
        return handle


# A의 주문 생성 경로와 충돌하지 않도록 분리한 C 조회 계약 초안이다.
router = APIRouter(prefix='/order-history', tags=['C 주문 조회'], route_class=OrderReadRoute)

ORDER_COLUMNS = '''o.order_id, o.order_number, o.order_status,
    o.pickup_branch_id, o.fulfillment_type, o.subtotal_amount,
    o.coupon_discount, o.points_used, o.paid_total, o.ordered_at,
    o.purchase_confirmed_at, o.canceled_at, b.branch_name'''
ORDER_FROM = 'FROM orders o LEFT JOIN branches b ON b.branch_id=o.pickup_branch_id'


def read_orders(db, condition: str, params: tuple, page: int, page_size: int):
    """항목 조인으로 페이지 수가 달라지지 않도록 주문 단위로 페이지를 조회한다."""
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute(f'SELECT COUNT(*) AS total_count {ORDER_FROM} WHERE {condition}', params)
        total = cursor.fetchone()['total_count']
        cursor.execute(
            f'SELECT {ORDER_COLUMNS} {ORDER_FROM} WHERE {condition} '
            'ORDER BY o.ordered_at DESC, o.order_id DESC LIMIT %s OFFSET %s',
            (*params, page_size, (page - 1) * page_size),
        )
        orders = cursor.fetchall()
    return {'data': jsonable_encoder(orders), 'pagination': {
        'page': page, 'page_size': page_size, 'total_count': total,
    }}


def read_detail(db, customer_id: int, order_id: int):
    """소유자 조건을 상세 조회에도 적용하고 주문 당시 상품 정보를 반환한다."""
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute(
            f'SELECT {ORDER_COLUMNS} {ORDER_FROM} '
            'WHERE o.customer_id=%s AND o.order_id=%s', (customer_id, order_id),
        )
        order = cursor.fetchone()
        if order is None:
            raise OrderReadError(404, 'NOT_FOUND', '주문을 찾을 수 없습니다.')
        cursor.execute(
            'SELECT order_item_id, product_variant_id, product_name, product_code, '
            'color_name, size_mm, unit_price, quantity, line_total FROM order_items '
            'WHERE order_id=%s ORDER BY order_item_id', (order_id,),
        )
        order['items'] = cursor.fetchall()
        cursor.execute(
            'SELECT fulfillment_id, fulfillment_status, destination_branch_id, '
            'tracking_number, shipped_at, arrived_at, completed_at FROM fulfillments '
            'WHERE order_id=%s ORDER BY fulfillment_id', (order_id,),
        )
        order['fulfillments'] = cursor.fetchall()
    return {'data': jsonable_encoder(order)}


@router.get('/customer')
def customer_orders(scope: CustomerScope = Depends(authenticated_customer),
                    db=Depends(get_db), page: int = Query(1, ge=1),
                    page_size: int = Query(20, ge=1, le=100)):
    return read_orders(db, 'o.customer_id=%s', (scope.customer_id,), page, page_size)


@router.get('/customer/{order_id}')
def customer_order(order_id: int, scope: CustomerScope = Depends(authenticated_customer),
                   db=Depends(get_db)):
    if order_id < 1:
        raise OrderReadError(400, 'INVALID_INPUT', '주문 번호를 확인해주세요.')
    return read_detail(db, scope.customer_id, order_id)


@router.get('/customer/{order_id}/after-sales')
def customer_after_sales(order_id: int = Path(..., ge=1),
                         scope: CustomerScope = Depends(authenticated_customer),
                         db=Depends(get_db)):
    """본인 주문의 기존 처리 기록만 조회하며 결제·혜택·재고를 변경하지 않는다."""
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute(
            'SELECT order_id, order_status, canceled_at FROM orders '
            'WHERE order_id=%s AND customer_id=%s', (order_id, scope.customer_id),
        )
        order = cursor.fetchone()
        if order is None:
            raise OrderReadError(404, 'NOT_FOUND', '주문을 찾을 수 없습니다.')
        cursor.execute(
            'SELECT return_request_id, return_reason_code, return_reason, request_status, '
            'branch_id, requested_at, processed_at, inspection_result, rejection_reason '
            'FROM return_requests WHERE order_id=%s AND customer_id=%s '
            'ORDER BY requested_at DESC, return_request_id DESC',
            (order_id, scope.customer_id),
        )
        order['return_requests'] = cursor.fetchall()
        # 외부 결제 키·실패 내부 메시지·재시도 식별자는 고객 응답에서 제외한다.
        cursor.execute(
            'SELECT refund_id, refund_number, return_request_id, refund_type, '
            'refund_status, refund_amount, requested_at, processing_at, completed_at, failed_at '
            'FROM refunds WHERE order_id=%s '
            'ORDER BY requested_at DESC, refund_id DESC', (order_id,),
        )
        order['refunds'] = cursor.fetchall()
    return {'data': jsonable_encoder(order)}


@router.get('/staff/dispatch')
def dispatch_orders(scope: DispatchScope = Depends(authorized_dispatch),
                    db=Depends(get_db), page: int = Query(1, ge=1),
                    page_size: int = Query(20, ge=1, le=100),
                    branch_id: int | None = Query(None, ge=1)):
    if not scope.order_statuses or (not scope.all_branches and not scope.branch_ids):
        raise OrderReadError(403, 'FORBIDDEN', '출고 조회 권한이 없습니다.')
    if branch_id is not None and not scope.all_branches and branch_id not in scope.branch_ids:
        raise OrderReadError(403, 'FORBIDDEN', '소속 대리점만 조회할 수 있습니다.')
    return read_dispatch_orders(db, scope, branch_id, page, page_size)


def read_dispatch_orders(db, scope: DispatchScope, branch_id: int | None,
                         page: int, page_size: int):
    """A의 읽기 함수를 재사용하고 C의 소속·미출고 조건을 페이지 처리 전에 적용한다."""
    paid = get_paid_orders(db=db).data
    candidates = [row for row in paid
                  if (scope.all_branches or row.pickup_branch_id in scope.branch_ids)
                  and (branch_id is None or row.pickup_branch_id == branch_id)]
    if not candidates:
        return {'data': [], 'pagination': {'page': page, 'page_size': page_size, 'total_count': 0}}
    blocked = set()
    # 주문마다 조회하지 않으며 큰 목록의 SQL 인자 수도 제한한다.
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        for offset in range(0, len(candidates), 500):
            ids = tuple(row.order_id for row in candidates[offset:offset + 500])
            placeholders = ','.join(['%s'] * len(ids))
            cursor.execute(
                f'SELECT order_id, fulfillment_status, shipped_at FROM fulfillments '
                f'WHERE order_id IN ({placeholders})', ids,
            )
            for shipment in cursor.fetchall():
                # 일부 출고·취소·알 수 없는 상태도 제외한다. 재출고 정책 확정 시 재검토한다.
                if shipment['fulfillment_status'] != 'PREPARING' or shipment['shipped_at'] is not None:
                    blocked.add(shipment['order_id'])
    eligible = [row for row in candidates if row.order_id not in blocked]
    start = (page - 1) * page_size
    return {'data': jsonable_encoder(eligible[start:start + page_size]), 'pagination': {
        'page': page, 'page_size': page_size, 'total_count': len(eligible),
    }}

# 문의 읽기는 기존 C 라우터를 사용하며 작성·답변 변경은 제공하지 않는다.
@router.get('/inquiries/customer')
def customer_inquiries(page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100),
                       scope: CustomerScope = Depends(authenticated_customer), db=Depends(get_db)):
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute('SELECT COUNT(*) AS total_count FROM inquiries WHERE customer_id=%s', (scope.customer_id,))
        total = cursor.fetchone()['total_count']
        cursor.execute('SELECT inquiry_id, product_id, inquiry_type, title, inquiry_status, created_at '
                       'FROM inquiries WHERE customer_id=%s ORDER BY created_at DESC, inquiry_id DESC LIMIT %s OFFSET %s',
                       (scope.customer_id, page_size, (page - 1) * page_size))
        rows = cursor.fetchall()
    return {'data': jsonable_encoder(rows), 'pagination': {'page': page, 'page_size': page_size, 'total_count': total}}


@router.get('/inquiries/customer/{inquiry_id}')
def customer_inquiry_detail(inquiry_id: int = Path(..., ge=1),
                            scope: CustomerScope = Depends(authenticated_customer), db=Depends(get_db)):
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute('SELECT inquiry_id, product_id, inquiry_type, title, inquiry_content, inquiry_status, created_at '
                       'FROM inquiries WHERE customer_id=%s AND inquiry_id=%s', (scope.customer_id, inquiry_id))
        row = cursor.fetchone()
        if row is None:
            raise OrderReadError(404, 'NOT_FOUND', '문의를 찾을 수 없습니다.')
        cursor.execute('SELECT inquiry_response_id, response_content, responded_at FROM inquiry_responses '
                       'WHERE inquiry_id=%s ORDER BY responded_at ASC, inquiry_response_id ASC', (inquiry_id,))
        row['responses'] = cursor.fetchall()
    return {'data': jsonable_encoder(row)}

from typing import Literal
from pydantic import BaseModel, Field, ConfigDict
import json


class InquiryCreateRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')
    inquiry_type: Literal['PRODUCT', 'DELIVERY', 'PAYMENT', 'OTHER']
    title: str = Field(min_length=1, max_length=150)
    inquiry_content: str = Field(min_length=1)
    product_id: int | None = Field(default=None, gt=0)
    request_id: str = Field(min_length=1, max_length=100)


@router.post('/inquiries/customer')
def create_customer_inquiry(body: InquiryCreateRequest,
                            scope: CustomerScope = Depends(authenticated_customer), db=Depends(get_db)):
    # 고객 잠금은 동일 고객의 같은 요청 식별자 조회와 생성을 직렬화한다.
    payload = body.model_dump(exclude={'request_id'})
    try:
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute('SELECT customer_id FROM customers WHERE customer_id=%s AND deleted_at IS NULL FOR UPDATE', (scope.customer_id,))
            if cursor.fetchone() is None:
                raise OrderReadError(403, 'FORBIDDEN', '접근 권한이 없습니다.')
            cursor.execute("SELECT entity_id, after_data FROM audit_logs WHERE actor_customer_id=%s "
                           "AND action_code='INQUIRY_CREATE' AND entity_type='INQUIRY' AND request_id=%s", (scope.customer_id, body.request_id))
            prior = cursor.fetchone()
            if prior:
                stored = json.loads(prior['after_data']) if isinstance(prior['after_data'], str) else prior['after_data']
                if stored != payload:
                    raise OrderReadError(409, 'ALREADY_PROCESSED', '같은 요청의 내용이 다릅니다.')
                db.rollback()
                return {'data': {'inquiry_id': prior['entity_id']}, 'message': '문의가 접수되었습니다.'}
            if body.product_id is not None:
                cursor.execute('SELECT product_id FROM products WHERE product_id=%s', (body.product_id,))
                if cursor.fetchone() is None:
                    raise OrderReadError(404, 'NOT_FOUND', '상품을 찾을 수 없습니다.')
            cursor.execute('INSERT INTO inquiries (customer_id, product_id, inquiry_type, title, inquiry_content) VALUES (%s,%s,%s,%s,%s)',
                           (scope.customer_id, body.product_id, body.inquiry_type, body.title, body.inquiry_content))
            inquiry_id = cursor.lastrowid
            cursor.execute('INSERT INTO audit_logs (actor_type, actor_customer_id, action_code, entity_type, entity_id, after_data, request_id) '
                           "VALUES ('CUSTOMER',%s,'INQUIRY_CREATE','INQUIRY',%s,%s,%s)",
                           (scope.customer_id, inquiry_id, json.dumps(payload, ensure_ascii=False), body.request_id))
        db.commit()
        return JSONResponse(status_code=201, content={'data': {'inquiry_id': inquiry_id}, 'message': '문의가 접수되었습니다.'})
    except Exception:
        db.rollback()
        raise

# 문의 업무는 대리점 선택값이 아니라 B가 검증한 본사 사원 역할로 제한한다.
def authorized_inquiry_staff(employee=Depends(current_employee)):
    if not any(role['role_code'] == 'HQ_STAFF' for role in employee['roles']):
        raise OrderReadError(403, 'FORBIDDEN', '문의 처리 권한이 없습니다.')
    return employee


@router.get('/inquiries/staff')
def staff_inquiries(page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100),
                    inquiry_status: Literal['OPEN', 'ANSWERED', 'CLOSED'] | None = None,
                    employee=Depends(authorized_inquiry_staff), db=Depends(get_db)):
    condition = 'WHERE inquiry_status=%s' if inquiry_status else ''
    args = (inquiry_status,) if inquiry_status else ()
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute(f'SELECT COUNT(*) AS total_count FROM inquiries {condition}', args)
        total = cursor.fetchone()['total_count']
        cursor.execute(f'SELECT inquiry_id, product_id, inquiry_type, title, inquiry_status, created_at '
                       f'FROM inquiries {condition} ORDER BY created_at DESC, inquiry_id DESC LIMIT %s OFFSET %s',
                       (*args, page_size, (page - 1) * page_size))
        rows = cursor.fetchall()
    return {'data': jsonable_encoder(rows), 'pagination': {'page': page, 'page_size': page_size, 'total_count': total}}


@router.get('/inquiries/staff/{inquiry_id}')
def staff_inquiry_detail(inquiry_id: int = Path(..., ge=1), employee=Depends(authorized_inquiry_staff), db=Depends(get_db)):
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute('SELECT inquiry_id, product_id, inquiry_type, title, inquiry_content, inquiry_status, created_at '
                       'FROM inquiries WHERE inquiry_id=%s', (inquiry_id,))
        row = cursor.fetchone()
        if row is None:
            raise OrderReadError(404, 'NOT_FOUND', '문의를 찾을 수 없습니다.')
        cursor.execute('SELECT inquiry_response_id, response_content, responded_at FROM inquiry_responses '
                       'WHERE inquiry_id=%s ORDER BY responded_at ASC, inquiry_response_id ASC', (inquiry_id,))
        row['responses'] = cursor.fetchall()
    return {'data': jsonable_encoder(row)}

class InquiryAnswerRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')
    response_content: str = Field(min_length=1)
    request_id: str = Field(min_length=1, max_length=100)


@router.post('/inquiries/staff/{inquiry_id}/responses')
def answer_staff_inquiry(body: InquiryAnswerRequest, inquiry_id: int = Path(..., ge=1),
                         employee=Depends(authorized_inquiry_staff), db=Depends(get_db)):
    employee_id = employee['employee_id']
    payload = {'inquiry_id': inquiry_id, 'response_content': body.response_content}
    try:
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            # 같은 직원이 서로 다른 문의에 같은 요청 ID를 동시에 보내는 경우도 직렬화한다.
            cursor.execute('SELECT employee_id FROM employees WHERE employee_id=%s FOR UPDATE', (employee_id,))
            cursor.execute('SELECT inquiry_status FROM inquiries WHERE inquiry_id=%s FOR UPDATE', (inquiry_id,))
            inquiry = cursor.fetchone()
            if inquiry is None:
                raise OrderReadError(404, 'NOT_FOUND', '문의를 찾을 수 없습니다.')
            cursor.execute("SELECT entity_id, after_data FROM audit_logs WHERE actor_employee_id=%s AND action_code='INQUIRY_ANSWER' "
                           "AND entity_type='INQUIRY_RESPONSE' AND request_id=%s", (employee_id, body.request_id))
            prior = cursor.fetchone()
            if prior:
                stored = json.loads(prior['after_data']) if isinstance(prior['after_data'], str) else prior['after_data']
                if stored != payload:
                    raise OrderReadError(409, 'ALREADY_PROCESSED', '같은 요청의 내용이 다릅니다.')
                db.rollback()
                return {'data': {'inquiry_id': inquiry_id, 'inquiry_response_id': prior['entity_id'], 'inquiry_status': 'ANSWERED'}, 'message': '답변이 등록되었습니다.'}
            cursor.execute('SELECT inquiry_response_id FROM inquiry_responses WHERE inquiry_id=%s LIMIT 1', (inquiry_id,))
            if inquiry['inquiry_status'] != 'OPEN' or cursor.fetchone() is not None:
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '첫 답변을 등록할 수 있는 문의가 아닙니다.')
            cursor.execute('INSERT INTO inquiry_responses (inquiry_id, employee_id, response_content) VALUES (%s,%s,%s)',
                           (inquiry_id, employee_id, body.response_content))
            response_id = cursor.lastrowid
            cursor.execute("UPDATE inquiries SET inquiry_status='ANSWERED' WHERE inquiry_id=%s", (inquiry_id,))
            cursor.execute("INSERT INTO audit_logs (actor_type, actor_employee_id, action_code, entity_type, entity_id, after_data, request_id) "
                           "VALUES ('EMPLOYEE',%s,'INQUIRY_ANSWER','INQUIRY_RESPONSE',%s,%s,%s)",
                           (employee_id, response_id, json.dumps(payload, ensure_ascii=False), body.request_id))
        db.commit()
        return JSONResponse(status_code=201, content={'data': {'inquiry_id': inquiry_id, 'inquiry_response_id': response_id,
                            'inquiry_status': 'ANSWERED'}, 'message': '답변이 등록되었습니다.'})
    except Exception:
        db.rollback()
        raise

ACTIVE_RETURN_STATUSES = ('REQUESTED', 'APPROVED', 'COLLECTING', 'INSPECTING', 'RETURNED')


def authorized_return_read(employee=Depends(current_employee)):
    """반품 조회 권한만 제공한다. 검수·환불 실행 권한으로 확대하지 않는다."""
    roles = {role['role_code'] for role in employee['roles']}
    if 'HQ_STAFF' in roles:
        return DispatchScope((), (), all_branches=True)
    if roles & {'BRANCH_STAFF', 'BRANCH_MANAGER'}:
        return DispatchScope(tuple(branch['branch_id'] for branch in employee['branches']), ())
    raise OrderReadError(403, 'FORBIDDEN', '반품 조회 권한이 없습니다.')


def return_read_filter(scope, branch_id):
    # 접수 시 서버가 저장한 수령 대리점을 기준으로 조회 범위를 제한한다.
    if branch_id is not None and not scope.all_branches and branch_id not in scope.branch_ids:
        raise OrderReadError(403, 'FORBIDDEN', '소속 대리점만 조회할 수 있습니다.')
    if branch_id is not None:
        return 'r.branch_id=%s', (branch_id,)
    if scope.all_branches:
        return '1=1', ()
    if not scope.branch_ids:
        return '1=0', ()
    return 'r.branch_id IN (' + ','.join('%s' for _ in scope.branch_ids) + ')', scope.branch_ids


RETURN_READ_FROM = 'FROM return_requests r JOIN orders o ON o.order_id=r.order_id LEFT JOIN branches b ON b.branch_id=r.branch_id'
RETURN_READ_COLUMNS = 'r.return_request_id, r.order_id, o.order_number, r.branch_id, b.branch_name, r.request_status, r.return_reason_code, r.return_reason, r.requested_at, r.processed_at, r.inspection_result, r.rejection_reason'


@router.get('/staff/returns')
def staff_returns(scope=Depends(authorized_return_read), db=Depends(get_db),
                  branch_id: int | None = Query(None, ge=1),
                  page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100)):
    condition, args = return_read_filter(scope, branch_id)
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute(f'SELECT COUNT(*) AS total_count {RETURN_READ_FROM} WHERE {condition}', args)
        total = cursor.fetchone()['total_count']
        cursor.execute(f'SELECT {RETURN_READ_COLUMNS} {RETURN_READ_FROM} WHERE {condition} '
                       'ORDER BY r.requested_at DESC, r.return_request_id DESC LIMIT %s OFFSET %s',
                       (*args, page_size, (page-1)*page_size))
        rows = cursor.fetchall()
    return {'data': jsonable_encoder(rows), 'pagination': {'page': page, 'page_size': page_size, 'total_count': total}}


@router.get('/staff/returns/{return_request_id}')
def staff_return_detail(return_request_id: int = Path(..., ge=1),
                        scope=Depends(authorized_return_read), db=Depends(get_db)):
    condition, args = return_read_filter(scope, None)
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute(f'SELECT {RETURN_READ_COLUMNS} {RETURN_READ_FROM} '
                       f'WHERE r.return_request_id=%s AND {condition}', (return_request_id, *args))
        row = cursor.fetchone()
        if row is None:
            raise OrderReadError(404, 'NOT_FOUND', '반품 접수를 찾을 수 없습니다.')
        cursor.execute('SELECT ri.order_item_id, ri.quantity, oi.product_name, oi.product_code, '
                       'oi.color_name, oi.size_mm, oi.unit_price, oi.line_total '
                       'FROM return_items ri JOIN order_items oi ON oi.order_item_id=ri.order_item_id '
                       'WHERE ri.return_request_id=%s AND oi.order_id=%s ORDER BY ri.order_item_id',
                       (return_request_id, row['order_id']))
        row['items'] = cursor.fetchall()
        cursor.execute('SELECT inspection_stage, inspection_decision, inspected_at, inspection_notes, '
                       'has_wear_marks, has_product_damage, has_customer_fault, components_complete, '
                       'packaging_intact, has_product_defect, is_wrong_item '
                       'FROM after_sales_inspections WHERE return_request_id=%s ORDER BY inspected_at, after_sales_inspection_id', (return_request_id,))
        row['inspections'] = cursor.fetchall()
        cursor.execute('SELECT refund_id, refund_status, refund_amount, requested_at, completed_at '
                       'FROM refunds WHERE return_request_id=%s AND order_id=%s ORDER BY requested_at DESC, refund_id DESC',
                       (return_request_id, row['order_id']))
        row['refunds'] = cursor.fetchall()
    return {'data': jsonable_encoder(row)}


def has_active_return(cursor, order_id):
    """주문 행 잠금을 가진 호출자만 사용하여 접수와 구매확정을 직렬화한다."""
    cursor.execute('SELECT return_request_id FROM return_requests WHERE order_id=%s '
                   'AND request_status IN (%s,%s,%s,%s,%s) LIMIT 1 FOR UPDATE',
                   (order_id, *ACTIVE_RETURN_STATUSES))
    return cursor.fetchone() is not None


class ReturnInspectionRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')
    request_id: str = Field(min_length=1, max_length=100)
    inspection_stage: Literal['BRANCH', 'HEADQUARTERS']
    received_product: Literal[True]
    has_wear_marks: bool = Field(strict=True)
    has_product_damage: bool = Field(strict=True)
    has_customer_fault: bool = Field(strict=True)
    components_complete: bool = Field(strict=True)
    packaging_intact: bool = Field(strict=True)
    has_product_defect: bool = Field(strict=True)
    is_wrong_item: bool = Field(strict=True)
    inspection_notes: str = Field(min_length=1)


@router.post('/staff/returns/{return_request_id}/inspection')
def inspect_staff_return(body: ReturnInspectionRequest, return_request_id: int = Path(..., ge=1),
                         employee=Depends(current_employee), db=Depends(get_db)):
    roles = {role['role_code'] for role in employee['roles']}
    if body.inspection_stage == 'HEADQUARTERS':
        allowed = 'HQ_STAFF' in roles
    else:
        allowed = bool(roles & {'BRANCH_STAFF', 'BRANCH_MANAGER'})
    if not allowed:
        raise OrderReadError(403, 'FORBIDDEN', '해당 단계의 검수 권한이 없습니다.')
    payload = {'return_request_id': return_request_id, **body.model_dump(exclude={'request_id'})}
    try:
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            # 직원 요청 키와 같은 접수의 단계별 최초 저장을 직렬화한다.
            cursor.execute('SELECT employee_id FROM employees WHERE employee_id=%s FOR UPDATE', (employee['employee_id'],))
            cursor.execute('SELECT request_status, branch_id FROM return_requests WHERE return_request_id=%s FOR UPDATE', (return_request_id,))
            row = cursor.fetchone()
            if row is None:
                raise OrderReadError(404, 'NOT_FOUND', '반품 접수를 찾을 수 없습니다.')
            if body.inspection_stage == 'BRANCH' and row['branch_id'] not in {b['branch_id'] for b in employee['branches']}:
                raise OrderReadError(403, 'FORBIDDEN', '소속 대리점만 검수할 수 있습니다.')
            cursor.execute("SELECT entity_id, after_data FROM audit_logs WHERE actor_employee_id=%s AND action_code='RETURN_INSPECT' "
                           "AND entity_type='AFTER_SALES_INSPECTION' AND request_id=%s", (employee['employee_id'], body.request_id))
            prior = cursor.fetchone()
            if prior:
                stored = json.loads(prior['after_data']) if isinstance(prior['after_data'], str) else prior['after_data']
                if stored != payload:
                    raise OrderReadError(409, 'ALREADY_PROCESSED', '같은 요청의 내용이 다릅니다.')
                db.rollback()
                return {'data': {'after_sales_inspection_id': prior['entity_id']}, 'message': '이미 저장된 검수입니다.'}
            if row['request_status'] not in ('REQUESTED', 'COLLECTING', 'INSPECTING'):
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '검수할 수 있는 반품 상태가 아닙니다.')
            cursor.execute('SELECT after_sales_inspection_id FROM after_sales_inspections WHERE return_request_id=%s AND inspection_stage=%s FOR UPDATE', (return_request_id, body.inspection_stage))
            if cursor.fetchone() is not None:
                raise OrderReadError(409, 'ALREADY_PROCESSED', '해당 단계의 검수가 이미 저장되었습니다.')
            cursor.execute('INSERT INTO after_sales_inspections (return_request_id, inspection_stage, inspected_by_employee_id, '
                           'has_wear_marks, has_product_damage, has_customer_fault, components_complete, packaging_intact, '
                           'has_product_defect, is_wrong_item, inspection_notes) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)',
                           (return_request_id, body.inspection_stage, employee['employee_id'], body.has_wear_marks,
                            body.has_product_damage, body.has_customer_fault, body.components_complete, body.packaging_intact,
                            body.has_product_defect, body.is_wrong_item, body.inspection_notes))
            inspection_id = cursor.lastrowid
            cursor.execute("UPDATE return_requests SET request_status='INSPECTING' WHERE return_request_id=%s", (return_request_id,))
            cursor.execute("INSERT INTO audit_logs (actor_type, actor_employee_id, action_code, entity_type, entity_id, before_data, after_data, request_id) "
                           "VALUES ('EMPLOYEE',%s,'RETURN_INSPECT','AFTER_SALES_INSPECTION',%s,%s,%s,%s)",
                           (employee['employee_id'], inspection_id, json.dumps({'request_status':row['request_status']}), json.dumps(payload, ensure_ascii=False), body.request_id))
        db.commit()
        return JSONResponse(status_code=201, content={'data': {'after_sales_inspection_id':inspection_id}, 'message':'검수 관찰 결과가 저장되었습니다. 승인·환불 완료가 아닙니다.'})
    except Exception:
        db.rollback()
        raise


class ReturnDecisionRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')
    request_id: str = Field(min_length=1, max_length=100)
    decision: Literal['APPROVED', 'REJECTED']
    rejection_reason: str | None = Field(default=None, min_length=1)


def prepare_customer_order_cancel(db, *, order_id: int, customer_id: int, request_id: str, reason: str):
    """출고 전 전체 취소의 C 조건만 검사한다. 결제 취소·예약 해제는 실행하지 않는다."""
    if order_id < 1 or customer_id < 1 or not request_id.strip() or len(request_id) > 100 or not reason.strip():
        raise OrderReadError(400, 'INVALID_INPUT', '취소 요청 정보를 확인해주세요.')
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute('SELECT order_status FROM orders WHERE order_id=%s AND customer_id=%s FOR UPDATE', (order_id,customer_id))
        order = cursor.fetchone()
        if order is None:
            raise OrderReadError(404, 'NOT_FOUND', '주문을 찾을 수 없습니다.')
        if order['order_status'] != 'PAID':
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '결제 완료 후 출고 전 주문만 취소를 준비할 수 있습니다.')
        # 기존 A의 결제 완료 기준만 확인한다. 금액 계산·결제 상태 전이는 A 책임이다.
        cursor.execute("SELECT payment_id FROM payments WHERE order_id=%s AND payment_status='PAID' LIMIT 1 FOR UPDATE", (order_id,))
        if cursor.fetchone() is None:
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '결제 완료 기록을 확인해주세요.')
        cursor.execute('SELECT fulfillment_status, shipped_at, arrived_at, inspected_at, completed_at '
                       'FROM fulfillments WHERE order_id=%s ORDER BY fulfillment_id FOR UPDATE', (order_id,))
        deliveries = cursor.fetchall()
        if len(deliveries) > 1 or any(row['fulfillment_status'] != 'PREPARING' or
            any(row[field] is not None for field in ('shipped_at','arrived_at','inspected_at','completed_at')) for row in deliveries):
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '출고 진행 기록이 있거나 확인이 필요한 배송입니다.')
        cursor.execute("SELECT inventory_reservation_id FROM inventory_reservations WHERE order_id=%s "
                       "AND (reservation_status='CONSUMED' OR consumed_at IS NOT NULL) LIMIT 1 FOR UPDATE", (order_id,))
        if cursor.fetchone() is not None:
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '이미 출고 재고 처리 기록이 있습니다.')
    # 검증된 고객 ID를 전달하는 호출자가 잠금 해제 및 A/B/D 전체 처리를 책임진다.
    return {'order_id':order_id,'customer_id':customer_id,'request_id':request_id.strip(),'reason':reason.strip()}


def read_customer_cancel_mock_result(db, *, order_id: int, customer: CustomerScope):
    """응답 유실 시 본인 주문의 모의 취소 금융 기록만 조회한다.

    읽기 전용 결과는 최종 취소 완료나 재실행 허가가 아니다. 기록이 없더라도
    진행 중 트랜잭션이 있을 수 있으므로 새 환불 실행을 자동 결정하지 않는다.
    """
    if (not isinstance(customer, CustomerScope) or type(customer.customer_id) is not int
            or customer.customer_id < 1 or type(order_id) is not int or order_id < 1):
        raise OrderReadError(400, 'INVALID_INPUT', '조회 정보를 확인해주세요.')
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute('SELECT order_id, order_status, canceled_at FROM orders WHERE order_id=%s AND customer_id=%s',
                       (order_id, customer.customer_id))
        order = cursor.fetchone()
        if order is None:
            raise OrderReadError(404, 'NOT_FOUND', '주문을 찾을 수 없습니다.')
        # 외부 키·요청 키·내부 오류·다른 유형의 환불은 반환하지 않는다.
        cursor.execute('SELECT r.refund_id, r.refund_status, r.refund_amount, r.requested_at, r.completed_at, r.failed_at '
                       'FROM refunds r JOIN payments p ON p.payment_id=r.payment_id AND p.order_id=r.order_id '
                       "WHERE r.order_id=%s AND r.refund_type='ORDER_CANCEL' AND r.return_request_id IS NULL "
                       "AND p.payment_method='MOCK' ORDER BY r.requested_at DESC, r.refund_id DESC", (order_id,))
        records = cursor.fetchall()
    fields = ('refund_id', 'refund_status', 'refund_amount', 'requested_at', 'completed_at', 'failed_at')
    return {'order_id': order['order_id'], 'order_status': order['order_status'],
            'canceled_at': order['canceled_at'],
            'refunds': [{field: row[field] for field in fields} for row in records],
            'is_mock': True, 'completion_confirmed': False}


def stage_customer_order_cancel_mock(db, *, order_id: int, customer: CustomerScope,
                                    request_id: str, reason: str):
    """최초 취소의 C/A 내부 단계를 연결한다. D/B 처리 전 저장 확정은 금지한다.

    검증된 CustomerScope만 사용한다. 재전송 결과 조회나 실행 API가 아니며,
    호출자는 동일 연결에서 남은 업무를 완료하거나 전체 rollback해야 한다.
    """
    from fastapi import HTTPException
    if (not isinstance(customer, CustomerScope) or type(customer.customer_id) is not int
            or customer.customer_id < 1 or type(order_id) is not int or order_id < 1
            or not isinstance(request_id, str) or not request_id.strip() or len(request_id) > 100
            or not isinstance(reason, str) or not reason.strip() or len(reason.strip()) > 255):
        raise OrderReadError(400, 'INVALID_INPUT', '취소 요청 정보를 확인해주세요.')
    prepared = prepare_customer_order_cancel(db, order_id=order_id, customer_id=customer.customer_id,
                                            request_id=request_id, reason=reason)
    try:
        refund = cancel_paid_order_mock(db, **prepared)
        transition = mark_order_canceled_mock(db, order_id=prepared['order_id'],
                                             customer_id=prepared['customer_id'],
                                             refund_id=refund['refund_id'], reason=prepared['reason'])
    except HTTPException as error:
        raise OrderReadError(error.status_code, error.detail['code'], error.detail['message']) from error
    # 반환한 상태는 미커밋 단계다. API의 주문 취소 완료 응답으로 사용하지 않는다.
    return {'order_id': transition['order_id'], 'refund_id': refund['refund_id'],
            'is_mock': True, 'requires_inventory_release': True, 'completed': False}


def prepare_approved_return_refund(db, *, return_request_id: int, request_id: str, employee: dict):
    """A 호출 인자만 준비한다. 호출자가 트랜잭션을 소유하며 이 함수는 환불하지 않는다."""
    if not any(role['role_code'] == 'HQ_STAFF' for role in employee['roles']):
        raise OrderReadError(403, 'FORBIDDEN', '반품 환불 연결 준비 권한이 없습니다.')
    if return_request_id < 1 or not request_id.strip() or len(request_id) > 100:
        raise OrderReadError(400, 'INVALID_INPUT', '요청 정보를 확인해주세요.')
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        # 주문 → 접수 순서로 잠근다. 환불 금액·결제 기록 검증은 A가 담당한다.
        cursor.execute('SELECT order_id FROM return_requests WHERE return_request_id=%s', (return_request_id,))
        reference = cursor.fetchone()
        if reference is None:
            raise OrderReadError(404, 'NOT_FOUND', '반품 접수를 찾을 수 없습니다.')
        order_id = reference['order_id']
        cursor.execute('SELECT order_status, purchase_confirmed_at, pickup_branch_id FROM orders WHERE order_id=%s FOR UPDATE', (order_id,))
        order = cursor.fetchone()
        cursor.execute('SELECT order_id, request_status FROM return_requests WHERE return_request_id=%s FOR UPDATE', (return_request_id,))
        request = cursor.fetchone()
        if order is None or request is None or request['order_id'] != order_id:
            raise OrderReadError(404, 'NOT_FOUND', '반품 주문을 찾을 수 없습니다.')
        if request['request_status'] != 'APPROVED' or order['order_status'] != 'COMPLETED' or order['purchase_confirmed_at'] is not None:
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '수령 후 구매 미확정인 최종 승인 반품만 준비할 수 있습니다.')
        cursor.execute("SELECT after_sales_inspection_id FROM after_sales_inspections WHERE return_request_id=%s "
                       "AND inspection_stage='HEADQUARTERS' AND inspection_decision='ACCEPTED' FOR UPDATE", (return_request_id,))
        if cursor.fetchone() is None:
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '본사 최종 승인 검수 기록이 필요합니다.')
        cursor.execute("SELECT pickup_id FROM pickups WHERE order_id=%s AND branch_id=%s "
                       "AND pickup_status='COMPLETED' AND picked_up_at IS NOT NULL FOR UPDATE", (order_id, order['pickup_branch_id']))
        if cursor.fetchone() is None:
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '실제 수령 완료 기록을 확인해주세요.')
        cursor.execute('SELECT order_item_id, quantity FROM order_items WHERE order_id=%s ORDER BY order_item_id FOR UPDATE', (order_id,))
        items = cursor.fetchall()
        cursor.execute('SELECT order_item_id, quantity FROM return_items WHERE return_request_id=%s ORDER BY order_item_id FOR UPDATE', (return_request_id,))
        returned = cursor.fetchall()
        expected = [(item['order_item_id'], item['quantity']) for item in items]
        actual = [(item['order_item_id'], item['quantity']) for item in returned]
        if not expected or any(quantity < 1 for _, quantity in expected) or expected != actual:
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '전체 주문 반품 항목·수량을 확인해주세요.')
    # 준비 결과는 실행 허가·성공 응답이 아니다. 실제 실행 권한은 별도로 확정해야 한다.
    return {'order_id':order_id, 'return_request_id':return_request_id,
            'employee_id':employee['employee_id'], 'request_id':request_id.strip()}


@router.post('/staff/returns/{return_request_id}/decision')
def decide_staff_return(body: ReturnDecisionRequest, return_request_id: int = Path(..., ge=1),
                        employee=Depends(current_employee), db=Depends(get_db)):
    """본사 검수 후 최종 결정만 기록한다. 승인과 환불 성공은 분리한다."""
    if not any(role['role_code'] == 'HQ_STAFF' for role in employee['roles']):
        raise OrderReadError(403, 'FORBIDDEN', '반품 최종 결정 권한이 없습니다.')
    if (body.decision == 'REJECTED') != (body.rejection_reason is not None):
        raise OrderReadError(400, 'INVALID_INPUT', '거절할 때만 거절 사유를 입력해주세요.')
    payload = {'return_request_id': return_request_id, **body.model_dump(exclude={'request_id'})}
    try:
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            # 기존 검수 저장과 같은 잠금 순서로 최초 결정과 요청 재전송을 직렬화한다.
            cursor.execute('SELECT employee_id FROM employees WHERE employee_id=%s FOR UPDATE', (employee['employee_id'],))
            cursor.execute('SELECT request_status FROM return_requests WHERE return_request_id=%s FOR UPDATE', (return_request_id,))
            row = cursor.fetchone()
            if row is None:
                raise OrderReadError(404, 'NOT_FOUND', '반품 접수를 찾을 수 없습니다.')
            cursor.execute("SELECT after_data FROM audit_logs WHERE actor_employee_id=%s AND action_code='RETURN_DECIDE' "
                           "AND entity_type='RETURN_REQUEST' AND request_id=%s", (employee['employee_id'], body.request_id))
            prior = cursor.fetchone()
            if prior:
                stored = json.loads(prior['after_data']) if isinstance(prior['after_data'], str) else prior['after_data']
                if stored != payload:
                    raise OrderReadError(409, 'ALREADY_PROCESSED', '같은 요청의 내용이 다릅니다.')
                db.rollback()
                return {'data': {'return_request_id':return_request_id, 'request_status':body.decision}, 'message':'이미 기록된 반품 결정입니다.'}
            if row['request_status'] != 'INSPECTING':
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '검수 중인 반품만 최종 결정할 수 있습니다.')
            cursor.execute("SELECT after_sales_inspection_id, inspection_decision FROM after_sales_inspections "
                           "WHERE return_request_id=%s AND inspection_stage='HEADQUARTERS' FOR UPDATE", (return_request_id,))
            inspection = cursor.fetchone()
            if inspection is None or inspection['inspection_decision'] != 'PENDING':
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '판정 대기 중인 본사 검수 기록이 필요합니다.')
            cursor.execute('UPDATE after_sales_inspections SET inspection_decision=%s WHERE after_sales_inspection_id=%s',
                           ('ACCEPTED' if body.decision == 'APPROVED' else 'REJECTED', inspection['after_sales_inspection_id']))
            cursor.execute('UPDATE return_requests SET request_status=%s, rejection_reason=%s, handled_by_employee_id=%s, '
                           'processed_at=CURRENT_TIMESTAMP WHERE return_request_id=%s',
                           (body.decision, body.rejection_reason, employee['employee_id'], return_request_id))
            cursor.execute("INSERT INTO audit_logs (actor_type, actor_employee_id, action_code, entity_type, entity_id, before_data, after_data, request_id) "
                           "VALUES ('EMPLOYEE',%s,'RETURN_DECIDE','RETURN_REQUEST',%s,%s,%s,%s)",
                           (employee['employee_id'], return_request_id, json.dumps({'request_status':row['request_status'],
                            'after_sales_inspection_id':inspection['after_sales_inspection_id']}), json.dumps(payload, ensure_ascii=False), body.request_id))
        db.commit()
        return {'data': {'return_request_id':return_request_id, 'request_status':body.decision},
                'message':'반품 최종 결정이 기록되었습니다. 환불 완료가 아닙니다.'}
    except Exception:
        db.rollback()
        raise


class ReturnCompleteMockRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')
    request_id: str = Field(min_length=1, max_length=100)
    resale_confirmed: Literal[True]


@router.post('/staff/returns/{return_request_id}/complete-mock')
def complete_staff_return_mock(body: ReturnCompleteMockRequest, return_request_id: int = Path(..., ge=1),
                               employee=Depends(current_employee), db=Depends(get_db)):
    """정상 재판매 전체 반품의 D 복원·A 모의 환불·C 완료를 함께 저장한다."""
    from .order import refund_return_order_mock
    from fastapi import HTTPException
    if not any(r['role_code']=='HQ_STAFF' for r in employee['roles']):
        raise OrderReadError(403,'FORBIDDEN','본사 반품 완료 권한이 없습니다.')
    payload={'return_request_id':return_request_id,'resale_confirmed':True}
    try:
        if db.get_autocommit():
            raise OrderReadError(500,'INTERNAL_ERROR','트랜잭션 설정을 확인해주세요.')
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute('SELECT order_id FROM return_requests WHERE return_request_id=%s',(return_request_id,))
            reference=cursor.fetchone()
            if reference is None:
                raise OrderReadError(404,'NOT_FOUND','반품 접수를 찾을 수 없습니다.')
            order_id=reference['order_id']
            cursor.execute('SELECT coupon_discount,points_used FROM orders WHERE order_id=%s FOR UPDATE',(order_id,))
            order=cursor.fetchone()
            if order is None:
                raise OrderReadError(404,'NOT_FOUND','주문을 찾을 수 없습니다.')
            cursor.execute('SELECT order_id,request_status FROM return_requests WHERE return_request_id=%s FOR UPDATE',(return_request_id,))
            request=cursor.fetchone()
            if request is None or request['order_id']!=order_id:
                raise OrderReadError(409,'INVALID_STATE_TRANSITION','반품 주문이 일치하지 않습니다.')
            cursor.execute("SELECT after_data FROM audit_logs WHERE action_code='RETURN_MOCK_COMPLETE' AND actor_employee_id=%s AND request_id=%s",(employee['employee_id'],body.request_id))
            prior=cursor.fetchone()
            if prior:
                stored=json.loads(prior['after_data']) if isinstance(prior['after_data'],str) else prior['after_data']
                if stored['request']!=payload:
                    raise OrderReadError(409,'ALREADY_PROCESSED','같은 요청의 내용이 다릅니다.')
                db.rollback()
                return {'data':{**stored['result'],'replayed':True}}
            cursor.execute("SELECT after_data FROM audit_logs WHERE action_code='RETURN_MOCK_COMPLETE' AND entity_type='return_requests' AND entity_id=%s ORDER BY audit_log_id DESC LIMIT 1",(return_request_id,))
            completed=cursor.fetchone()
            if completed:
                stored=json.loads(completed['after_data']) if isinstance(completed['after_data'],str) else completed['after_data']
                db.rollback()
                return {'data':{**stored['result'],'replayed':True}}
            if order['coupon_discount']!=0 or order['points_used']!=0:
                raise OrderReadError(409,'INVALID_STATE_TRANSITION','혜택 사용 주문은 B 연동 후 처리할 수 있습니다.')
            cursor.execute("SELECT refund_id FROM refunds WHERE order_id=%s AND refund_status<>'CANCELED' LIMIT 1 FOR UPDATE",(order_id,))
            if cursor.fetchone() is not None:
                raise OrderReadError(409,'ALREADY_PROCESSED','기존 환불 기록을 확인해주세요.')
            prepared=prepare_approved_return_refund(db,return_request_id=return_request_id,request_id=body.request_id,employee=employee)
            restore_return_inventory(db,order_id=order_id,return_request_id=return_request_id,
                                     employee_id=employee['employee_id'],resale_confirmed=True)
            refund=refund_return_order_mock(db,**prepared)
            if (refund.get('order_id')!=order_id or refund.get('return_request_id')!=return_request_id
                    or refund.get('refund_status')!='SUCCEEDED' or refund.get('is_mock') is not True):
                raise OrderReadError(500,'INTERNAL_ERROR','모의 환불 결과를 확인하지 못했습니다.')
            cursor.execute("UPDATE return_requests SET request_status='COMPLETED',processed_at=CURRENT_TIMESTAMP WHERE return_request_id=%s AND request_status='APPROVED'",(return_request_id,))
            if cursor.rowcount!=1:
                raise OrderReadError(409,'INVALID_STATE_TRANSITION','반품 상태가 변경되었습니다.')
            result={'order_id':order_id,'return_request_id':return_request_id,'request_status':'COMPLETED',
                    'refund_id':refund['refund_id'],'is_mock':True,'completed':True,'replayed':False}
            cursor.execute("INSERT INTO audit_logs (actor_type,actor_employee_id,action_code,entity_type,entity_id,before_data,after_data,request_id) VALUES ('EMPLOYEE',%s,'RETURN_MOCK_COMPLETE','return_requests',%s,%s,%s,%s)",
                           (employee['employee_id'],return_request_id,json.dumps({'request_status':'APPROVED'}),json.dumps(jsonable_encoder({'request':payload,'result':result}),ensure_ascii=False),body.request_id))
        db.commit()
        return {'data':result,'message':'정상 반품 재고 복원과 모의 환불이 완료되었습니다.'}
    except HTTPException as error:
        db.rollback()
        raise OrderReadError(error.status_code,error.detail['code'],error.detail['message']) from error
    except Exception:
        db.rollback()
        raise


class ArrivalConfirmRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')
    request_id: str = Field(min_length=1, max_length=100)
    received_product: Literal[True]


@router.post('/staff/fulfillments/{fulfillment_id}/arrival')
def confirm_staff_arrival(body: ArrivalConfirmRequest, fulfillment_id: int = Path(..., ge=1),
                          employee=Depends(current_employee), db=Depends(get_db)):
    """실제 도착만 기록한다. 정상 검수·D 보관·수령 가능 처리는 별도다."""
    if not {r['role_code'] for r in employee['roles']} & {'BRANCH_STAFF','BRANCH_MANAGER'}:
        raise OrderReadError(403,'FORBIDDEN','대리점 도착 확인 권한이 없습니다.')
    payload = {'fulfillment_id':fulfillment_id,'received_product':True}
    try:
        if db.get_autocommit():
            raise OrderReadError(500,'INTERNAL_ERROR','트랜잭션 설정을 확인해주세요.')
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute('SELECT order_id FROM fulfillments WHERE fulfillment_id=%s',(fulfillment_id,))
            reference=cursor.fetchone()
            if reference is None:
                raise OrderReadError(404,'NOT_FOUND','배송을 찾을 수 없습니다.')
            order_id=reference['order_id']
            cursor.execute('SELECT order_status,pickup_branch_id FROM orders WHERE order_id=%s FOR UPDATE',(order_id,))
            order=cursor.fetchone()
            cursor.execute('SELECT order_id,destination_branch_id,fulfillment_status,shipped_at,arrived_at '
                           'FROM fulfillments WHERE fulfillment_id=%s FOR UPDATE',(fulfillment_id,))
            delivery=cursor.fetchone()
            if order is None or delivery is None or delivery['order_id']!=order_id:
                raise OrderReadError(404,'NOT_FOUND','배송 주문을 찾을 수 없습니다.')
            branch=delivery['destination_branch_id']
            if branch not in {b['branch_id'] for b in employee['branches']}:
                raise OrderReadError(403,'FORBIDDEN','소속 대리점 배송만 확인할 수 있습니다.')
            if branch!=order['pickup_branch_id']:
                raise OrderReadError(409,'INVALID_STATE_TRANSITION','수령 대리점이 일치하지 않습니다.')
            cursor.execute("SELECT after_data FROM audit_logs WHERE actor_employee_id=%s AND action_code='ARRIVAL_COMPLETE' "
                           'AND request_id=%s',(employee['employee_id'],body.request_id))
            prior=cursor.fetchone()
            if prior:
                stored=json.loads(prior['after_data']) if isinstance(prior['after_data'],str) else prior['after_data']
                if stored['request']!=payload:
                    raise OrderReadError(409,'ALREADY_PROCESSED','같은 요청의 내용이 다릅니다.')
                db.rollback()
                return {'data':{**stored['result'],'replayed':True},'message':'이미 도착이 기록되었습니다.'}
            if delivery['arrived_at'] is not None:
                cursor.execute("SELECT after_data FROM audit_logs WHERE action_code='ARRIVAL_COMPLETE' "
                               "AND entity_type='fulfillments' AND entity_id=%s ORDER BY audit_log_id DESC LIMIT 1",(fulfillment_id,))
                completed=cursor.fetchone()
                if completed:
                    stored=json.loads(completed['after_data']) if isinstance(completed['after_data'],str) else completed['after_data']
                    db.rollback()
                    return {'data':{**stored['result'],'replayed':True},'message':'이미 도착이 기록되었습니다.'}
            if order['order_status']!='SHIPPING' or delivery['fulfillment_status']!='IN_TRANSIT' or delivery['shipped_at'] is None or delivery['arrived_at'] is not None:
                raise OrderReadError(409,'INVALID_STATE_TRANSITION','도착 확인 대상 상태가 아닙니다.')
            cursor.execute("UPDATE fulfillments SET fulfillment_status='ARRIVED',arrived_at=CURRENT_TIMESTAMP "
                           "WHERE fulfillment_id=%s AND fulfillment_status='IN_TRANSIT' AND arrived_at IS NULL",(fulfillment_id,))
            if cursor.rowcount!=1:
                raise OrderReadError(409,'INVALID_STATE_TRANSITION','배송 상태가 변경되었습니다.')
            cursor.execute('INSERT INTO fulfillment_status_history (fulfillment_id,previous_status,new_status,change_source,change_reason,actor_type,actor_employee_id) '
                           "VALUES (%s,'IN_TRANSIT','ARRIVED','STAFF_ARRIVAL',%s,'EMPLOYEE',%s)",(fulfillment_id,f'order_id={order_id}',employee['employee_id']))
            cursor.execute('SELECT arrived_at FROM fulfillments WHERE fulfillment_id=%s',(fulfillment_id,))
            result={'order_id':order_id,'fulfillment_id':fulfillment_id,'fulfillment_status':'ARRIVED',
                    'arrived_at':cursor.fetchone()['arrived_at'],'replayed':False}
            cursor.execute('INSERT INTO audit_logs (actor_type,actor_employee_id,action_code,entity_type,entity_id,after_data,request_id) '
                           "VALUES ('EMPLOYEE',%s,'ARRIVAL_COMPLETE','fulfillments',%s,%s,%s)",
                           (employee['employee_id'],fulfillment_id,json.dumps(jsonable_encoder({'request':payload,'result':result}),ensure_ascii=False),body.request_id))
        db.commit()
        return {'data':result,'message':'도착이 기록되었습니다. 정상 검수와 수령 가능 처리는 아직 완료되지 않았습니다.'}
    except Exception:
        db.rollback()
        raise


class NormalInspectionRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')
    request_id: str = Field(min_length=1, max_length=100)
    all_items_normal: Literal[True]


@router.post('/staff/fulfillments/{fulfillment_id}/inspection')
def confirm_staff_normal_inspection(body: NormalInspectionRequest, fulfillment_id: int = Path(..., ge=1),
                          employee=Depends(current_employee), db=Depends(get_db)):
    """전체 정상 검수만 기록한다. D 보관·수령 가능 처리는 별도다."""
    if not {r['role_code'] for r in employee['roles']} & {'BRANCH_STAFF','BRANCH_MANAGER'}:
        raise OrderReadError(403,'FORBIDDEN','대리점 검수 권한이 없습니다.')
    payload = {'fulfillment_id':fulfillment_id,'all_items_normal':True}
    try:
        if db.get_autocommit():
            raise OrderReadError(500,'INTERNAL_ERROR','트랜잭션 설정을 확인해주세요.')
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute('SELECT order_id FROM fulfillments WHERE fulfillment_id=%s',(fulfillment_id,))
            reference=cursor.fetchone()
            if reference is None:
                raise OrderReadError(404,'NOT_FOUND','배송을 찾을 수 없습니다.')
            order_id=reference['order_id']
            cursor.execute('SELECT order_status,pickup_branch_id FROM orders WHERE order_id=%s FOR UPDATE',(order_id,))
            order=cursor.fetchone()
            cursor.execute('SELECT order_id,destination_branch_id,fulfillment_status,shipped_at,arrived_at,inspected_at,completed_at '
                           'FROM fulfillments WHERE fulfillment_id=%s FOR UPDATE',(fulfillment_id,))
            delivery=cursor.fetchone()
            if order is None or delivery is None or delivery['order_id']!=order_id:
                raise OrderReadError(404,'NOT_FOUND','배송 주문을 찾을 수 없습니다.')
            branch=delivery['destination_branch_id']
            if branch not in {b['branch_id'] for b in employee['branches']}:
                raise OrderReadError(403,'FORBIDDEN','소속 대리점 배송만 확인할 수 있습니다.')
            if branch!=order['pickup_branch_id']:
                raise OrderReadError(409,'INVALID_STATE_TRANSITION','수령 대리점이 일치하지 않습니다.')
            cursor.execute("SELECT after_data FROM audit_logs WHERE actor_employee_id=%s AND action_code='NORMAL_INSPECTION' "
                           'AND request_id=%s',(employee['employee_id'],body.request_id))
            prior=cursor.fetchone()
            if prior:
                stored=json.loads(prior['after_data']) if isinstance(prior['after_data'],str) else prior['after_data']
                if stored['request']!=payload:
                    raise OrderReadError(409,'ALREADY_PROCESSED','같은 요청의 내용이 다릅니다.')
                db.rollback()
                return {'data':{**stored['result'],'replayed':True},'message':'이미 정상 검수가 기록되었습니다.'}
            if delivery['inspected_at'] is not None:
                cursor.execute("SELECT after_data FROM audit_logs WHERE action_code='NORMAL_INSPECTION' "
                               "AND entity_type='fulfillments' AND entity_id=%s ORDER BY audit_log_id DESC LIMIT 1",(fulfillment_id,))
                completed=cursor.fetchone()
                if completed:
                    stored=json.loads(completed['after_data']) if isinstance(completed['after_data'],str) else completed['after_data']
                    db.rollback()
                    return {'data':{**stored['result'],'replayed':True},'message':'이미 정상 검수가 기록되었습니다.'}
            if order['order_status']!='SHIPPING' or delivery['fulfillment_status']!='ARRIVED' or delivery['shipped_at'] is None or delivery['arrived_at'] is None or delivery['inspected_at'] is not None or delivery['completed_at'] is not None:
                raise OrderReadError(409,'INVALID_STATE_TRANSITION','정상 검수 대상 상태가 아닙니다.')
            # 전체 주문과 배송 항목의 ID·수량이 일치할 때만 정상 검수를 기록한다.
            cursor.execute('SELECT order_item_id,quantity FROM order_items WHERE order_id=%s ORDER BY order_item_id FOR UPDATE',(order_id,))
            items=cursor.fetchall()
            cursor.execute('SELECT order_id,order_item_id,quantity FROM fulfillment_items WHERE fulfillment_id=%s ORDER BY order_item_id FOR UPDATE',(fulfillment_id,))
            shipped=cursor.fetchall()
            if not items or len(items)!=len(shipped) or any(x['order_id']!=order_id for x in shipped) or any(x['quantity']<=0 for x in items) or [(x['order_item_id'],x['quantity']) for x in items]!=[(x['order_item_id'],x['quantity']) for x in shipped]:
                raise OrderReadError(409,'INVALID_STATE_TRANSITION','전체 주문 상품과 배송 수량을 확인해주세요.')
            cursor.execute("UPDATE fulfillments SET fulfillment_status='INSPECTING',inspected_at=CURRENT_TIMESTAMP "
                           "WHERE fulfillment_id=%s AND fulfillment_status='ARRIVED' AND inspected_at IS NULL",(fulfillment_id,))
            if cursor.rowcount!=1:
                raise OrderReadError(409,'INVALID_STATE_TRANSITION','배송 상태가 변경되었습니다.')
            cursor.execute('INSERT INTO fulfillment_status_history (fulfillment_id,previous_status,new_status,change_source,change_reason,actor_type,actor_employee_id) '
                           "VALUES (%s,'ARRIVED','INSPECTING','STAFF_INSPECTION',%s,'EMPLOYEE',%s)",(fulfillment_id,f'order_id={order_id}',employee['employee_id']))
            cursor.execute('SELECT inspected_at FROM fulfillments WHERE fulfillment_id=%s',(fulfillment_id,))
            result={'order_id':order_id,'fulfillment_id':fulfillment_id,'fulfillment_status':'INSPECTING',
                    'inspected_at':cursor.fetchone()['inspected_at'],'replayed':False}
            cursor.execute('INSERT INTO audit_logs (actor_type,actor_employee_id,action_code,entity_type,entity_id,after_data,request_id) '
                           "VALUES ('EMPLOYEE',%s,'NORMAL_INSPECTION','fulfillments',%s,%s,%s)",
                           (employee['employee_id'],fulfillment_id,json.dumps(jsonable_encoder({'request':payload,'result':result}),ensure_ascii=False),body.request_id))
        db.commit()
        return {'data':result,'message':'정상 검수가 기록되었습니다. 재고 보관과 수령 가능 처리는 아직 완료되지 않았습니다.'}
    except Exception:
        db.rollback()
        raise


def prepare_staff_pickup_ready(db, *, fulfillment_id: int, employee):
    """D 보관 처리 후 C 수령 가능 전이의 전제만 검사한다. 변경·commit은 하지 않는다.

    최상위 트랜잭션에서 D 함수와 함께 호출해야 하며 보관 기록 존재만으로
    이번 요청의 D 처리 성공이나 전체 업무 완료를 주장하지 않는다.
    """
    if fulfillment_id <= 0:
        raise OrderReadError(400, 'INVALID_INPUT', '배송 번호를 확인해주세요.')
    if not {r['role_code'] for r in employee['roles']} & {'BRANCH_STAFF', 'BRANCH_MANAGER'}:
        raise OrderReadError(403, 'FORBIDDEN', '대리점 수령 준비 권한이 없습니다.')
    if db.get_autocommit():
        raise OrderReadError(500, 'INTERNAL_ERROR', '트랜잭션 설정을 확인해주세요.')
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute('SELECT order_id FROM fulfillments WHERE fulfillment_id=%s', (fulfillment_id,))
        reference = cursor.fetchone()
        if reference is None:
            raise OrderReadError(404, 'NOT_FOUND', '배송을 찾을 수 없습니다.')
        order_id = reference['order_id']
        # 기존 도착·검수와 같은 순서로 잠그며 종료는 최상위 호출자가 담당한다.
        cursor.execute('SELECT order_status,pickup_branch_id FROM orders WHERE order_id=%s FOR UPDATE', (order_id,))
        order = cursor.fetchone()
        cursor.execute('SELECT order_id,destination_branch_id,fulfillment_status,shipped_at,arrived_at,inspected_at,completed_at '
                       'FROM fulfillments WHERE fulfillment_id=%s FOR UPDATE', (fulfillment_id,))
        delivery = cursor.fetchone()
        if order is None or delivery is None or delivery['order_id'] != order_id:
            raise OrderReadError(404, 'NOT_FOUND', '배송 주문을 찾을 수 없습니다.')
        branch_id = delivery['destination_branch_id']
        if branch_id not in {b['branch_id'] for b in employee['branches']}:
            raise OrderReadError(403, 'FORBIDDEN', '소속 대리점만 처리할 수 있습니다.')
        if (branch_id != order['pickup_branch_id'] or order['order_status'] != 'SHIPPING'
                or delivery['fulfillment_status'] != 'INSPECTING'
                or any(delivery[field] is None for field in ('shipped_at', 'arrived_at', 'inspected_at'))
                or delivery['completed_at'] is not None):
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '정상 검수 기록과 수령 대리점을 확인해주세요.')
        cursor.execute('SELECT order_item_id,quantity FROM order_items WHERE order_id=%s ORDER BY order_item_id FOR UPDATE', (order_id,))
        items = cursor.fetchall()
        cursor.execute('SELECT fulfillment_item_id,order_id,order_item_id,quantity FROM fulfillment_items '
                       'WHERE fulfillment_id=%s ORDER BY order_item_id FOR UPDATE', (fulfillment_id,))
        shipped = cursor.fetchall()
        if (not items or len(items) != len(shipped) or any(x['order_id'] != order_id for x in shipped)
                or any(x['quantity'] <= 0 for x in items)
                or [(x['order_item_id'], x['quantity']) for x in items] != [(x['order_item_id'], x['quantity']) for x in shipped]):
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '전체 주문 상품과 배송 수량을 확인해주세요.')
        cursor.execute('SELECT ph.fulfillment_item_id,ph.branch_id,ph.quantity,ph.holding_status,ph.received_at,ph.ready_at,ph.picked_up_at '
                       'FROM pickup_holdings ph JOIN fulfillment_items fi ON fi.fulfillment_item_id=ph.fulfillment_item_id '
                       'WHERE fi.fulfillment_id=%s ORDER BY ph.fulfillment_item_id FOR UPDATE', (fulfillment_id,))
        holdings = cursor.fetchall()
        expected = {x['fulfillment_item_id']: x['quantity'] for x in shipped}
        if (len(holdings) != len(expected) or {x['fulfillment_item_id'] for x in holdings} != set(expected)
                or any(x['branch_id'] != branch_id or x['quantity'] != expected.get(x['fulfillment_item_id'])
                       or x['holding_status'] != 'READY_FOR_PICKUP' or x['received_at'] is None
                       or x['ready_at'] is None or x['picked_up_at'] is not None for x in holdings)):
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', 'D의 전체 상품 보관 준비가 필요합니다.')
    return {'order_id': order_id, 'fulfillment_id': fulfillment_id, 'branch_id': branch_id,
            'employee_id': employee['employee_id']}


def record_staff_pickup_ready(db, *, fulfillment_id: int, employee):
    """D 보관 후 C 기록과 A 전이를 연결한다. 최상위 호출자가 commit/rollback한다.

    공개 API가 아니며 자체 재전송 처리도 하지 않는다. 최상위 실행 API는
    주문 잠금·요청 완료 기록 확인 후 D 처리를 먼저 실행해야 한다.
    """
    prepared = prepare_staff_pickup_ready(db, fulfillment_id=fulfillment_id, employee=employee)
    order_id, branch_id = prepared['order_id'], prepared['branch_id']
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute('SELECT pickup_id,branch_id,pickup_status,picked_up_at,ready_at FROM pickups '
                       'WHERE order_id=%s FOR UPDATE', (order_id,))
        pickup = cursor.fetchone()
        if pickup is not None and (pickup['branch_id'] != branch_id or pickup['pickup_status'] != 'PREPARING'
                                   or pickup['picked_up_at'] is not None or pickup['ready_at'] is not None):
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '수령 준비 기록을 확인해주세요.')
        if pickup is None:
            # 보관 기한·정책을 자동 설정하지 않고 기존 배송 도착 시각을 사용한다.
            cursor.execute("INSERT INTO pickups (order_id,branch_id,handled_by_employee_id,pickup_status,arrived_at,ready_at) "
                           "SELECT order_id,destination_branch_id,%s,'READY_FOR_PICKUP',arrived_at,CURRENT_TIMESTAMP "
                           'FROM fulfillments WHERE fulfillment_id=%s', (employee['employee_id'], fulfillment_id))
            pickup_id = cursor.lastrowid
            previous_status = None
        else:
            pickup_id = pickup['pickup_id']
            previous_status = 'PREPARING'
            cursor.execute("UPDATE pickups p JOIN fulfillments f ON f.fulfillment_id=%s "
                           "SET p.pickup_status='READY_FOR_PICKUP',p.arrived_at=f.arrived_at,p.ready_at=CURRENT_TIMESTAMP,p.handled_by_employee_id=%s "
                           "WHERE p.pickup_id=%s AND p.pickup_status='PREPARING' AND p.ready_at IS NULL",
                           (fulfillment_id, employee['employee_id'], pickup_id))
        if cursor.rowcount != 1:
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '수령 준비 상태가 변경되었습니다.')
        cursor.execute("UPDATE fulfillments SET fulfillment_status='READY_FOR_PICKUP' "
                       "WHERE fulfillment_id=%s AND fulfillment_status='INSPECTING' AND inspected_at IS NOT NULL",
                       (fulfillment_id,))
        if cursor.rowcount != 1:
            raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '배송 상태가 변경되었습니다.')
        reason = f'order_id={order_id}, fulfillment_id={fulfillment_id}, pickup_id={pickup_id}'
        cursor.execute("INSERT INTO fulfillment_status_history (fulfillment_id,previous_status,new_status,change_source,change_reason,actor_type,actor_employee_id) "
                       "VALUES (%s,'INSPECTING','READY_FOR_PICKUP','STAFF_ARRIVAL',%s,'EMPLOYEE',%s)",
                       (fulfillment_id, reason, employee['employee_id']))
        cursor.execute("INSERT INTO pickup_status_history (pickup_id,previous_status,new_status,change_source,change_reason,actor_type,actor_employee_id) "
                       "VALUES (%s,%s,'READY_FOR_PICKUP','STAFF_ARRIVAL',%s,'EMPLOYEE',%s)",
                       (pickup_id, previous_status, reason, employee['employee_id']))
    return transition_pickup_order(db, order_id=order_id, fulfillment_id=fulfillment_id,
                                   pickup_id=pickup_id, branch_id=branch_id, employee=employee, completed=False)


class PickupReadyRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')
    request_id: str = Field(min_length=1, max_length=100)
    confirmed: Literal[True]


@router.post('/staff/fulfillments/{fulfillment_id}/ready')
def confirm_staff_pickup_ready(body: PickupReadyRequest, fulfillment_id: int = Path(..., ge=1),
                              employee=Depends(current_employee), db=Depends(get_db)):
    """D 보관·C 기록·A 상태를 같은 연결로 저장한다. 인증·알림은 별도다."""
    from fastapi import HTTPException
    if not {r['role_code'] for r in employee['roles']} & {'BRANCH_STAFF','BRANCH_MANAGER'}:
        raise OrderReadError(403,'FORBIDDEN','대리점 수령 준비 권한이 없습니다.')
    payload = {'fulfillment_id':fulfillment_id,'confirmed':True}
    try:
        if db.get_autocommit():
            raise OrderReadError(500,'INTERNAL_ERROR','트랜잭션 설정을 확인해주세요.')
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute('SELECT order_id FROM fulfillments WHERE fulfillment_id=%s',(fulfillment_id,))
            reference = cursor.fetchone()
            if reference is None:
                raise OrderReadError(404,'NOT_FOUND','배송을 찾을 수 없습니다.')
            order_id = reference['order_id']
            cursor.execute('SELECT pickup_branch_id FROM orders WHERE order_id=%s FOR UPDATE',(order_id,))
            order = cursor.fetchone()
            cursor.execute('SELECT order_id,destination_branch_id FROM fulfillments WHERE fulfillment_id=%s FOR UPDATE',(fulfillment_id,))
            delivery = cursor.fetchone()
            if order is None or delivery is None or delivery['order_id'] != order_id:
                raise OrderReadError(404,'NOT_FOUND','배송 주문을 찾을 수 없습니다.')
            branch_id = delivery['destination_branch_id']
            if branch_id not in {b['branch_id'] for b in employee['branches']}:
                raise OrderReadError(403,'FORBIDDEN','소속 대리점만 처리할 수 있습니다.')
            if branch_id != order['pickup_branch_id']:
                raise OrderReadError(409,'INVALID_STATE_TRANSITION','수령 대리점이 일치하지 않습니다.')
            cursor.execute("SELECT after_data FROM audit_logs WHERE action_code='PICKUP_READY_COMPLETE' AND actor_employee_id=%s AND request_id=%s",(employee['employee_id'],body.request_id))
            prior = cursor.fetchone()
            if prior:
                stored = json.loads(prior['after_data']) if isinstance(prior['after_data'],str) else prior['after_data']
                if stored['request'] != payload:
                    raise OrderReadError(409,'ALREADY_PROCESSED','같은 요청의 내용이 다릅니다.')
                db.rollback()
                return {'data':{**stored['result'],'replayed':True}}
            cursor.execute("SELECT after_data FROM audit_logs WHERE action_code='PICKUP_READY_COMPLETE' AND entity_type='fulfillments' AND entity_id=%s ORDER BY audit_log_id DESC LIMIT 1",(fulfillment_id,))
            completed = cursor.fetchone()
            if completed:
                stored = json.loads(completed['after_data']) if isinstance(completed['after_data'],str) else completed['after_data']
                db.rollback()
                return {'data':{**stored['result'],'replayed':True}}
            prepare_pickup_holdings(db,order_id=order_id,fulfillment_id=fulfillment_id,branch_id=branch_id)
            result = {**record_staff_pickup_ready(db,fulfillment_id=fulfillment_id,employee=employee),'completed':True}
            cursor.execute("INSERT INTO audit_logs (actor_type,actor_employee_id,action_code,entity_type,entity_id,after_data,request_id) VALUES ('EMPLOYEE',%s,'PICKUP_READY_COMPLETE','fulfillments',%s,%s,%s)",
                           (employee['employee_id'],fulfillment_id,json.dumps(jsonable_encoder({'request':payload,'result':result}),ensure_ascii=False),body.request_id))
        db.commit()
        return {'data':result,'message':'수령 준비가 완료되었습니다. 인증과 실제 전달은 별도입니다.'}
    except HTTPException as error:
        db.rollback()
        raise OrderReadError(error.status_code,error.detail['code'],error.detail['message']) from error
    except Exception:
        db.rollback()
        raise


class DispatchConfirmRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')
    request_id: str = Field(min_length=1, max_length=100)
    confirmed: Literal[True]


@router.post('/staff/dispatch/{order_id}/confirm')
def confirm_staff_dispatch(body: DispatchConfirmRequest, order_id: int = Path(..., ge=1),
                           employee=Depends(current_employee), db=Depends(get_db)):
    """실제 출고 확인 후 D/C/A 변경과 완료 이력을 한 번에 확정한다."""
    from .c_dispatch import prepare_order_fulfillment, record_dispatched_fulfillment
    if not any(role['role_code'] == 'HQ_STAFF' for role in employee['roles']):
        raise OrderReadError(403, 'FORBIDDEN', '출고 실행 권한이 없습니다.')
    payload = {'order_id':order_id,'confirmed':True}
    try:
        if db.get_autocommit():
            raise OrderReadError(500, 'INTERNAL_ERROR', '트랜잭션 설정을 확인해주세요.')
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute('SELECT order_status FROM orders WHERE order_id=%s FOR UPDATE', (order_id,))
            if cursor.fetchone() is None:
                raise OrderReadError(404, 'NOT_FOUND', '주문을 찾을 수 없습니다.')
            cursor.execute("SELECT after_data FROM audit_logs WHERE actor_employee_id=%s "
                           "AND action_code='DISPATCH_COMPLETE' AND request_id=%s", (employee['employee_id'],body.request_id))
            prior = cursor.fetchone()
            if prior:
                stored = json.loads(prior['after_data']) if isinstance(prior['after_data'],str) else prior['after_data']
                if stored['request'] != payload:
                    raise OrderReadError(409, 'ALREADY_PROCESSED', '같은 요청의 내용이 다릅니다.')
                db.rollback()
                return {'data':{**stored['result'],'replayed':True},'message':'이미 출고가 기록되었습니다.'}
            cursor.execute("SELECT after_data FROM audit_logs WHERE action_code='DISPATCH_COMPLETE' "
                           "AND entity_type='orders' AND entity_id=%s ORDER BY audit_log_id DESC LIMIT 1", (order_id,))
            completed = cursor.fetchone()
            if completed:
                stored = json.loads(completed['after_data']) if isinstance(completed['after_data'],str) else completed['after_data']
                db.rollback()
                return {'data':{**stored['result'],'replayed':True},'message':'이미 출고가 기록되었습니다.'}
        prepared = prepare_order_fulfillment(db,order_id=order_id,employee=employee)
        consume_order_inventory(db,order_id=order_id,employee_id=employee['employee_id'])
        record_dispatched_fulfillment(db,order_id=order_id,fulfillment_id=prepared['fulfillment_id'],employee=employee)
        transition = transition_dispatched_order(db,order_id=order_id,fulfillment_id=prepared['fulfillment_id'],employee=employee)
        result = {**transition,'fulfillment_number':prepared['fulfillment_number'],'completed':True,'replayed':False}
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute('INSERT INTO audit_logs (actor_type,actor_employee_id,action_code,entity_type,entity_id,after_data,request_id) '
                           "VALUES ('EMPLOYEE',%s,'DISPATCH_COMPLETE','orders',%s,%s,%s)",
                           (employee['employee_id'],order_id,json.dumps({'request':payload,'result':result},ensure_ascii=False),body.request_id))
        db.commit()
        return {'data':result,'message':'출고가 기록되었습니다.'}
    except Exception:
        db.rollback()
        raise


class MockOrderCancelRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')
    request_id: str = Field(min_length=1, max_length=100)
    reason: str = Field(min_length=1, max_length=255)


@router.post('/customer/{order_id}/cancel-mock')
def cancel_customer_order_mock(body: MockOrderCancelRequest, order_id: int = Path(..., ge=1),
                               scope: CustomerScope = Depends(authenticated_customer), db=Depends(get_db)):
    """혜택 미사용 주문의 모의 환불·취소·D 예약 해제를 하나의 트랜잭션으로 처리한다."""
    payload = {'order_id': order_id, 'reason': body.reason}
    try:
        if db.get_autocommit():
            raise OrderReadError(500, 'INTERNAL_ERROR', '트랜잭션 설정을 확인해주세요.')
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute('SELECT order_status, coupon_discount, points_used FROM orders '
                           'WHERE order_id=%s AND customer_id=%s FOR UPDATE', (order_id, scope.customer_id))
            order = cursor.fetchone()
            if order is None:
                raise OrderReadError(404, 'NOT_FOUND', '주문을 찾을 수 없습니다.')
            cursor.execute("SELECT entity_id, after_data FROM audit_logs WHERE actor_customer_id=%s "
                           "AND action_code='MOCK_CANCEL_COMPLETE' AND request_id=%s", (scope.customer_id, body.request_id))
            prior = cursor.fetchone()
            if prior:
                stored = json.loads(prior['after_data']) if isinstance(prior['after_data'], str) else prior['after_data']
                if stored['request'] != payload:
                    raise OrderReadError(409, 'ALREADY_PROCESSED', '같은 요청의 내용이 다릅니다.')
                db.rollback()
                return {'data': {**stored['result'], 'replayed': True}, 'message': '이미 모의 취소가 완료되었습니다.'}
            cursor.execute("SELECT after_data FROM audit_logs WHERE actor_customer_id=%s AND action_code='MOCK_CANCEL_COMPLETE' "
                           "AND entity_type='orders' AND entity_id=%s ORDER BY audit_log_id DESC LIMIT 1", (scope.customer_id, order_id))
            completed = cursor.fetchone()
            if completed:
                stored = json.loads(completed['after_data']) if isinstance(completed['after_data'], str) else completed['after_data']
                db.rollback()
                return {'data': {**stored['result'], 'replayed': True}, 'message': '이미 모의 취소가 완료되었습니다.'}
            if order['coupon_discount'] != 0 or order['points_used'] != 0:
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '혜택 복원 연결 전에는 혜택 사용 주문을 취소할 수 없습니다.')
            # 과거 부분 저장된 금융 결과를 자동 완료/재환불하지 않는다.
            cursor.execute("SELECT refund_id FROM refunds WHERE order_id=%s AND refund_status<>'CANCELED' LIMIT 1 FOR UPDATE", (order_id,))
            if cursor.fetchone() is not None:
                raise OrderReadError(409, 'ALREADY_PROCESSED', '기존 환불 처리 결과를 확인해주세요.')
        stage = stage_customer_order_cancel_mock(db, order_id=order_id, customer=scope,
                                                request_id=body.request_id, reason=body.reason)
        release_order_inventory(db, order_id=order_id, reason=body.reason)
        result = {'order_id': order_id, 'order_status': 'CANCELED', 'refund_id': stage['refund_id'],
                  'is_mock': True, 'completed': True, 'replayed': False}
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute('INSERT INTO audit_logs (actor_type, actor_customer_id, action_code, entity_type, '
                           'entity_id, after_data, request_id) '
                           "VALUES ('CUSTOMER',%s,'MOCK_CANCEL_COMPLETE','orders',%s,%s,%s)",
                           (scope.customer_id, order_id, json.dumps({'request': payload, 'result': result}, ensure_ascii=False), body.request_id))
        db.commit()
        return {'data': result, 'message': '모의 환불과 주문 취소가 완료되었습니다.'}
    except Exception:
        db.rollback()
        raise


class ReturnCreateRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')
    request_id: str = Field(min_length=1, max_length=100)
    return_reason_code: Literal['CUSTOMER_CHANGE', 'PRODUCT_DEFECT', 'WRONG_ITEM', 'OTHER']
    return_reason: str = Field(min_length=1)


@router.post('/customer/{order_id}/returns')
def create_customer_return(body: ReturnCreateRequest, order_id: int = Path(..., ge=1),
                           scope: CustomerScope = Depends(authenticated_customer), db=Depends(get_db)):
    """전체 주문을 접수만 기록한다. 환불·재고·혜택 변경은 각 담당 연결 후 수행한다."""
    payload = {'order_id': order_id, **body.model_dump(exclude={'request_id'})}
    try:
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            # 동일 고객의 요청 ID와 동일 주문의 접수/구매확정 경합을 각각 잠근다.
            cursor.execute('SELECT customer_id FROM customers WHERE customer_id=%s AND deleted_at IS NULL FOR UPDATE', (scope.customer_id,))
            if cursor.fetchone() is None:
                raise OrderReadError(403, 'FORBIDDEN', '접근 권한이 없습니다.')
            cursor.execute('SELECT order_status, pickup_branch_id, purchase_confirmed_at FROM orders '
                           'WHERE order_id=%s AND customer_id=%s FOR UPDATE', (order_id, scope.customer_id))
            order = cursor.fetchone()
            if order is None:
                raise OrderReadError(404, 'NOT_FOUND', '주문을 찾을 수 없습니다.')
            cursor.execute("SELECT entity_id, after_data FROM audit_logs WHERE actor_customer_id=%s "
                           "AND action_code='RETURN_CREATE' AND entity_type='RETURN_REQUEST' AND request_id=%s",
                           (scope.customer_id, body.request_id))
            prior = cursor.fetchone()
            if prior:
                stored = json.loads(prior['after_data']) if isinstance(prior['after_data'], str) else prior['after_data']
                if stored != payload:
                    raise OrderReadError(409, 'ALREADY_PROCESSED', '같은 요청의 내용이 다릅니다.')
                db.rollback()
                return {'data': {'return_request_id': prior['entity_id']}, 'message': '이미 접수된 반품입니다.'}
            if order['order_status'] != 'COMPLETED' or order['purchase_confirmed_at'] is not None:
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '수령 완료 후 구매확정 전에만 반품을 접수할 수 있습니다.')
            cursor.execute("SELECT pickup_id FROM pickups WHERE order_id=%s AND branch_id=%s "
                           "AND pickup_status='COMPLETED' AND picked_up_at IS NOT NULL FOR UPDATE",
                           (order_id, order['pickup_branch_id']))
            if cursor.fetchone() is None:
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '실제 수령 완료 기록을 확인해주세요.')
            # 완료 반품 또는 기존 환불도 전체 재접수를 차단한다. 실패 환불 복구는 A 업무다.
            cursor.execute("SELECT return_request_id FROM return_requests WHERE order_id=%s "
                           "AND request_status NOT IN ('REJECTED','CANCELED') LIMIT 1 FOR UPDATE", (order_id,))
            if cursor.fetchone() is not None:
                raise OrderReadError(409, 'ALREADY_PROCESSED', '이미 반품 처리 기록이 있습니다.')
            cursor.execute("SELECT refund_id FROM refunds WHERE order_id=%s AND refund_status<>'CANCELED' LIMIT 1 FOR UPDATE", (order_id,))
            if cursor.fetchone() is not None:
                raise OrderReadError(409, 'ALREADY_PROCESSED', '기존 환불 처리 기록을 확인해주세요.')
            cursor.execute('SELECT order_item_id, quantity FROM order_items WHERE order_id=%s ORDER BY order_item_id FOR UPDATE', (order_id,))
            items = cursor.fetchall()
            if not items or any(item['quantity'] < 1 for item in items):
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '주문 항목을 확인해주세요.')
            cursor.execute('INSERT INTO return_requests (order_id, customer_id, branch_id, return_reason_code, return_reason) VALUES (%s,%s,%s,%s,%s)',
                           (order_id, scope.customer_id, order['pickup_branch_id'], body.return_reason_code, body.return_reason))
            return_id = cursor.lastrowid
            for item in items:
                cursor.execute('INSERT INTO return_items (return_request_id, order_item_id, quantity) VALUES (%s,%s,%s)',
                               (return_id, item['order_item_id'], item['quantity']))
            cursor.execute("INSERT INTO audit_logs (actor_type, actor_customer_id, action_code, entity_type, entity_id, after_data, request_id) "
                           "VALUES ('CUSTOMER',%s,'RETURN_CREATE','RETURN_REQUEST',%s,%s,%s)",
                           (scope.customer_id, return_id, json.dumps(payload, ensure_ascii=False), body.request_id))
        db.commit()
        return JSONResponse(status_code=201, content={'data': {'return_request_id': return_id}, 'message': '반품이 접수되었습니다. 환불 완료가 아닙니다.'})
    except Exception:
        db.rollback()
        raise


@router.post('/customer/{order_id}/purchase-confirmation')
def confirm_customer_purchase(order_id: int = Path(..., ge=1), scope: CustomerScope = Depends(authenticated_customer), db=Depends(get_db)):
    """수령 완료와 고객 직접 구매확정을 구분한다. 자동 확정·재고·혜택 변경은 하지 않는다."""
    try:
        with db.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute('SELECT order_status, pickup_branch_id, purchase_confirmed_at FROM orders '
                           'WHERE order_id=%s AND customer_id=%s FOR UPDATE', (order_id, scope.customer_id))
            order = cursor.fetchone()
            if order is None:
                raise OrderReadError(404, 'NOT_FOUND', '주문을 찾을 수 없습니다.')
            if order['order_status'] != 'COMPLETED':
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '수령 완료 후 구매확정할 수 있습니다.')
            if order['purchase_confirmed_at'] is not None:
                db.rollback()
                return {'data': {'order_id':order_id, 'order_status':'COMPLETED', 'purchase_confirmed_at':jsonable_encoder(order['purchase_confirmed_at'])}, 'message':'이미 구매확정된 주문입니다.'}
            cursor.execute("SELECT pickup_id FROM pickups WHERE order_id=%s AND branch_id=%s AND pickup_status='COMPLETED' AND picked_up_at IS NOT NULL FOR UPDATE", (order_id,order['pickup_branch_id']))
            if cursor.fetchone() is None:
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '실제 수령 완료 기록을 확인해주세요.')
            if has_active_return(cursor, order_id):
                raise OrderReadError(409, 'INVALID_STATE_TRANSITION', '반품 진행 중에는 구매확정할 수 없습니다.')
            cursor.execute('UPDATE orders SET purchase_confirmed_at=CURRENT_TIMESTAMP WHERE order_id=%s AND purchase_confirmed_at IS NULL', (order_id,))
            cursor.execute('SELECT purchase_confirmed_at FROM orders WHERE order_id=%s', (order_id,))
            confirmed = cursor.fetchone()['purchase_confirmed_at']
            cursor.execute("INSERT INTO audit_logs (actor_type, actor_customer_id, action_code, entity_type, entity_id, before_data, after_data) "
                           "VALUES ('CUSTOMER',%s,'PURCHASE_CONFIRM','ORDER',%s,%s,%s)",
                           (scope.customer_id,order_id,json.dumps({'purchase_confirmed_at':None}),json.dumps({'purchase_confirmed_at':jsonable_encoder(confirmed)})))
        db.commit()
        return {'data':{'order_id':order_id,'order_status':'COMPLETED','purchase_confirmed_at':jsonable_encoder(confirmed)},'message':'구매확정되었습니다.'}
    except Exception:
        db.rollback()
        raise

# 조회만 제공한다. 입고·전달 상태 및 D 재고는 변경하지 않는다.
@router.get('/staff/arrival-candidates')
def arrival_candidates(page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100),
                       branch_id: int | None = Query(None, ge=1), scope: DispatchScope = Depends(authorized_dispatch), db=Depends(get_db),
                       stage: Literal['arrival','inspection'] = Query('arrival')):
    conditions = ["o.order_status='SHIPPING'", "f.fulfillment_status='IN_TRANSIT'", 'f.shipped_at IS NOT NULL', 'f.arrived_at IS NULL', 'f.destination_branch_id=o.pickup_branch_id']
    if stage == 'inspection':
        conditions = ["o.order_status='SHIPPING'", "f.fulfillment_status IN ('ARRIVED','INSPECTING')", 'f.shipped_at IS NOT NULL',
                      'f.arrived_at IS NOT NULL', 'f.completed_at IS NULL',
                      'f.destination_branch_id=o.pickup_branch_id']
    params = []
    if not scope.all_branches:
        if not scope.branch_ids:
            raise OrderReadError(403,'FORBIDDEN','소속 대리점을 확인해주세요.')
        if branch_id is not None and branch_id not in scope.branch_ids:
            raise OrderReadError(403,'FORBIDDEN','소속 대리점만 조회할 수 있습니다.')
        conditions.append('f.destination_branch_id IN ('+','.join(['%s']*len(scope.branch_ids))+')')
        params.extend(scope.branch_ids)
    if branch_id is not None:
        conditions.append('f.destination_branch_id=%s');params.append(branch_id)
    tables='FROM fulfillments f JOIN orders o ON o.order_id=f.order_id LEFT JOIN branches b ON b.branch_id=f.destination_branch_id'
    where=' WHERE '+' AND '.join(conditions)
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute('SELECT COUNT(*) AS total_count '+tables+where,tuple(params))
        total=cursor.fetchone()['total_count']
        time_field = 'f.arrived_at' if stage == 'inspection' else 'f.shipped_at'
        cursor.execute('SELECT f.fulfillment_id,f.fulfillment_number,f.order_id,o.order_number,f.destination_branch_id,b.branch_name,f.fulfillment_status,f.shipped_at,f.arrived_at,f.inspected_at '
                       +tables+where+f' ORDER BY {time_field} DESC,f.fulfillment_id DESC LIMIT %s OFFSET %s',(*params,page_size,(page-1)*page_size))
        rows=cursor.fetchall()
    return {'data':jsonable_encoder(rows),'pagination':{'page':page,'page_size':page_size,'total_count':total}}


@router.get('/staff/pickup-candidates')
def pickup_candidates(page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100),
                      branch_id: int | None = Query(None, ge=1), scope: DispatchScope = Depends(authorized_dispatch), db=Depends(get_db)):
    conditions=["o.order_status='READY_FOR_PICKUP'","p.pickup_status='READY_FOR_PICKUP'",'p.ready_at IS NOT NULL','p.picked_up_at IS NULL','p.branch_id=o.pickup_branch_id']
    params=[]
    if not scope.all_branches:
        if not scope.branch_ids:
            raise OrderReadError(403,'FORBIDDEN','소속 대리점을 확인해주세요.')
        if branch_id is not None and branch_id not in scope.branch_ids:
            raise OrderReadError(403,'FORBIDDEN','소속 대리점만 조회할 수 있습니다.')
        conditions.append('p.branch_id IN ('+','.join(['%s']*len(scope.branch_ids))+')');params.extend(scope.branch_ids)
    if branch_id is not None:
        conditions.append('p.branch_id=%s');params.append(branch_id)
    tables='FROM pickups p JOIN orders o ON o.order_id=p.order_id LEFT JOIN branches b ON b.branch_id=p.branch_id'
    where=' WHERE '+' AND '.join(conditions)
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute('SELECT COUNT(*) AS total_count '+tables+where,tuple(params));total=cursor.fetchone()['total_count']
        cursor.execute('SELECT p.pickup_id,p.order_id,o.order_number,p.branch_id,b.branch_name,p.pickup_status,p.ready_at '
                       +tables+where+' ORDER BY p.ready_at DESC,p.pickup_id DESC LIMIT %s OFFSET %s',(*params,page_size,(page-1)*page_size));rows=cursor.fetchall()
    return {'data':jsonable_encoder(rows),'pagination':{'page':page,'page_size':page_size,'total_count':total}}


def read_pickup_candidate_detail(db, *, record_id: int, arrival: bool, scope: DispatchScope, inspection: bool = False):
    """상세에서도 소속을 다시 검사하고 주문 당시 상품 정보만 읽는다."""
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        if arrival:
            stage_condition = ("f.fulfillment_status IN ('ARRIVED','INSPECTING') AND f.arrived_at IS NOT NULL AND f.completed_at IS NULL"
                               if inspection else "f.fulfillment_status='IN_TRANSIT' AND f.arrived_at IS NULL")
            cursor.execute("SELECT f.fulfillment_id,f.fulfillment_number,f.order_id,o.order_number,f.destination_branch_id AS branch_id,b.branch_name,f.fulfillment_status,f.shipped_at,f.arrived_at,f.inspected_at "
                           "FROM fulfillments f JOIN orders o ON o.order_id=f.order_id LEFT JOIN branches b ON b.branch_id=f.destination_branch_id "
                           f"WHERE f.fulfillment_id=%s AND o.order_status='SHIPPING' AND {stage_condition} "
                           "AND f.shipped_at IS NOT NULL AND f.destination_branch_id=o.pickup_branch_id",(record_id,))
        else:
            cursor.execute("SELECT p.pickup_id,p.order_id,o.order_number,p.branch_id,b.branch_name,p.pickup_status,p.ready_at "
                           "FROM pickups p JOIN orders o ON o.order_id=p.order_id LEFT JOIN branches b ON b.branch_id=p.branch_id "
                           "WHERE p.pickup_id=%s AND o.order_status='READY_FOR_PICKUP' AND p.pickup_status='READY_FOR_PICKUP' "
                           "AND p.ready_at IS NOT NULL AND p.picked_up_at IS NULL AND p.branch_id=o.pickup_branch_id",(record_id,))
        row=cursor.fetchone()
        if row is None or (not scope.all_branches and row['branch_id'] not in scope.branch_ids):
            raise OrderReadError(404,'NOT_FOUND','대상 정보를 확인할 수 없습니다.')
        if arrival:
            cursor.execute('SELECT fi.fulfillment_item_id,fi.order_item_id,oi.product_name,oi.product_code,oi.color_name,oi.size_mm,fi.quantity,oi.unit_price,oi.line_total '
                           'FROM fulfillment_items fi JOIN order_items oi ON oi.order_item_id=fi.order_item_id AND oi.order_id=fi.order_id '
                           'WHERE fi.fulfillment_id=%s ORDER BY fi.order_item_id,fi.fulfillment_item_id',(record_id,))
        else:
            cursor.execute('SELECT order_item_id,product_name,product_code,color_name,size_mm,quantity,unit_price,line_total '
                           'FROM order_items WHERE order_id=%s ORDER BY order_item_id',(row['order_id'],))
        row['items']=cursor.fetchall()
    return {'data':jsonable_encoder(row)}


@router.get('/staff/arrival-candidates/{fulfillment_id}')
def arrival_candidate_detail(fulfillment_id: int = Path(...,ge=1), scope: DispatchScope = Depends(authorized_dispatch),db=Depends(get_db)):
    return read_pickup_candidate_detail(db,record_id=fulfillment_id,arrival=True,scope=scope)


@router.get('/staff/pickup-candidates/{pickup_id}')
def pickup_candidate_detail(pickup_id: int = Path(...,ge=1),scope: DispatchScope = Depends(authorized_dispatch),db=Depends(get_db)):
    return read_pickup_candidate_detail(db,record_id=pickup_id,arrival=False,scope=scope)


@router.get('/staff/inspection-candidates/{fulfillment_id}')
def inspection_candidate_detail(fulfillment_id: int = Path(...,ge=1),scope: DispatchScope = Depends(authorized_dispatch),db=Depends(get_db)):
    """도착 후 정상 검수 대기 배송을 기존 권한·상품 조회로 확인한다."""
    return read_pickup_candidate_detail(db,record_id=fulfillment_id,arrival=True,inspection=True,scope=scope)
