"""재고 변경의 수량 보존·중복 요청·상태·원자성을 검증한다."""

from copy import deepcopy
from datetime import datetime, timedelta

import pytest
from fastapi import HTTPException

from backend.features.inventory import reserve_order_inventory, release_order_inventory

NOW = datetime(2026, 10, 9, 12)
EXPIRY = NOW + timedelta(hours=1)


class MemoryConnection:
    def __init__(self):
        self.state = {
            "orders": {1: "PENDING_PAYMENT", 2: "PENDING_PAYMENT"},
            "items": {1: [{"order_item_id": 11, "product_variant_id": 1, "quantity": 2}],
                      2: [{"order_item_id": 21, "product_variant_id": 1, "quantity": 8}]},
            "balances": {1: {"product_variant_id": 1, "on_hand_quantity": 10,
                             "reserved_quantity": 0, "defective_quantity": 1}},
            "reservations": [], "movements": [], "shipped": set(),
        }
        self.queries = []
        self.savepoints = {}
        self.next_id = 1
        self.autocommit = False
        self.fail_movement = False

    def get_autocommit(self):
        return self.autocommit

    def cursor(self, cursor_class):
        return MemoryCursor(self)


class MemoryCursor:
    def __init__(self, connection):
        self.db = connection
        self.results = []
        self.lastrowid = None

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def execute(self, sql, params=()):
        sql = " ".join(sql.split())
        self.db.queries.append((sql, params))
        state = self.db.state
        if sql.startswith("SAVEPOINT "):
            self.db.savepoints[sql.split()[-1]] = deepcopy(state)
        elif sql.startswith("ROLLBACK TO SAVEPOINT "):
            self.db.state = deepcopy(self.db.savepoints[sql.split()[-1]])
        elif sql.startswith("RELEASE SAVEPOINT "):
            self.db.savepoints.pop(sql.split()[-1])
        elif sql == "SELECT CURRENT_TIMESTAMP AS db_now":
            self.results = [{"db_now": NOW}]
        elif "FROM orders WHERE" in sql:
            status = state["orders"].get(params[0])
            self.results = [] if status is None else [{"order_id": params[0], "order_status": status, "db_now": NOW}]
        elif "FROM fulfillments" in sql:
            self.results = [{"fulfillment_id": 1}] if params[0] in state["shipped"] else []
        elif "FROM order_items" in sql:
            self.results = sorted(state["items"].get(params[0], []), key=lambda item: item["product_variant_id"])
        elif "FROM inventory_reservations" in sql:
            self.results = [row for row in state["reservations"] if row["order_id"] == params[0]]
        elif "FROM headquarters_inventory" in sql:
            balance = state["balances"].get(params[0])
            self.results = [] if balance is None else [{
                **balance, "available_quantity": balance["on_hand_quantity"] - balance["reserved_quantity"] - balance["defective_quantity"],
            }]
        elif sql.startswith("INSERT INTO inventory_reservations"):
            order_id, item_id, variant_id, quantity, expiry = params
            self.lastrowid = self.db.next_id
            self.db.next_id += 1
            state["reservations"].append({
                "inventory_reservation_id": self.lastrowid, "order_id": order_id,
                "order_item_id": item_id, "product_variant_id": variant_id,
                "reserved_quantity": quantity, "reservation_status": "RESERVED",
                "expires_at": expiry, "released_at": None, "release_reason": None,
            })
        elif sql.startswith("UPDATE headquarters_inventory"):
            quantity, variant_id = params
            delta = quantity if " + " in sql else -quantity
            state["balances"][variant_id]["reserved_quantity"] += delta
        elif sql.startswith("UPDATE inventory_reservations"):
            for row in state["reservations"]:
                if row["inventory_reservation_id"] == params[1]:
                    row.update(reservation_status="RELEASED", released_at=NOW, release_reason=params[0])
        elif sql.startswith("INSERT INTO inventory_movements"):
            if self.db.fail_movement:
                raise RuntimeError("movement write failed")
            assert params[7] not in [movement[7] for movement in state["movements"]]
            state["movements"].append(params)
        else:
            raise AssertionError("Unexpected SQL: " + sql)

    def fetchone(self):
        return deepcopy(self.results[0]) if self.results else None

    def fetchall(self):
        return deepcopy(self.results)


