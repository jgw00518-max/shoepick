"""본사·대리점 재고 조회, 주문 재고 예약·해제, 이동 이력.

기존 테이블: headquarters_inventory, inventory_policies,
inventory_reservations, inventory_movements, pickup_holdings.
대리점의 고객 수령 대기 물품과 일반 판매 재고는 구분한다.
"""

from contextlib import contextmanager
from datetime import datetime
from typing import Annotated, Literal
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Path, Query
from pydantic import BaseModel
from pymysql.connections import Connection
from pymysql.cursors import DictCursor

if __package__ == "backend.features":
    from ..dependencies import get_db
else:
    from dependencies import get_db

router = APIRouter(prefix="/inventory", tags=["재고"])

# 1. 요청·응답 모델
class HeadquartersInventoryItem(BaseModel):
    product_variant_id: int
    product_id: int
    product_code: str
    product_name: str
    color_code: str
    color_name: str
    size_mm: int
    on_hand_quantity: int
    reserved_quantity: int
    defective_quantity: int
    available_quantity: int
    updated_at: datetime


class Pagination(BaseModel):
    page: int
    page_size: int
    total_count: int


class HeadquartersInventoryResponse(BaseModel):
    data: list[HeadquartersInventoryItem]
    pagination: Pagination


HoldingStatus = Literal[
    "AWAITING_ARRIVAL", "INSPECTING", "READY_FOR_PICKUP", "PICKED_UP",
    "RECALLING", "RETURNED_TO_HQ", "DAMAGED", "CANCELED",
]
BranchSortField = Literal["updated_at", "received_at", "product_code", "product_name", "holding_status"]
BRANCH_SORT_COLUMNS = {
    "updated_at": "ph.updated_at", "received_at": "ph.received_at",
    "product_code": "oi.product_code", "product_name": "oi.product_name",
    "holding_status": "ph.holding_status",
}


class BranchInventoryItem(BaseModel):
    pickup_holding_id: int
    branch_id: int
    branch_name: str
    fulfillment_item_id: int
    fulfillment_id: int
    fulfillment_number: str
    order_id: int
    order_number: str
    order_item_id: int
    product_variant_id: int
    product_code: str
    product_name: str
    color_name: str
    size_mm: int
    quantity: int
    holding_status: HoldingStatus
    received_at: datetime | None
    ready_at: datetime | None
    picked_up_at: datetime | None
    recalled_at: datetime | None
    updated_at: datetime


class BranchInventoryResponse(BaseModel):
    data: list[BranchInventoryItem]
    pagination: Pagination


# 정렬 컬럼은 허용 목록에서만 선택한다. 사용자 입력을 SQL에 직접 넣지 않는다.
SortField = Literal["updated_at", "product_code", "product_name", "available_quantity"]
SORT_COLUMNS = {
    "updated_at": "hi.updated_at",
    "product_code": "pv.product_code",
    "product_name": "p.product_name",
    "available_quantity": "hi.available_quantity",
}


