from unittest.mock import MagicMock

from fastapi.testclient import TestClient
import pytest

from backend.main import app
from backend.features.order_history import (
    CustomerScope, DispatchScope, OrderReadError, authenticated_customer,
    authorized_dispatch, get_db, read_detail,
)


@pytest.fixture
def client():
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.fetchone.return_value = {'total_count': 0}
    cursor.fetchall.return_value = []
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as client:
        yield client, cursor
    app.dependency_overrides.clear()


def test_authentication_required(client):
    response = client[0].get('/api/v1/order-history/customer')
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


def test_staff_waits_for_a_contract(client):
    app.dependency_overrides[authorized_dispatch] = lambda: DispatchScope((3,), ('PAID',))
    assert client[0].get('/api/v1/order-history/staff/dispatch').status_code == 503
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
