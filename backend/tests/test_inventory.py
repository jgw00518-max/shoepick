"""실제 DB 변경 없이 재고 조회 API와 입력·오류 처리를 검증한다."""

from datetime import datetime

import pytest
from fastapi.testclient import TestClient
from pymysql import OperationalError

from backend.features.inventory import get_db
from backend.main import app


class FakeCursor:
    def __init__(self, rows, total_count):
        self.rows = rows
        self.total_count = total_count
        self.calls = []
        self.branch_exists = True

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def execute(self, query, parameters):
        self.calls.append((query, parameters))

    def fetchone(self):
        if self.calls[-1][0].startswith("SELECT branch_id FROM branches"):
            return {"branch_id": self.calls[-1][1][0]} if self.branch_exists else None
        return {"total_count": self.total_count}

    def fetchall(self):
        return self.rows


@pytest.fixture
def client():
    class FakeConnection:
        cursor_result = FakeCursor([], 0)

        def cursor(self, cursor_class):
            return self.cursor_result

    connection = FakeConnection()
    app.dependency_overrides[get_db] = lambda: connection
    try:
        with TestClient(app) as test_client:
            yield test_client, connection
    finally:
        app.dependency_overrides.clear()


def test_inventory_fields_and_pagination(client):
    test_client, connection = client
    connection.cursor_result = FakeCursor([
        {"product_variant_id": 12, "product_id": 3, "product_code": "SKU-12",
         "product_name": "운동화", "color_code": "BLK", "color_name": "검정",
         "size_mm": 250, "on_hand_quantity": 100, "reserved_quantity": 10,
         "defective_quantity": 2, "available_quantity": 88,
         "updated_at": datetime(2026, 10, 9, 12)},
    ], 21)
    response = test_client.get("/api/v1/inventory/headquarters?page=2&page_size=20")
    assert response.status_code == 200
    assert response.json()["pagination"] == {"page": 2, "page_size": 20, "total_count": 21}
    assert response.json()["data"][0]["available_quantity"] == 88
    query, parameters = connection.cursor_result.calls[-1]
    assert "hi.updated_at DESC, hi.product_variant_id ASC" in query
    assert parameters == (20, 20)


def test_empty_inventory(client):
    test_client, _ = client
    response = test_client.get("/api/v1/inventory/headquarters")
    assert response.status_code == 200
    assert response.json() == {"data": [], "pagination": {"page": 1, "page_size": 20, "total_count": 0}}


def test_keyword_and_variant_are_bound_parameters(client):
    test_client, connection = client
    keyword = "%' OR 1=1 --_!"
    response = test_client.get("/api/v1/inventory/headquarters", params={"keyword": keyword, "product_variant_id": 12})
    assert response.status_code == 200
    for query, parameters in connection.cursor_result.calls:
        assert keyword not in query
        assert parameters[:3] == ("%!%' OR 1=1 --!_!!%", "%!%' OR 1=1 --!_!!%", 12)


@pytest.mark.parametrize("params", [
    {"page": 0}, {"page_size": 101}, {"product_variant_id": -1},
    {"sort": "updated_at; DROP TABLE products"}, {"order": "anything"},
])
def test_invalid_query(client, params):
    test_client, connection = client
    response = test_client.get("/api/v1/inventory/headquarters", params=params)
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "INVALID_INPUT"
    assert not connection.cursor_result.calls


def test_database_connection_failure_is_not_exposed(client):
    test_client, _ = client

    def fail():
        raise OperationalError(2003, "private connection information")

    app.dependency_overrides[get_db] = fail
    response = test_client.get("/api/v1/inventory/headquarters")
    assert response.status_code == 500
    assert response.json()["error"]["code"] == "INTERNAL_ERROR"
    assert "private connection information" not in response.text


def test_branch_inventory_filters_and_order_snapshot(client):
    test_client, connection = client
    connection.cursor_result = FakeCursor([
        {"pickup_holding_id": 4, "branch_id": 1, "branch_name": "강남점",
         "fulfillment_item_id": 3, "fulfillment_id": 2, "fulfillment_number": "FUL-2",
         "order_id": 5, "order_number": "ORDER-5", "order_item_id": 6,
         "product_variant_id": 12, "product_code": "SKU-12", "product_name": "주문 당시 운동화",
         "color_name": "검정", "size_mm": 250, "quantity": 2,
         "holding_status": "READY_FOR_PICKUP", "received_at": datetime(2026, 10, 9, 12),
         "ready_at": None, "picked_up_at": None, "recalled_at": None,
         "updated_at": datetime(2026, 10, 9, 12)},
    ], 21)
    response = test_client.get("/api/v1/inventory/branches/1", params={
        "page": 2, "holding_status": "READY_FOR_PICKUP", "product_variant_id": 12,
        "keyword": "%' OR 1=1 --", "sort": "product_name", "order": "asc",
    })
    assert response.status_code == 200
    assert response.json()["data"][0]["product_name"] == "주문 당시 운동화"
    assert response.json()["data"][0]["picked_up_at"] is None
    assert response.json()["pagination"] == {"page": 2, "page_size": 20, "total_count": 21}
    for query, parameters in connection.cursor_result.calls[1:]:
        assert "ph.branch_id = %s" in query
        assert "ph.holding_status = %s" in query
        assert "%' OR 1=1 --" not in query
        assert parameters[:3] == (1, "READY_FOR_PICKUP", 12)
        assert parameters[3:5] == ("%!%' OR 1=1 --%", "%!%' OR 1=1 --%")
    query, parameters = connection.cursor_result.calls[-1]
    assert "oi.product_name ASC, ph.pickup_holding_id ASC" in query
    assert parameters[-2:] == (20, 20)


def test_existing_branch_without_holdings(client):
    test_client, _ = client
    response = test_client.get("/api/v1/inventory/branches/1")
    assert response.status_code == 200
    assert response.json() == {"data": [], "pagination": {"page": 1, "page_size": 20, "total_count": 0}}


def test_unknown_branch(client):
    test_client, connection = client
    connection.cursor_result.branch_exists = False
    response = test_client.get("/api/v1/inventory/branches/999999")
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "NOT_FOUND"
    assert len(connection.cursor_result.calls) == 1


@pytest.mark.parametrize("path,params", [
    ("0", {}), ("invalid", {}), ("1", {"holding_status": "OTHER"}),
    ("1", {"sort": "DROP TABLE"}), ("1", {"page_size": 101}),
])
def test_invalid_branch_query(client, path, params):
    test_client, connection = client
    response = test_client.get("/api/v1/inventory/branches/" + path, params=params)
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "INVALID_INPUT"
    assert not connection.cursor_result.calls