def test_reserve_release_and_duplicate_retries():
    db = MemoryConnection()
    first = reserve_order_inventory(db, order_id=1, expires_at=EXPIRY)
    assert first.changed and first.reservations[0].reserved_quantity == 2
    assert db.state["balances"][1]["reserved_quantity"] == 2
    assert db.state["balances"][1]["on_hand_quantity"] == 10
    repeated = reserve_order_inventory(db, order_id=1, expires_at=EXPIRY + timedelta(hours=1))
    assert not repeated.changed
    assert repeated.reservations[0].expires_at == EXPIRY
    assert len(db.state["movements"]) == 1
    db.state["orders"][1] = "CANCELED"
    released = release_order_inventory(db, order_id=1, reason="주문 취소")
    assert released.changed and released.reservations[0].reservation_status == "RELEASED"
    assert db.state["balances"][1]["reserved_quantity"] == 0
    assert db.state["balances"][1]["on_hand_quantity"] == 10
    assert not release_order_inventory(db, order_id=1, reason="재시도").changed
    assert len(db.state["movements"]) == 2


def test_another_order_cannot_reserve_already_reserved_stock():
    db = MemoryConnection()
    reserve_order_inventory(db, order_id=1, expires_at=EXPIRY)
    before = deepcopy(db.state)
    with pytest.raises(HTTPException) as exc:
        reserve_order_inventory(db, order_id=2, expires_at=EXPIRY)
    assert exc.value.detail["code"] == "INSUFFICIENT_STOCK"
    assert db.state == before


def test_shortage_on_second_sku_leaves_no_partial_reservation():
    db = MemoryConnection()
    db.state["items"][1].append({"order_item_id": 12, "product_variant_id": 2, "quantity": 3})
    db.state["balances"][2] = {"product_variant_id": 2, "on_hand_quantity": 1, "reserved_quantity": 0, "defective_quantity": 0}
    before = deepcopy(db.state)
    with pytest.raises(HTTPException):
        reserve_order_inventory(db, order_id=1, expires_at=EXPIRY)
    assert db.state == before
    locks = [params[0] for query, params in db.queries if "FROM headquarters_inventory" in query]
    assert locks == [1, 2]
    assert all(query.endswith("FOR UPDATE") for query, _ in db.queries if "FROM headquarters_inventory" in query)


@pytest.mark.parametrize("action", ["reserve", "release"])
def test_movement_failure_rolls_back_inventory_changes(action):
    db = MemoryConnection()
    if action == "release":
        reserve_order_inventory(db, order_id=1, expires_at=EXPIRY)
        db.state["orders"][1] = "CANCELED"
    before = deepcopy(db.state)
    db.fail_movement = True
    with pytest.raises(RuntimeError):
        if action == "reserve":
            reserve_order_inventory(db, order_id=1, expires_at=EXPIRY)
        else:
            release_order_inventory(db, order_id=1, reason="취소")
    assert db.state == before


@pytest.mark.parametrize("status", ["PAID", "PREPARING", "SHIPPING", "COMPLETED"])
def test_release_requires_unpaid_or_canceled_order(status):
    db = MemoryConnection()
    reserve_order_inventory(db, order_id=1, expires_at=EXPIRY)
    db.state["orders"][1] = status
    before = deepcopy(db.state)
    with pytest.raises(HTTPException) as exc:
        release_order_inventory(db, order_id=1, reason="취소")
    assert exc.value.detail["code"] == "INVALID_STATE_TRANSITION"
    assert db.state == before


def test_shipped_order_cannot_release_even_with_canceled_status():
    db = MemoryConnection()
    reserve_order_inventory(db, order_id=1, expires_at=EXPIRY)
    db.state["orders"][1] = "CANCELED"
    db.state["shipped"].add(1)
    before = deepcopy(db.state)
    with pytest.raises(HTTPException):
        release_order_inventory(db, order_id=1, reason="취소")
    assert db.state == before


def test_expired_request_and_unknown_order_are_rejected():
    db = MemoryConnection()
    with pytest.raises(HTTPException) as exc:
        reserve_order_inventory(db, order_id=1, expires_at=NOW)
    assert exc.value.status_code == 400
    with pytest.raises(HTTPException) as exc:
        reserve_order_inventory(db, order_id=999, expires_at=EXPIRY)
    assert exc.value.status_code == 404
    assert not db.state["reservations"]


def test_autocommit_connection_is_rejected():
    db = MemoryConnection()
    db.autocommit = True
    with pytest.raises(HTTPException):
        reserve_order_inventory(db, order_id=1, expires_at=EXPIRY)
    assert not db.queries


def test_wrong_reservation_variant_cannot_release_other_stock():
    db = MemoryConnection()
    reserve_order_inventory(db, order_id=1, expires_at=EXPIRY)
    db.state["orders"][1] = "CANCELED"
    db.state["reservations"][0]["product_variant_id"] = 2
    before = deepcopy(db.state)
    with pytest.raises(HTTPException):
        release_order_inventory(db, order_id=1, reason="취소")
    assert db.state == before
