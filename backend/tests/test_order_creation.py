"""실제 DB 변경 없이 주문 원자성·중복 요청·30분 만료·인증을 검증한다."""

from datetime import datetime, timedelta
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from backend.features import order
from backend.main import app


NOW = datetime(2026, 10, 10, 18)
CUSTOMER = {"customer_id": 7}


def request():
    return order.OrderCreateRequest(
        branch_id=1, order_request_key="order-unique-1",
        items=[order.OrderCreateItem(product_variant_id=2, quantity=3)],
    )


def connection(results):
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.fetchone.side_effect = results
    cursor.lastrowid = 10
    return db, cursor


def prepared(monkeypatch):
    monkeypatch.setattr(order, "prepare_order", lambda *args: {
        "subtotal_amount": 90000,
        "items": [{"product_variant_id": 2, "product_name": "운동화",
                   "product_code": "SHOE-2", "color_name": "검정", "size_mm": 260,
                   "unit_price": 30000, "quantity": 3}],
    })


def test_create_saves_items_history_and_reserves_exactly_30_minutes(monkeypatch):
    prepared(monkeypatch)
    reserve = MagicMock()
    monkeypatch.setattr(order, "reserve_order_inventory", reserve)
    db, cursor = connection([CUSTOMER, None, {"db_now": NOW}])
    response = order.create_order(request(), CUSTOMER, db)
    assert response.data.order_id == 10
    assert response.data.paid_total == 90000
    assert response.data.expires_at == NOW + timedelta(minutes=30)
    reserve.assert_called_once_with(db, order_id=10, expires_at=NOW + timedelta(minutes=30))
    sql = [call.args[0] for call in cursor.execute.call_args_list]
    assert any("INSERT INTO orders" in value for value in sql)
    assert any("INSERT INTO order_items" in value for value in sql)
    assert any("INSERT INTO order_status_history" in value for value in sql)
    db.commit.assert_called_once()
    db.rollback.assert_not_called()


def test_stock_failure_rolls_back_order_and_items(monkeypatch):
    prepared(monkeypatch)
    monkeypatch.setattr(order, "reserve_order_inventory", MagicMock(
        side_effect=HTTPException(409, detail={"code": "INSUFFICIENT_STOCK"})))
    db, _ = connection([CUSTOMER, None, {"db_now": NOW}])
    with pytest.raises(HTTPException):
        order.create_order(request(), CUSTOMER, db)
    db.rollback.assert_called_once()
    db.commit.assert_not_called()


@pytest.mark.parametrize("owner,branch,items,success", [
    (7, 1, [(2, 3)], True), (8, 1, [(2, 3)], False),
    (7, 2, [(2, 3)], False), (7, 1, [(2, 4)], False),
])
def test_retry_checks_owner_branch_items_without_new_reservation(monkeypatch, owner, branch, items, success):
    reserve = MagicMock()
    monkeypatch.setattr(order, "reserve_order_inventory", reserve)
    monkeypatch.setattr(order, "cancel_expired_order", lambda *args: False)
    previous = {"order_id": 10, "order_number": "existing", "customer_id": owner,
                "pickup_branch_id": branch, "order_status": "PENDING_PAYMENT",
                "paid_total": 90000, "ordered_at": NOW}
    db, cursor = connection([CUSTOMER, previous])
    cursor.fetchall.return_value = [{"product_variant_id": variant, "quantity": quantity}
                                   for variant, quantity in items]
    if success:
        response = order.create_order(request(), CUSTOMER, db)
        assert response.data.order_number == "existing"
        assert response.data.expires_at == NOW + timedelta(minutes=30)
        db.commit.assert_called_once()
    else:
        with pytest.raises(HTTPException) as error:
            order.create_order(request(), CUSTOMER, db)
        assert error.value.status_code == 409
        db.rollback.assert_called_once()
    reserve.assert_not_called()
    assert not any("INSERT INTO orders" in call.args[0] for call in cursor.execute.call_args_list)


