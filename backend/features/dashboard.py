"""재고·품의·결재·발주·입고 운영 현황 집계."""

from typing import Annotated
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, Path, HTTPException
from pydantic import BaseModel
from pymysql.connections import Connection
from pymysql.cursors import DictCursor
from .authentication import AuthRoute, AuthError, current_employee, check_branch

if __package__ == 'backend.features':
    from ..dependencies import get_db
else:
    from dependencies import get_db

router = APIRouter(prefix="/dashboard", tags=["운영 현황"], route_class=AuthRoute)

HELD_STATUSES = ('INSPECTING', 'READY_FOR_PICKUP', 'RECALLING', 'DAMAGED')
SALES_ORDER_STATUSES = ('PAID','PREPARING','SHIPPING','READY_FOR_PICKUP','COMPLETED')


class ExecutiveSales(BaseModel):
    sales_quantity: int
    revenue_amount: int
    order_count: int
    period_start: datetime
    period_end: datetime
    timezone: str = 'Asia/Seoul'


class ExecutiveSalesResponse(BaseModel):
    data: ExecutiveSales


def _sales_period():
    end=datetime.now(timezone(timedelta(hours=9))).replace(tzinfo=None)
    start=(end-timedelta(days=27)).replace(hour=0,minute=0,second=0,microsecond=0)
    return start,end


@router.get('/executive/sales', response_model=ExecutiveSalesResponse, summary='임원 최근 28일 판매량·결제액·주문 수')
def get_executive_sales(employee: Annotated[dict,Depends(current_employee)], db: Annotated[Connection,Depends(get_db)]):
    roles={role['role_code'] for role in employee.get('roles',[])}
    if not roles & {'EXECUTIVE','ADMIN'}:
        raise AuthError('FORBIDDEN')
    start,end=_sales_period()
    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT COALESCE(SUM(q.quantity),0) AS sales_quantity,COALESCE(SUM(o.paid_total),0) AS revenue_amount,'
            'COUNT(*) AS order_count FROM orders o '
            "JOIN (SELECT order_id,MIN(paid_at) AS paid_at FROM payments WHERE payment_status IN ('PAID','PARTIALLY_REFUNDED') "
            'AND paid_at IS NOT NULL GROUP BY order_id) pay ON pay.order_id=o.order_id '
            'LEFT JOIN (SELECT order_id,SUM(quantity) AS quantity FROM order_items GROUP BY order_id) q ON q.order_id=o.order_id '
            'WHERE pay.paid_at>=%s AND pay.paid_at<=%s AND o.order_status IN (%s,%s,%s,%s,%s)',
            (start,end,*SALES_ORDER_STATUSES))
        totals=cursor.fetchone()
    return ExecutiveSalesResponse(data=ExecutiveSales(**totals,period_start=start,period_end=end))


class BranchHeldInventory(BaseModel):
    branch_id: int
    branch_name: str
    held_quantity: int
    holding_count: int


class BranchHeldInventoryResponse(BaseModel):
    data: BranchHeldInventory


class HeadquartersLowStock(BaseModel):
    low_stock_variant_count: int
    monitored_variant_count: int


class HeadquartersLowStockResponse(BaseModel):
    data: HeadquartersLowStock


@router.get('/headquarters/low-stock', response_model=HeadquartersLowStockResponse,
    summary='본사 대시보드 가용 재고 부족 옵션 수 집계')
def get_headquarters_low_stock(employee: Annotated[dict, Depends(current_employee)],
    db: Annotated[Connection, Depends(get_db)]):
    roles={role['role_code'] for role in employee.get('roles',[])}
    if not roles & {'HQ_STAFF','TEAM_LEAD','DIRECTOR','EXECUTIVE','ADMIN'}:
        raise AuthError('FORBIDDEN')
    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT COALESCE(SUM(CASE WHEN hi.available_quantity * 100 '
            '< COALESCE(ip.initial_stock_quantity,%s) * COALESCE(ip.reorder_threshold_percent,%s) '
            'THEN 1 ELSE 0 END),0) AS low_stock_variant_count,COUNT(*) AS monitored_variant_count '
            'FROM headquarters_inventory hi JOIN product_variants pv ON pv.product_variant_id=hi.product_variant_id '
            'JOIN products p ON p.product_id=pv.product_id '
            'LEFT JOIN inventory_policies ip ON ip.product_variant_id=hi.product_variant_id '
            'WHERE pv.is_active=1 AND p.is_active=1 AND (ip.product_variant_id IS NULL OR ip.is_active=1)',(100,30))
        totals=cursor.fetchone()
    return HeadquartersLowStockResponse(data=HeadquartersLowStock(**totals))


@router.get('/branches/{branch_id}/inventory', response_model=BranchHeldInventoryResponse,
    summary='대리점 대시보드 현재 보관 수량 집계')
def get_branch_held_inventory(branch_id: Annotated[int, Path(gt=0)],
    employee: Annotated[dict, Depends(current_employee)], db: Annotated[Connection, Depends(get_db)]):
    check_branch(employee,branch_id)
    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT branch_id,branch_name FROM branches WHERE branch_id=%s AND is_active=1',(branch_id,))
        branch=cursor.fetchone()
        if branch is None:
            raise HTTPException(404,detail={'code':'NOT_FOUND','message':'활성 대리점을 찾을 수 없습니다.'})
        cursor.execute('SELECT COALESCE(SUM(quantity),0) AS held_quantity,COUNT(*) AS holding_count FROM pickup_holdings '
            'WHERE branch_id=%s AND holding_status IN (%s,%s,%s,%s)',(branch_id,*HELD_STATUSES))
        totals=cursor.fetchone()
    return BranchHeldInventoryResponse(data=BranchHeldInventory(**branch,**totals))

# 1. 요청·응답 모델: 기간·지점별 필터와 현황 응답을 정의한다.
# 2. 업무 함수: 권한 범위 내 재고·결재 대기·미입고 발주 등을 집계한다.
# 3. API 함수: 현황 조회를 연결한다. 업무 데이터를 직접 변경하지 않는다.
#    예: GET /api/v1/dashboard/summary
