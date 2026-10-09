"""결제 완료 주문 조회, 주문 상세 조회, 모의 결제 API."""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Path
from pydantic import BaseModel
from pymysql.connections import Connection
from pymysql.cursors import DictCursor

if __package__ == "backend.features":
    from ..dependencies import get_db
else:
    from dependencies import get_db


router = APIRouter(prefix="/orders", tags=["주문·결제"])


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

    for item in request.items:
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
                WHERE order_id = %s
                FOR UPDATE
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