@pytest.mark.parametrize("status,expired,changed", [
    ("PENDING_PAYMENT", True, True), ("PENDING_PAYMENT", False, False),
    ("PAID", True, False), ("CANCELED", True, False),
])
def test_expiry_releases_only_unpaid_expired_orders(monkeypatch, status, expired, changed):
    release = MagicMock()
    monkeypatch.setattr(order, "release_order_inventory", release)
    db, cursor = connection([{"order_status": status}, {"inventory_reservation_id": 1} if expired else None])
    assert order.cancel_expired_order(db, 10) is changed
    assert release.call_count == int(changed)
    assert any("UPDATE orders" in call.args[0] for call in cursor.execute.call_args_list) is changed
    db.commit.assert_not_called()


def test_expired_payment_commits_cancellation_without_creating_payment(monkeypatch):
    monkeypatch.setattr(order, "cancel_expired_order", lambda *args: True)
    db, cursor = connection([{"order_id": 10, "order_status": "PENDING_PAYMENT", "paid_total": 90000}, None])
    with pytest.raises(HTTPException) as error:
        order.pay_order_mock(order.MockPaymentRequest(transaction_key="pay-1"), CUSTOMER, 10, db)
    assert error.value.detail["code"] == "PAYMENT_EXPIRED"
    db.commit.assert_called_once()
    assert not any("INSERT INTO payments" in call.args[0] for call in cursor.execute.call_args_list)


def test_other_customer_cannot_pay(monkeypatch):
    db, cursor = connection([None])
    with pytest.raises(HTTPException) as error:
        order.pay_order_mock(order.MockPaymentRequest(transaction_key="pay-1"), CUSTOMER, 10, db)
    assert error.value.status_code == 404
    assert cursor.execute.call_args.args[1] == (10, CUSTOMER["customer_id"])
    db.commit.assert_not_called()


def test_new_order_requires_login_before_database_access():
    with TestClient(app) as client:
        response = client.post("/api/v1/orders", json=request().model_dump())
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHENTICATED"


def test_valid_payment_saves_payment_and_status_once(monkeypatch):
    monkeypatch.setattr(order, "cancel_expired_order", lambda *args: False)
    db, cursor = connection([
        {"order_id": 10, "order_status": "PENDING_PAYMENT", "paid_total": 90000},
        None, None, None,
    ])
    response = order.pay_order_mock(order.MockPaymentRequest(transaction_key="pay-1"), CUSTOMER, 10, db)
    assert response.data.order_status == "PAID"
    assert response.data.paid_total == 90000
    assert any("INSERT INTO payments" in call.args[0] for call in cursor.execute.call_args_list)
    db.commit.assert_called_once()
    db.rollback.assert_not_called()


def test_paid_retry_returns_previous_result_without_releasing_stock(monkeypatch):
    expire = MagicMock()
    monkeypatch.setattr(order, "cancel_expired_order", expire)
    db, cursor = connection([
        {"order_id": 10, "order_status": "PAID", "paid_total": 90000},
        {"order_id": 10, "payment_id": 4, "payment_status": "PAID"},
    ])
    response = order.pay_order_mock(order.MockPaymentRequest(transaction_key="pay-1"), CUSTOMER, 10, db)
    assert response.data.payment_id == 4
    expire.assert_not_called()
    assert not any("INSERT INTO payments" in call.args[0] for call in cursor.execute.call_args_list)


def test_expiry_worker_rechecks_each_order_and_continues_after_failure(monkeypatch):
    from backend import expire_pending_orders as worker
    db, cursor = connection([])
    cursor.fetchall.return_value = [{"order_id": 1}, {"order_id": 2}, {"order_id": 3}]
    monkeypatch.setattr(worker, "connect", lambda: db)
    expire = MagicMock(side_effect=[True, RuntimeError("검사 오류"), False])
    monkeypatch.setattr(worker, "cancel_expired_order", expire)
    assert worker.expire_pending_orders() == 1
    assert [call.args[1] for call in expire.call_args_list] == [1, 2, 3]
    assert db.commit.call_count == 2
    assert db.rollback.call_count == 2
    db.close.assert_called_once()
