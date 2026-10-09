from unittest.mock import MagicMock

import pytest
from fastapi import Depends
from fastapi.testclient import TestClient

from backend.auth import check_branch, current_customer, require_permission, verified_uid
from backend.db import get_db, transaction
from backend.responses import ApiError
from backend.main import create_app
from backend.responses import PageQuery, success
from backend import auth as auth_module
from fastapi.security import HTTPAuthorizationCredentials


@pytest.fixture
def client():
    app = create_app()

    @app.get('/test/customer')
    def customer(value=Depends(current_customer)):
        return success(value)

    @app.get('/test/page')
    def page(query: PageQuery = Depends()):
        return success(query.model_dump())

    @app.get('/test/error')
    def error():
        raise RuntimeError('password=secret SQL token')

    return TestClient(app, raise_server_exceptions=False)


def test_health_and_errors(client):
    assert client.get('/api/v1/health').json() == {'data': {'status': 'ok'}}
    for path, status, code in [('/missing', 404, 'NOT_FOUND'),
                              ('/test/customer', 401, 'UNAUTHENTICATED'),
                              ('/test/page?page_size=101', 400, 'INVALID_INPUT'),
                              ('/test/error', 500, 'INTERNAL_ERROR')]:
        response = client.get(path)
        assert response.status_code == status
        assert response.json()['error']['code'] == code
        assert 'secret' not in response.text


def test_customer_from_verified_uid(client):
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.fetchone.return_value = {'customer_id': 7, 'firebase_uid': 'verified'}
    client.app.dependency_overrides[verified_uid] = lambda: 'verified'
    client.app.dependency_overrides[get_db] = lambda: db
    assert client.get('/test/customer?customer_id=999').json()['data']['customer_id'] == 7
    assert cursor.execute.call_args.args[1] == ('verified',)
    cursor.fetchone.return_value = None
    assert client.get('/test/customer').status_code == 403


def test_permission_and_branch_deny():
    employee = {'permissions': {'agreed_permission'}, 'branch_ids': {3}}
    assert require_permission('agreed_permission')(employee) is employee
    check_branch(employee, 3)
    with pytest.raises(ApiError):
        require_permission('other')(employee)
    with pytest.raises(ApiError):
        check_branch(employee, 4)


def test_transaction_commit_and_rollback():
    db = MagicMock()
    with transaction(db):
        pass
    db.commit.assert_called_once()
    with pytest.raises(ValueError):
        with transaction(db):
            raise ValueError('failure')
    db.rollback.assert_called_once()


def test_verified_token_and_invalid_token(monkeypatch):
    monkeypatch.setattr(auth_module, 'firebase_app', lambda: 'configured-app')
    verify = MagicMock(return_value={'uid': 'verified'})
    monkeypatch.setattr(auth_module.auth, 'verify_id_token', verify)
    token = HTTPAuthorizationCredentials(scheme='Bearer', credentials='id-token')
    assert verified_uid(token) == 'verified'
    verify.assert_called_once_with('id-token', app='configured-app', check_revoked=True)
    verify.side_effect = auth_module.auth.InvalidIdTokenError('invalid')
    with pytest.raises(ApiError) as caught:
        verified_uid(token)
    assert caught.value.code == 'UNAUTHENTICATED'


def test_employee_permissions_from_database():
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.fetchone.return_value = {
        'employee_id': 9, 'department': 'team', 'position': 'staff',
    }
    cursor.fetchall.side_effect = [[{'permission_code': 'agreed'}], [{'branch_id': 3}]]
    employee = auth_module.current_employee('verified', db)
    assert employee['permissions'] == {'agreed'}
    assert employee['branch_ids'] == {3}
    assert cursor.execute.call_args_list[0].args[1] == ('verified',)
    cursor.fetchone.return_value = None
    with pytest.raises(ApiError):
        auth_module.current_employee('verified', db)