# 2. 업무 함수
def list_headquarters_inventory(
    db: Connection,
    *,
    page: int,
    page_size: int,
    keyword: str | None,
    product_variant_id: int | None,
    sort: SortField,
    order: Literal["asc", "desc"],
) -> HeadquartersInventoryResponse:
    """기존 본사 재고 행을 상품명·옵션 정보와 함께 조회한다.

    비활성 상품도 운영 재고 조회 대상에 포함하며,
    본사 재고 행이 없는 옵션을 재고 0으로 만들어 반환하지 않는다.
    """
    conditions = []
    parameters = []
    if keyword and keyword.strip():
        # %, _도 검색어 자체로 취급한다. !는 LIKE의 이스케이프 문자다.
        escaped = keyword.strip().replace("!", "!!").replace("%", "!%").replace("_", "!_")
        pattern = f"%{escaped}%"
        conditions.append("(p.product_name LIKE %s ESCAPE '!' OR pv.product_code LIKE %s ESCAPE '!')")
        parameters.extend([pattern, pattern])
    if product_variant_id is not None:
        conditions.append("hi.product_variant_id = %s")
        parameters.append(product_variant_id)

    tables = """
        FROM headquarters_inventory AS hi
        JOIN product_variants AS pv ON pv.product_variant_id = hi.product_variant_id
        JOIN products AS p ON p.product_id = pv.product_id
    """
    where = " WHERE " + " AND ".join(conditions) if conditions else ""
    sort_column = SORT_COLUMNS[sort]
    direction = {"asc": "ASC", "desc": "DESC"}[order]

    with db.cursor(DictCursor) as cursor:
        cursor.execute("SELECT COUNT(*) AS total_count " + tables + where, tuple(parameters))
        total_count = cursor.fetchone()["total_count"]
        cursor.execute(
            """
            SELECT hi.product_variant_id, pv.product_id, pv.product_code,
                   p.product_name, pv.color_code, pv.color_name, pv.size_mm,
                   hi.on_hand_quantity, hi.reserved_quantity,
                   hi.defective_quantity, hi.available_quantity, hi.updated_at
            """
            + tables + where
            + f" ORDER BY {sort_column} {direction}, hi.product_variant_id ASC LIMIT %s OFFSET %s",
            tuple(parameters) + (page_size, (page - 1) * page_size),
        )
        rows = cursor.fetchall()

    return HeadquartersInventoryResponse(
        data=rows,
        pagination=Pagination(page=page, page_size=page_size, total_count=total_count),
    )


# 3. API 함수
@router.get("/headquarters", response_model=HeadquartersInventoryResponse)
def get_headquarters_inventory(
    db: Annotated[Connection, Depends(get_db)],
    page: Annotated[int, Query(ge=1, description="페이지 번호")] = 1,
    page_size: Annotated[int, Query(ge=1, le=100, description="페이지당 항목 수")] = 20,
    keyword: Annotated[str | None, Query(max_length=150, description="상품명 또는 상품 코드")] = None,
    product_variant_id: Annotated[int | None, Query(gt=0, description="상품 옵션 ID")] = None,
    sort: SortField = "updated_at",
    order: Literal["asc", "desc"] = "desc",
) -> HeadquartersInventoryResponse:
    """본사 재고 목록을 조회한다. 직원 인증은 담당 B의 공통 기능 연결 시 추가한다."""
    return list_headquarters_inventory(
        db,
        page=page,
        page_size=page_size,
        keyword=keyword,
        product_variant_id=product_variant_id,
        sort=sort,
        order=order,
    )


