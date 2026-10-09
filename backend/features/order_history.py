"""C 담당의 주문 조회. 인증과 출고 조건은 B/A의 합의된 의존성으로 연결한다."""

from dataclasses import dataclass

from fastapi import APIRouter, Depends, Query
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from fastapi.routing import APIRoute
import pymysql
from .authentication import AuthError, current_customer, current_employee

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


def authenticated_customer(customer=Depends(current_customer)) -> CustomerScope:
    """B가 검증한 고객 ID만 주문 조회에 전달한다."""
    return CustomerScope(customer['customer_id'])


def authorized_dispatch(employee=Depends(current_employee)) -> DispatchScope:
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


@router.get('/staff/dispatch')
def dispatch_orders(scope: DispatchScope = Depends(authorized_dispatch),
                    db=Depends(get_db), page: int = Query(1, ge=1),
                    page_size: int = Query(20, ge=1, le=100),
                    branch_id: int | None = Query(None, ge=1)):
    if not scope.order_statuses or (not scope.all_branches and not scope.branch_ids):
        raise OrderReadError(403, 'FORBIDDEN', '출고 조회 권한이 없습니다.')
    if branch_id is not None and not scope.all_branches and branch_id not in scope.branch_ids:
        raise OrderReadError(403, 'FORBIDDEN', '소속 대리점만 조회할 수 있습니다.')
    # A의 결제 완료 공통 함수가 전달되기 전에는 상태값만으로 잘못된 출고 목록을 반환하지 않는다.
    raise OrderReadError(503, 'INTERNAL_ERROR', '출고 조회 연동을 준비 중입니다.')
