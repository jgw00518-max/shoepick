from functools import lru_cache
from pathlib import Path

import firebase_admin
from firebase_admin import auth, credentials
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from backend.config import get_settings
from backend.db import get_db
from backend.responses import ApiError

bearer = HTTPBearer(auto_error=False)


@lru_cache
def firebase_app():
    settings = get_settings()
    if not settings.firebase_project_id:
        raise RuntimeError('Firebase configuration is missing')
    credential = None
    if settings.firebase_credentials_path:
        path = Path(settings.firebase_credentials_path)
        if not path.is_absolute():
            path = Path(__file__).parent / path
        credential = credentials.Certificate(str(path))
    return firebase_admin.initialize_app(
        credential, {'projectId': settings.firebase_project_id}, name='shoepick'
    )


def verified_uid(token: HTTPAuthorizationCredentials | None = Depends(bearer)) -> str:
    """Firebase가 검증한 UID만 DB 조회에 사용한다."""
    if token is None:
        raise ApiError('UNAUTHENTICATED')
    app = firebase_app()
    try:
        claims = auth.verify_id_token(token.credentials, app=app, check_revoked=True)
    except (auth.InvalidIdTokenError, auth.ExpiredIdTokenError,
            auth.RevokedIdTokenError, auth.UserDisabledError, ValueError):
        raise ApiError('UNAUTHENTICATED') from None
    return claims['uid']


def current_customer(uid: str = Depends(verified_uid), db=Depends(get_db)):
    with db.cursor() as cursor:
        cursor.execute(
            'SELECT customer_id, firebase_uid FROM customers '
            'WHERE firebase_uid=%s AND deleted_at IS NULL', (uid,)
        )
        customer = cursor.fetchone()
    if customer is None:
        raise ApiError('FORBIDDEN')
    return customer


def current_employee(uid: str = Depends(verified_uid), db=Depends(get_db)):
    with db.cursor() as cursor:
        cursor.execute(
            'SELECT employee_id, department, position FROM employees '
            'WHERE firebase_uid=%s AND is_active=1', (uid,)
        )
        employee = cursor.fetchone()
        if employee is None:
            raise ApiError('FORBIDDEN')
        cursor.execute(
            'SELECT DISTINCT p.permission_code FROM employee_roles er '
            'JOIN roles r ON r.role_id=er.role_id AND r.is_active=1 '
            'JOIN role_permissions rp ON rp.role_id=r.role_id '
            'JOIN permissions p ON p.permission_id=rp.permission_id '
            'WHERE er.employee_id=%s', (employee['employee_id'],)
        )
        employee['permissions'] = {row['permission_code'] for row in cursor.fetchall()}
        cursor.execute(
            'SELECT branch_id FROM employee_branch_assignments '
            'WHERE employee_id=%s AND assigned_at<=CURRENT_TIMESTAMP '
            'AND (ended_at IS NULL OR ended_at>CURRENT_TIMESTAMP)',
            (employee['employee_id'],)
        )
        employee['branch_ids'] = {row['branch_id'] for row in cursor.fetchall()}
    return employee


def require_permission(permission_code: str):
    """B와 합의한 실제 권한 코드를 사용한다. 없는 권한은 허용하지 않는다."""
    def check(employee=Depends(current_employee)):
        if permission_code not in employee['permissions']:
            raise ApiError('FORBIDDEN')
        return employee
    return check


def check_branch(employee: dict, branch_id: int):
    if branch_id not in employee['branch_ids']:
        raise ApiError('FORBIDDEN')