def list_branch_inventory(
    db: Connection,
    *,
    branch_id: int,
    page: int,
    page_size: int,
    keyword: str | None,
    product_variant_id: int | None,
    holding_status: HoldingStatus | None,
    sort: BranchSortField,
    order: Literal["asc", "desc"],
) -> BranchInventoryResponse:
    """주문 품목별 보관 기록 조회. 상품 정보는 주문 당시 스냅샷을 사용한다.

    상태 필터가 없으면 입고 대기·수령 완료 등 이력도 포함한다.
    quantity는 기록의 수량이며 전체 합계가 현재 보관 수량은 아니다.
    """
    conditions = ["ph.branch_id = %s"]
    parameters = [branch_id]
    if holding_status is not None:
        conditions.append("ph.holding_status = %s")
        parameters.append(holding_status)
    if product_variant_id is not None:
        conditions.append("oi.product_variant_id = %s")
        parameters.append(product_variant_id)
    if keyword and keyword.strip():
        escaped = keyword.strip().replace("!", "!!").replace("%", "!%").replace("_", "!_")
        pattern = f"%{escaped}%"
        conditions.append("(oi.product_name LIKE %s ESCAPE '!' OR oi.product_code LIKE %s ESCAPE '!')")
        parameters.extend([pattern, pattern])

    tables = """
        FROM pickup_holdings AS ph
        JOIN branches AS b ON b.branch_id = ph.branch_id
        JOIN fulfillment_items AS fi ON fi.fulfillment_item_id = ph.fulfillment_item_id
        JOIN fulfillments AS f ON f.fulfillment_id = fi.fulfillment_id AND f.order_id = fi.order_id
        JOIN order_items AS oi ON oi.order_item_id = fi.order_item_id AND oi.order_id = fi.order_id
        JOIN orders AS o ON o.order_id = fi.order_id
    """
    where = " WHERE " + " AND ".join(conditions)
    sort_column = BRANCH_SORT_COLUMNS[sort]
    direction = {"asc": "ASC", "desc": "DESC"}[order]

    with db.cursor(DictCursor) as cursor:
        cursor.execute("SELECT branch_id FROM branches WHERE branch_id = %s", (branch_id,))
        if cursor.fetchone() is None:
            raise HTTPException(
                status_code=404,
                detail={"code": "NOT_FOUND", "message": "대리점을 찾을 수 없습니다."},
            )
        cursor.execute("SELECT COUNT(*) AS total_count " + tables + where, tuple(parameters))
        total_count = cursor.fetchone()["total_count"]
        cursor.execute(
            """
            SELECT ph.pickup_holding_id, ph.branch_id, b.branch_name,
                   ph.fulfillment_item_id, fi.fulfillment_id, f.fulfillment_number,
                   fi.order_id, o.order_number, fi.order_item_id, oi.product_variant_id,
                   oi.product_code, oi.product_name, oi.color_name, oi.size_mm,
                   ph.quantity, ph.holding_status, ph.received_at, ph.ready_at,
                   ph.picked_up_at, ph.recalled_at, ph.updated_at
            """
            + tables + where
            + f" ORDER BY {sort_column} {direction}, ph.pickup_holding_id ASC LIMIT %s OFFSET %s",
            tuple(parameters) + (page_size, (page - 1) * page_size),
        )
        rows = cursor.fetchall()
    return BranchInventoryResponse(
        data=rows,
        pagination=Pagination(page=page, page_size=page_size, total_count=total_count),
    )


@router.get("/branches/{branch_id}", response_model=BranchInventoryResponse)
def get_branch_inventory(
    branch_id: Annotated[int, Path(gt=0, description="대리점 ID")],
    db: Annotated[Connection, Depends(get_db)],
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    keyword: Annotated[str | None, Query(max_length=150, description="상품명 또는 상품 코드")] = None,
    product_variant_id: Annotated[int | None, Query(gt=0)] = None,
    holding_status: HoldingStatus | None = None,
    sort: BranchSortField = "updated_at",
    order: Literal["asc", "desc"] = "desc",
) -> BranchInventoryResponse:
    """대리점 보관 현황 조회. 직원의 소속 지점 검증은 담당 B 연동 시 추가한다."""
    return list_branch_inventory(
        db, branch_id=branch_id, page=page, page_size=page_size,
        keyword=keyword, product_variant_id=product_variant_id,
        holding_status=holding_status, sort=sort, order=order,
    )


# 4. 주문 담당이 같은 DB 트랜잭션에서 호출하는 공용 재고 변경 함수
class OrderReservationItem(BaseModel):
    inventory_reservation_id: int
    order_item_id: int
    product_variant_id: int
    reserved_quantity: int
    reservation_status: Literal["RESERVED", "CONSUMED", "RELEASED", "EXPIRED"]
    expires_at: datetime
    released_at: datetime | None
    release_reason: str | None


class OrderReservationResult(BaseModel):
    order_id: int
    changed: bool
    reservations: list[OrderReservationItem]


def _inventory_error(code: str, message: str, status_code: int = 409):
    raise HTTPException(status_code=status_code, detail={"code": code, "message": message})


