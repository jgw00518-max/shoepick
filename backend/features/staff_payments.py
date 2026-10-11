"""본사 직원의 결제 기록 조회 API."""

from datetime import datetime

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from pymysql.connections import Connection
from pymysql.cursors import DictCursor

if __package__ == "backend.features":
    from ..dependencies import get_db
    from .authentication import AuthError, current_employee
else:
    from dependencies import get_db
    from features.authentication import AuthError, current_employee


router = APIRouter(
    prefix="/staff/payments",
    tags=["A 본사 결제 확인"],
)


def current_payment_reader(
    employee: dict = Depends(current_employee),
) -> dict:
    """본사 사원·팀장·이사만 결제 기록을 조회한다."""
    role_codes = {
        role["role_code"]
        for role in employee["roles"]
    }

    if not role_codes.intersection({
        "HQ_STAFF",
        "TEAM_LEAD",
        "DIRECTOR",
    }):
        raise AuthError("FORBIDDEN")

    return employee


class StaffPaymentResponse(BaseModel):
    payment_id: int
    order_id: int
    order_number: str
    order_status: str
    payment_method: str
    payment_status: str
    payment_amount: int
    paid_at: datetime | None
    pickup_branch_id: int | None
    branch_name: str | None


class PaymentPagination(BaseModel):
    page: int
    page_size: int
    total_count: int


class StaffPaymentListResponse(BaseModel):
    data: list[StaffPaymentResponse]
    pagination: PaymentPagination


@router.get(
    "",
    response_model=StaffPaymentListResponse,
)
def get_staff_payments(
    employee: dict = Depends(current_payment_reader),
    db: Connection = Depends(get_db),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
) -> StaffPaymentListResponse:
    """전체 지점의 결제 기록을 최신 등록 순으로 조회한다."""
    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            """
            SELECT COUNT(*) AS total_count
            FROM payments
            """
        )
        total_count = cursor.fetchone()["total_count"]

        cursor.execute(
            """
            SELECT
                p.payment_id,
                o.order_id,
                o.order_number,
                o.order_status,
                p.payment_method,
                p.payment_status,
                p.payment_amount,
                p.paid_at,
                o.pickup_branch_id,
                b.branch_name
            FROM payments AS p
            JOIN orders AS o
                ON o.order_id = p.order_id
            LEFT JOIN branches AS b
                ON b.branch_id = o.pickup_branch_id
            ORDER BY p.payment_id DESC
            LIMIT %s OFFSET %s
            """,
            (
                page_size,
                (page - 1) * page_size,
            ),
        )
        rows = cursor.fetchall()

    return StaffPaymentListResponse(
        data=[
            StaffPaymentResponse(**row)
            for row in rows
        ],
        pagination=PaymentPagination(
            page=page,
            page_size=page_size,
            total_count=total_count,
        ),
    )