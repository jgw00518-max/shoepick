from unittest.mock import MagicMock

from fastapi import FastAPI
from fastapi.testclient import TestClient
import pytest

from backend.features import authentication as feature


@pytest.fixture
def client():
    app = FastAPI()
    app.include_router(feature.router, prefix='/api/v1')
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    app.dependency_overrides[feature.get_db] = lambda: db
    with TestClient(app) as client:
        yield client, cursor


def test_missing_token(client):
    r = client[0].get('/api/v1/authentication/customer')
    assert r.status_code == 401
    assert r.json()['error']['code'] == 'UNAUTHENTICATED'


def test_customer_uid_and_deleted_account(client):
    c, cursor = client
    c.app.dependency_overrides[feature.verified_uid] = lambda: 'verified'
    cursor.fetchone.return_value = {'customer_id': 7, 'customer_name': 'test'}
    assert c.get('/api/v1/authentication/customer?customer_id=999').json()['data']['customer_id'] == 7
    assert cursor.execute.call_args.args[1] == ('verified',)
    cursor.fetchone.return_value = None
    assert c.get('/api/v1/authentication/customer').status_code == 403


def test_inactive_employee(client):
    c, cursor = client
    c.app.dependency_overrides[feature.verified_uid] = lambda: 'verified'
    cursor.fetchone.return_value = None
    assert c.get('/api/v1/authentication/staff').status_code == 403


def test_staff_permissions_and_branch():
    employee = {'permissions': ['agreed'], 'branches': [{'branch_id': 3}]}
    assert feature.require_permission('agreed')(employee) is employee
    feature.check_branch(employee, 3)
    with pytest.raises(feature.AuthError):
        feature.require_permission('other')(employee)
    with pytest.raises(feature.AuthError):
        feature.check_branch(employee, 4)


def test_invalid_token(monkeypatch):
    from fastapi.security import HTTPAuthorizationCredentials
    monkeypatch.setattr(feature, 'get_firebase_app', lambda: 'app')
    verify = MagicMock(side_effect=feature.auth.InvalidIdTokenError('secret'))
    monkeypatch.setattr(feature.auth, 'verify_id_token', verify)
    with pytest.raises(feature.AuthError) as caught:
        feature.verified_uid(HTTPAuthorizationCredentials(scheme='Bearer', credentials='token'))
    assert caught.value.code == 'UNAUTHENTICATED'
    assert verify.call_args.kwargs['check_revoked'] is True


def test_internal_error_sanitized(client):
    c, cursor = client
    c.app.dependency_overrides[feature.verified_uid] = lambda: 'verified'
    cursor.execute.side_effect = RuntimeError('password SQL token')
    r = c.get('/api/v1/authentication/customer')
    assert r.status_code == 500
    assert 'password' not in r.text