def _lock_inventory_order(cursor, db: Connection, order_id: int):
    if isinstance(order_id, bool) or not isinstance(order_id, int) or order_id <= 0:
        _inventory_error("INVALID_INPUT", "주문 ID를 확인해주세요.", 400)
    if db.get_autocommit():
        _inventory_error("INTERNAL_ERROR", "재고 변경에는 트랜잭션 연결이 필요합니다.", 500)
    # 이 조회로 트랜잭션을 시작하고 같은 주문의 중복·동시 요청을 직렬화한다.
    cursor.execute(
        "SELECT order_id, order_status, CURRENT_TIMESTAMP AS db_now FROM orders WHERE order_id = %s FOR UPDATE",
        (order_id,),
    )
    order = cursor.fetchone()
    if order is None:
        _inventory_error("NOT_FOUND", "주문을 찾을 수 없습니다.", 404)
    return order


@contextmanager
def _inventory_savepoint(cursor):
    # 주문 담당의 선행 변경은 보존하고 이 함수의 변경만 원자적으로 복구한다.
    name = "inventory_" + uuid4().hex
    cursor.execute(f"SAVEPOINT {name}")
    try:
        yield
    except Exception:
        cursor.execute(f"ROLLBACK TO SAVEPOINT {name}")
        cursor.execute(f"RELEASE SAVEPOINT {name}")
        raise
    else:
        cursor.execute(f"RELEASE SAVEPOINT {name}")


def _check_before_shipment(cursor, order_id: int):
    cursor.execute(
        """SELECT fulfillment_id FROM fulfillments
           WHERE order_id = %s AND (
               shipped_at IS NOT NULL OR fulfillment_status IN (
                   'IN_TRANSIT', 'ARRIVED', 'INSPECTING', 'READY_FOR_PICKUP',
                   'RECALLING', 'RETURNED_TO_HQ', 'COMPLETED'
               )
           ) LIMIT 1 FOR UPDATE""",
        (order_id,),
    )
    if cursor.fetchone() is not None:
        _inventory_error("INVALID_STATE_TRANSITION", "출고된 주문의 예약 재고는 변경할 수 없습니다.")


def _order_reservations(cursor, order_id: int, *, lock: bool = False):
    cursor.execute(
        """SELECT inventory_reservation_id, order_id, order_item_id,
                  product_variant_id, reserved_quantity, reservation_status,
                  expires_at, released_at, release_reason
           FROM inventory_reservations WHERE order_id = %s
           ORDER BY product_variant_id, order_item_id""" + (" FOR UPDATE" if lock else ""),
        (order_id,),
    )
    return cursor.fetchall()


def _lock_inventory_balances(cursor, variant_ids):
    balances = {}
    # 주문이 다르더라도 SKU 잠금 순서를 통일해 교착 가능성을 줄인다.
    for variant_id in sorted(set(variant_ids)):
        cursor.execute(
            """SELECT product_variant_id, on_hand_quantity, reserved_quantity,
                      defective_quantity, available_quantity
               FROM headquarters_inventory WHERE product_variant_id = %s FOR UPDATE""",
            (variant_id,),
        )
        balance = cursor.fetchone()
        if balance is None:
            _inventory_error("INSUFFICIENT_STOCK", "본사 재고가 없는 상품 옵션입니다.")
        balances[variant_id] = balance
    return balances


def _reservation_movement(cursor, reservation, balance, delta: int, reason: str):
    action = "reserve" if delta > 0 else "release"
    cursor.execute(
        """INSERT INTO inventory_movements (
               product_variant_id, movement_type, on_hand_delta, reserved_delta,
               defective_delta, on_hand_after, reserved_after, defective_after,
               reference_type, reference_id, idempotency_key, reason
           ) VALUES (%s, %s, 0, %s, 0, %s, %s, %s, 'ORDER', %s, %s, %s)""",
        (
            reservation["product_variant_id"], "RESERVE" if delta > 0 else "RELEASE",
            delta, balance["on_hand_quantity"], balance["reserved_quantity"],
            balance["defective_quantity"], reservation["order_id"],
            f"reservation:{reservation['inventory_reservation_id']}:{action}", reason,
        ),
    )


