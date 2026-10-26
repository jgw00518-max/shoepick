"""직원 업무 API의 허용·거부를 실제 라우터 의존성으로 검증한다."""

from unittest.mock import MagicMock

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.auth_policy import HQ_INVENTORY_READ, BRANCH_INVENTORY_READ, DISPATCH_READ
from backend.features import authentication, inventory, order_history


@pytest.fixture
def session():
    app = FastAPI()
    app.include_router(inventory.router, prefix='/api/v1')
    app.include_router(order_history.router, prefix='/api/v1')
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.fetchone.side_effect = lambda: (
        {'branch_id': 3} if cursor.execute.call_args.args[0].startswith('SELECT branch_id')
        else {'total_count': 0}
    )
    cursor.fetchall.return_value = []
    app.dependency_overrides[inventory.get_db] = lambda: db
    with TestClient(app) as client:
        yield app, client, cursor


def employee(permissions=(), branches=(), role='HQ_STAFF'):
    return {'employee_id': 1, 'permissions': list(permissions),
            'branches': [{'branch_id': branch} for branch in branches],
            'roles': [{'role_code': role}]}


@pytest.mark.parametrize('path', [
    '/inventory/headquarters', '/inventory/branches/3', '/order-history/staff/dispatch',
])
def test_missing_token_denied(session, path):
    _, client, cursor = session
    response = client.get('/api/v1' + path)
    assert response.status_code == 401
    assert response.json()['error']['code'] == 'UNAUTHENTICATED'
    cursor.execute.assert_not_called()


@pytest.mark.parametrize('path', [
    '/inventory/headquarters', '/inventory/branches/3', '/order-history/staff/dispatch',
])
def test_forged_permission_query_cannot_grant_access(session, path):
    app, client, cursor = session
    app.dependency_overrides[authentication.current_employee] = lambda: employee()
    response = client.get('/api/v1' + path, params={
        'permission': HQ_INVENTORY_READ, 'role': 'HQ_STAFF', 'employee_id': 999,
    })
    assert response.status_code == 403
    cursor.execute.assert_not_called()


def test_headquarters_permission_allows_read(session):
    app, client, cursor = session
    app.dependency_overrides[authentication.current_employee] = lambda: employee([HQ_INVENTORY_READ])
    assert client.get('/api/v1/inventory/headquarters').status_code == 200
    assert cursor.execute.call_count == 2


def test_branch_permission_and_membership_both_required(session):
    app, client, cursor = session
    app.dependency_overrides[authentication.current_employee] = lambda: employee(
        [BRANCH_INVENTORY_READ], [3], 'BRANCH_STAFF')
    assert client.get('/api/v1/inventory/branches/3').status_code == 200
    cursor.reset_mock()
    assert client.get('/api/v1/inventory/branches/4?branch_id=3').status_code == 403
    cursor.execute.assert_not_called()
    app.dependency_overrides[authentication.current_employee] = lambda: employee([], [3])
    assert client.get('/api/v1/inventory/branches/3').status_code == 403
    cursor.execute.assert_not_called()


def test_dispatch_permission_does_not_bypass_branch_scope(session):
    app, client, cursor = session
    app.dependency_overrides[authentication.current_employee] = lambda: employee(
        [DISPATCH_READ], [3], 'BRANCH_MANAGER')
    assert client.get('/api/v1/order-history/staff/dispatch?branch_id=4').status_code == 403
    # 최신 C 조회 함수는 권한·지점 검사 후 A 결제 완료 함수를 호출한다.
    assert client.get('/api/v1/order-history/staff/dispatch?branch_id=3').status_code == 200
    assert cursor.execute.call_count == 1


def test_customer_only_identity_is_not_employee(session):
    app, client, cursor = session
    app.dependency_overrides[authentication.verified_uid] = lambda: 'customer-only'
    cursor.fetchone.side_effect = None
    cursor.fetchone.return_value = None
    assert client.get('/api/v1/inventory/headquarters').status_code == 403
