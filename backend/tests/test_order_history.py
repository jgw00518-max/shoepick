from unittest.mock import MagicMock

from fastapi.testclient import TestClient
import pytest

from backend.main import app
from backend.features.order_history import (
    CustomerScope, DispatchScope, OrderReadError, authenticated_customer,
    authorized_dispatch, get_db, read_detail,
)


@pytest.fixture
def client(monkeypatch):
    from backend.features import order_history
    from backend.features.order import PaidOrderListResponse
    monkeypatch.setattr(order_history, "get_paid_orders", lambda **kwargs: PaidOrderListResponse(data=[]))
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.fetchone.return_value = {'total_count': 0}
    cursor.fetchall.return_value = []
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as client:
        yield client, cursor
    app.dependency_overrides.clear()


@pytest.mark.parametrize('path', ['/customer', '/customer/1', '/staff/dispatch'])
def test_authentication_required(client, path):
    response = client[0].get('/api/v1/order-history' + path)
    assert response.status_code == 401
    assert response.json()['error']['code'] == 'UNAUTHENTICATED'


def test_customer_scope_and_empty_list(client):
    app.dependency_overrides[authenticated_customer] = lambda: CustomerScope(7)
    response = client[0].get('/api/v1/order-history/customer?customer_id=999&page=2')
    assert response.status_code == 200
    assert response.json()['data'] == []
    assert client[1].execute.call_args_list[0].args[1] == (7,)
    assert client[1].execute.call_args_list[1].args[1] == (7, 20, 20)


def test_invalid_page(client):
    app.dependency_overrides[authenticated_customer] = lambda: CustomerScope(7)
    response = client[0].get('/api/v1/order-history/customer?page_size=101')
    assert response.status_code == 400
    assert response.json()['error']['code'] == 'INVALID_INPUT'


def test_other_customer_detail_not_found():
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.fetchone.return_value = None
    with pytest.raises(OrderReadError) as error:
        read_detail(db, 7, 99)
    assert error.value.status == 404
    assert cursor.execute.call_args.args[1] == (7, 99)


def test_staff_returns_empty_paid_list(client):
    app.dependency_overrides[authorized_dispatch] = lambda: DispatchScope((3,), ('PAID',))
    assert client[0].get('/api/v1/order-history/staff/dispatch').status_code == 200
    client[1].execute.assert_not_called()


def test_staff_without_permission(client):
    app.dependency_overrides[authorized_dispatch] = lambda: DispatchScope((), ())
    assert client[0].get('/api/v1/order-history/staff/dispatch').status_code == 403


def test_dispatch_rejects_other_branch(client):
    app.dependency_overrides[authorized_dispatch] = lambda: DispatchScope((3,), ('PAID',))
    assert client[0].get('/api/v1/order-history/staff/dispatch?branch_id=4').status_code == 403
    client[1].execute.assert_not_called()


def test_dispatch_role_scope():
    assert authorized_dispatch({'roles': [{'role_code': 'HQ_STAFF'}], 'branches': []}).all_branches
    scope = authorized_dispatch({'roles': [{'role_code': 'BRANCH_MANAGER'}], 'branches': [{'branch_id': 3}]})
    assert scope.branch_ids == (3,) and not scope.all_branches
    with pytest.raises(OrderReadError):
        authorized_dispatch({'roles': [{'role_code': 'DIRECTOR'}], 'branches': []})


@pytest.mark.parametrize('path', ['/customer', '/customer/1', '/staff/dispatch'])
def test_invalid_token_blocked(client, monkeypatch, path):
    from backend.features import authentication
    monkeypatch.setattr(authentication, 'get_firebase_app', lambda: object())
    monkeypatch.setattr(authentication.auth, 'verify_id_token', MagicMock(side_effect=ValueError('invalid')))
    response = client[0].get('/api/v1/order-history' + path, headers={'Authorization': 'Bearer invalid'})
    assert response.status_code == 401
    assert response.json()['error']['code'] == 'UNAUTHENTICATED'
    client[1].execute.assert_not_called()


@pytest.mark.parametrize('query', ['page=0', 'page_size=0', 'page=x'])
def test_bad_pagination(client, query):
    app.dependency_overrides[authenticated_customer] = lambda: CustomerScope(7)
    assert client[0].get('/api/v1/order-history/customer?' + query).status_code == 400
    client[1].execute.assert_not_called()


def test_detail_route_scopes_owner_and_preserves_payload(client):
    app.dependency_overrides[authenticated_customer] = lambda: CustomerScope(7)
    client[1].fetchone.return_value = {'order_id': 5, 'order_number': 'C-5'}
    client[1].fetchall.side_effect = [[{'quantity': 2}], [{'fulfillment_status': 'PREPARING'}]]
    response = client[0].get('/api/v1/order-history/customer/5')
    assert response.status_code == 200
    assert client[1].execute.call_args_list[0].args[1] == (7, 5)
    assert response.json()['data']['items'] == [{'quantity': 2}]
    assert response.json()['data']['fulfillments'][0]['fulfillment_status'] == 'PREPARING'


def test_detail_route_hides_other_customer(client):
    app.dependency_overrides[authenticated_customer] = lambda: CustomerScope(7)
    client[1].fetchone.return_value = None
    response = client[0].get('/api/v1/order-history/customer/5')
    assert response.status_code == 404
    assert client[1].execute.call_args.args[1] == (7, 5)


def test_list_has_stable_tie_breaker(client):
    app.dependency_overrides[authenticated_customer] = lambda: CustomerScope(7)
    client[0].get('/api/v1/order-history/customer')
    # SQL 정렬 계약만 확인하며 실제 DB 정렬 실행 검증과 구분한다.
    assert 'ORDER BY o.ordered_at DESC, o.order_id DESC' in client[1].execute.call_args.args[0]


@pytest.mark.parametrize('role', ['BRANCH_STAFF', 'BRANCH_MANAGER', 'HQ_STAFF', 'TEAM_LEAD', 'DIRECTOR', 'EXECUTIVE', 'ADMIN'])
def test_staff_real_scope_adapter(client, role):
    from backend.features.authentication import current_employee
    app.dependency_overrides[current_employee] = lambda: {
        'roles': [{'role_code': role}], 'branches': [{'branch_id': 3}],
        'permissions': ['orders.dispatch.read'],
    }
    response = client[0].get('/api/v1/order-history/staff/dispatch?branch_id=4')
    assert response.status_code == (200 if role == 'HQ_STAFF' else 403)
    client[1].execute.assert_not_called()


@pytest.mark.parametrize('role', ['BRANCH_STAFF', 'BRANCH_MANAGER', 'HQ_STAFF'])
def test_allowed_staff_own_branch_returns_empty(client, role):
    from backend.features.authentication import current_employee
    app.dependency_overrides[current_employee] = lambda: {
        'roles': [{'role_code': role}], 'branches': [{'branch_id': 3}],
        'permissions': ['orders.dispatch.read'],
    }
    response = client[0].get('/api/v1/order-history/staff/dispatch?branch_id=3')
    assert response.status_code == 200
    assert response.json()['data'] == []
    client[1].execute.assert_not_called()