def reserve_order_inventory(
    db: Connection, *, order_id: int, expires_at: datetime,
) -> OrderReservationResult:
    """DB의 주문 품목 수량만큼 확보한다. commit하지 않는다.

    호출자는 확보 시점을 결정하고 DB와 같은 시간 기준의 naive 만료 시각을 전달한다.
    이미 확보한 품목은 다시 증가하거나 만료 시각을 연장하지 않는다.
    해제·소비된 예약을 다시 확보하지 않는다.
    """
    if not isinstance(expires_at, datetime) or expires_at.tzinfo is not None:
        _inventory_error("INVALID_INPUT", "DB 시간 기준의 예약 만료 시각을 전달해주세요.", 400)
    with db.cursor(DictCursor) as cursor:
        order = _lock_inventory_order(cursor, db, order_id)
        with _inventory_savepoint(cursor):
            if order["order_status"] not in {"PENDING_PAYMENT", "PAID", "PREPARING"}:
                _inventory_error("INVALID_STATE_TRANSITION", "재고를 확보할 수 없는 주문 상태입니다.")
            _check_before_shipment(cursor, order_id)
            cursor.execute(
                """SELECT order_item_id, product_variant_id, quantity FROM order_items
                   WHERE order_id = %s ORDER BY product_variant_id, order_item_id FOR UPDATE""",
                (order_id,),
            )
            items = cursor.fetchall()
            if not items:
                _inventory_error("INVALID_STATE_TRANSITION", "확보할 주문 품목이 없습니다.")
            by_item = {item["order_item_id"]: item for item in items}
            existing = _order_reservations(cursor, order_id, lock=True)
            for reservation in existing:
                item = by_item.get(reservation["order_item_id"])
                if (item is None or item["product_variant_id"] != reservation["product_variant_id"]
                        or item["quantity"] != reservation["reserved_quantity"]):
                    _inventory_error("INVALID_STATE_TRANSITION", "주문 품목과 예약 기록이 일치하지 않습니다.")
                if reservation["reservation_status"] != "RESERVED":
                    _inventory_error("INVALID_STATE_TRANSITION", "처리된 예약을 다시 확보할 수 없습니다.")
            existing_ids = {row["order_item_id"] for row in existing}
            missing = [item for item in items if item["order_item_id"] not in existing_ids]
            if missing and expires_at <= order["db_now"]:
                _inventory_error("INVALID_INPUT", "예약 만료 시각은 현재 DB 시각 이후여야 합니다.", 400)
            balances = _lock_inventory_balances(cursor, [item["product_variant_id"] for item in missing])
            if missing:
                # 잠금 대기 중 만료 시각이 지났을 수 있으므로 실제 변경 직전에 재검사한다.
                cursor.execute("SELECT CURRENT_TIMESTAMP AS db_now")
                if expires_at <= cursor.fetchone()["db_now"]:
                    _inventory_error("INVALID_INPUT", "예약 만료 시각이 지났습니다.", 400)
            # 모든 SKU가 충분한지 확인한 뒤에만 실제 변경을 시작한다.
            for item in missing:
                if balances[item["product_variant_id"]]["available_quantity"] < item["quantity"]:
                    _inventory_error("INSUFFICIENT_STOCK", "주문 상품의 가용 재고가 부족합니다.")
            for item in missing:
                variant_id, quantity = item["product_variant_id"], item["quantity"]
                cursor.execute(
                    """INSERT INTO inventory_reservations (
                           order_id, order_item_id, product_variant_id, reserved_quantity,
                           reservation_status, expires_at
                       ) VALUES (%s, %s, %s, %s, 'RESERVED', %s)""",
                    (order_id, item["order_item_id"], variant_id, quantity, expires_at),
                )
                reservation = {
                    "inventory_reservation_id": cursor.lastrowid, "order_id": order_id,
                    "product_variant_id": variant_id,
                }
                cursor.execute(
                    "UPDATE headquarters_inventory SET reserved_quantity = reserved_quantity + %s WHERE product_variant_id = %s",
                    (quantity, variant_id),
                )
                balances[variant_id]["reserved_quantity"] += quantity
                _reservation_movement(cursor, reservation, balances[variant_id], quantity, "주문 재고 확보")
            rows = _order_reservations(cursor, order_id, lock=True)
    return OrderReservationResult(order_id=order_id, changed=bool(missing), reservations=rows)


