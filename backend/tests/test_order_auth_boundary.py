"""실제 데이터 없이 기존 주문 API의 인증 경계를 검증한다."""
from unittest.mock import MagicMock

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from backend.features import order, authentication


@pytest.fixture
def setup():
    app = FastAPI()
    app.include_router(order.router, prefix='/api/v1')
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    app.dependency_overrides[order.get_db] = lambda: db
    with TestClient(app) as client:
        yield app, client, db, cursor


@pytest.mark.parametrize('path,method', [
    ('/orders/paid', 'get'), ('/orders/11', 'get'),
    ('/orders/11/mock-payment', 'post'),
])
def test_order_endpoints_require_token(setup, path, method):
    _, client, db, _ = setup
    response = getattr(client, method)('/api/v1' + path,
        **({'json': {'transaction_key': 'test'}} if method == 'post' else {}))
    assert response.status_code == 401
    assert response.headers['www-authenticate'] == 'Bearer'
    db.commit.assert_not_called()


def test_paid_list_uses_verified_customer_not_query(setup):
    app, client, _, cursor = setup
    app.dependency_overrides[authentication.current_customer] = lambda: {'customer_id': 7}
    cursor.fetchall.return_value = []
    assert client.get('/api/v1/orders/paid?customer_id=999').status_code == 200
    sql, params = cursor.execute.call_args.args
    assert 'o.customer_id = %s' in sql
    assert params == (7,)


@pytest.mark.parametrize('method,suffix', [('get', ''), ('post', '/mock-payment')])
def test_other_customer_order_is_hidden_before_any_write(setup, method, suffix):
    app, client, db, cursor = setup
    app.dependency_overrides[authentication.current_customer] = lambda: {'customer_id': 7}
    cursor.fetchone.return_value = None
    response = getattr(client, method)('/api/v1/orders/11' + suffix,
        **({'json': {'transaction_key': 'test'}} if method == 'post' else {}))
    assert response.status_code == 404
    sql, params = cursor.execute.call_args.args
    assert 'customer_id = %s' in sql
    assert params == (11, 7)
    assert cursor.execute.call_count == 1
    db.commit.assert_not_called()


def test_staff_only_uid_cannot_read_customer_orders(setup):
    app, client, _, cursor = setup
    app.dependency_overrides[authentication.verified_uid] = lambda: 'staff-only'
    cursor.fetchone.return_value = None
    assert client.get('/api/v1/orders/paid').status_code == 403


def test_owner_can_read_order_detail(setup):
    from datetime import datetime
    app, client, _, cursor = setup
    app.dependency_overrides[authentication.current_customer] = lambda: {'customer_id': 7}
    cursor.fetchone.return_value = {
        'order_id': 11, 'order_number': 'TEST-11', 'order_status': 'PAID',
        'pickup_branch_id': 3, 'branch_name': 'test', 'paid_total': 100,
        'ordered_at': datetime(2026, 10, 23),
    }
    cursor.fetchall.return_value = []
    response = client.get('/api/v1/orders/11')
    assert response.status_code == 200
    assert response.json()['data']['order_id'] == 11
    assert cursor.execute.call_args_list[0].args[1] == (11, 7)