def release_order_inventory(
    db: Connection, *, order_id: int, reason: str,
) -> OrderReservationResult:
    """결제 대기 또는 취소 주문의 예약을 전부 해제한다. commit하지 않는다.

    결제 완료 주문은 주문 담당이 먼저 취소 상태로 변경한 뒤 같은 연결로 호출한다.
    이미 해제된 예약은 다시 차감하지 않는다. 실물 재고는 변경하지 않는다.
    """
    if not isinstance(reason, str) or not reason.strip() or len(reason.strip()) > 255:
        _inventory_error("INVALID_INPUT", "255자 이내의 예약 해제 사유를 입력해주세요.", 400)
    reason = reason.strip()
    with db.cursor(DictCursor) as cursor:
        order = _lock_inventory_order(cursor, db, order_id)
        with _inventory_savepoint(cursor):
            if order["order_status"] not in {"PENDING_PAYMENT", "CANCELED"}:
                _inventory_error("INVALID_STATE_TRANSITION", "취소하지 않은 결제 주문의 예약은 해제할 수 없습니다.")
            _check_before_shipment(cursor, order_id)
            existing = _order_reservations(cursor, order_id, lock=True)
            if any(row["reservation_status"] == "CONSUMED" for row in existing):
                _inventory_error("INVALID_STATE_TRANSITION", "출고에 사용한 예약은 해제할 수 없습니다.")
            cursor.execute(
                """SELECT order_item_id, product_variant_id, quantity FROM order_items
                   WHERE order_id = %s ORDER BY product_variant_id, order_item_id FOR UPDATE""",
                (order_id,),
            )
            by_item = {item["order_item_id"]: item for item in cursor.fetchall()}
            for row in existing:
                item = by_item.get(row["order_item_id"])
                if (item is None or item["product_variant_id"] != row["product_variant_id"]
                        or item["quantity"] != row["reserved_quantity"]):
                    _inventory_error("INVALID_STATE_TRANSITION", "주문 품목과 예약 기록이 일치하지 않습니다.")
            active = [row for row in existing if row["reservation_status"] == "RESERVED"]
            balances = _lock_inventory_balances(cursor, [row["product_variant_id"] for row in active])
            quantities = {}
            for row in active:
                variant_id = row["product_variant_id"]
                quantities[variant_id] = quantities.get(variant_id, 0) + row["reserved_quantity"]
            for variant_id, quantity in quantities.items():
                if balances[variant_id]["reserved_quantity"] < quantity:
                    _inventory_error("INVALID_STATE_TRANSITION", "본사 예약 수량과 예약 기록이 일치하지 않습니다.")
            for row in active:
                variant_id, quantity = row["product_variant_id"], row["reserved_quantity"]
                cursor.execute(
                    "UPDATE headquarters_inventory SET reserved_quantity = reserved_quantity - %s WHERE product_variant_id = %s",
                    (quantity, variant_id),
                )
                cursor.execute(
                    """UPDATE inventory_reservations SET reservation_status = 'RELEASED',
                           released_at = CURRENT_TIMESTAMP, release_reason = %s
                       WHERE inventory_reservation_id = %s""",
                    (reason, row["inventory_reservation_id"]),
                )
                balances[variant_id]["reserved_quantity"] -= quantity
                _reservation_movement(cursor, row, balances[variant_id], -quantity, reason)
            rows = _order_reservations(cursor, order_id, lock=True)
    return OrderReservationResult(order_id=order_id, changed=bool(active), reservations=rows)
