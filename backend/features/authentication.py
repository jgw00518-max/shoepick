"""B 공통 인증: 검증된 Firebase UID와 기존 MySQL 회원·직원 정보를 연결한다."""

from functools import lru_cache
import logging
import os
from pathlib import Path

from fastapi import APIRouter, Depends
from fastapi.routing import APIRoute
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import firebase_admin
from firebase_admin import auth, credentials
import pymysql

if __package__ and __package__.startswith('backend.'):
    from ..dependencies import get_db
else:
    from dependencies import get_db


class AuthError(Exception):
    def __init__(self, code: str):
        self.code = code


class AuthRoute(APIRoute):
    """공통 인증 오류는 다른 담당 API에서도 이 route_class로 동일하게 처리한다."""

    def get_route_handler(self):
        handler = super().get_route_handler()

        async def handle(request):
            try:
                return await handler(request)
            except AuthError as error:
                status, message = {
                    'UNAUTHENTICATED': (401, '로그인이 필요합니다.'),
                    'FORBIDDEN': (403, '접근 권한이 없습니다.'),
                }[error.code]
                return JSONResponse(status_code=status, content={'error': {
                    'code': error.code, 'message': message,
                }}, headers={'WWW-Authenticate': 'Bearer'} if status == 401 else None)
            except RequestValidationError:
                return JSONResponse(status_code=400, content={'error': {
                    'code': 'INVALID_INPUT', 'message': '입력값을 확인해주세요.',
                }})
            except Exception:
                return JSONResponse(status_code=500, content={'error': {
                    'code': 'INTERNAL_ERROR', 'message': '서버 처리 중 오류가 발생했습니다.',
                }})
        return handle


bearer = HTTPBearer(auto_error=False)
router = APIRouter(prefix='/authentication', tags=['B 인증'], route_class=AuthRoute)


@lru_cache
def get_firebase_app():
    """키는 로컬 설정에서 읽고 프로젝트 ID를 명시한다. 설정 실패는 인증 실패로 숨기지 않는다."""
    project_id = os.getenv('FIREBASE_PROJECT_ID')
    if not project_id:
        raise RuntimeError('Firebase project configuration is missing')
    path = os.getenv('FIREBASE_CREDENTIALS_PATH')
    credential = None
    if path:
        key_path = Path(path)
        if not key_path.is_absolute():
            key_path = Path(__file__).resolve().parents[1] / key_path
        credential = credentials.Certificate(str(key_path))
    return firebase_admin.initialize_app(credential, {'projectId': project_id}, name='shoepick-auth')


def verified_uid(token: HTTPAuthorizationCredentials | None = Depends(bearer)) -> str:
    if token is None:
        logging.getLogger(__name__).warning('Firebase authentication failed: missing Bearer token')
        raise AuthError('UNAUTHENTICATED')
    app = get_firebase_app()
    try:
        # Allow small clock differences between the local server and Firebase.
        claims = auth.verify_id_token(
            token.credentials, app=app, check_revoked=True, clock_skew_seconds=30,
        )
    except (auth.InvalidIdTokenError, auth.ExpiredIdTokenError,
            auth.RevokedIdTokenError, auth.UserDisabledError, ValueError) as error:
        # Log only fixed categories; exception messages may contain token data.
        message = str(error).lower()
        reason = next((label for keyword, label in (
            ('used too early', 'token used too early; check system clocks'),
            ('expired', 'token expired'),
            ('audience', 'Firebase project audience mismatch'),
            ('issuer', 'Firebase project issuer mismatch'),
            ('signature', 'token signature verification failed'),
            ('revoked', 'token revoked'),
            ('disabled', 'Firebase user disabled'),
        ) if keyword in message), 'token rejected')
        logging.getLogger(__name__).warning(
            'Firebase authentication failed: %s (%s)', type(error).__name__, reason,
        )
        raise AuthError('UNAUTHENTICATED') from None
    return claims['uid']


def current_customer(uid: str = Depends(verified_uid), db=Depends(get_db)) -> dict:
    """요청의 회원 ID 대신 검증된 UID로 삭제되지 않은 고객을 찾는다."""
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute(
            'SELECT customer_id, firebase_uid, customer_name FROM customers '
            'WHERE firebase_uid=%s AND deleted_at IS NULL', (uid,),
        )
        customer = cursor.fetchone()
    if customer is None:
        raise AuthError('FORBIDDEN')
    return customer


def current_employee(uid: str = Depends(verified_uid), db=Depends(get_db)) -> dict:
    """활성 직원의 실제 직급·권한·소속을 DB에서 읽는다."""
    with db.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute(
            'SELECT employee_id, employee_code, employee_name, department, position '
            'FROM employees WHERE firebase_uid=%s AND is_active=1', (uid,),
        )
        employee = cursor.fetchone()
        if employee is None:
            raise AuthError('FORBIDDEN')
        cursor.execute(
            'SELECT r.role_code, r.role_name FROM employee_roles er '
            'JOIN roles r ON r.role_id=er.role_id AND r.is_active=1 '
            'WHERE er.employee_id=%s ORDER BY r.role_id', (employee['employee_id'],),
        )
        employee['roles'] = cursor.fetchall()
        cursor.execute(
            'SELECT DISTINCT p.permission_code FROM employee_roles er '
            'JOIN roles r ON r.role_id=er.role_id AND r.is_active=1 '
            'JOIN role_permissions rp ON rp.role_id=r.role_id '
            'JOIN permissions p ON p.permission_id=rp.permission_id '
            'WHERE er.employee_id=%s ORDER BY p.permission_code', (employee['employee_id'],),
        )
        employee['permissions'] = [row['permission_code'] for row in cursor.fetchall()]
        cursor.execute(
            'SELECT DISTINCT b.branch_id, b.branch_code, b.branch_name, b.district_code '
            'FROM employee_branch_assignments a JOIN branches b ON b.branch_id=a.branch_id '
            'WHERE a.employee_id=%s AND a.assigned_at<=CURRENT_TIMESTAMP '
            'AND (a.ended_at IS NULL OR a.ended_at>CURRENT_TIMESTAMP) AND b.is_active=1 '
            'ORDER BY b.branch_id', (employee['employee_id'],),
        )
        employee['branches'] = cursor.fetchall()
    return employee


def require_permission(permission_code: str):
    """각 담당이 B와 합의한 기존 업무 권한 코드를 전달한다."""
    def check(employee=Depends(current_employee)):
        if permission_code not in employee['permissions']:
            raise AuthError('FORBIDDEN')
        return employee
    return check


def check_branch(employee: dict, branch_id: int):
    if branch_id not in {branch['branch_id'] for branch in employee['branches']}:
        raise AuthError('FORBIDDEN')


@router.get('/customer')
def customer_session(customer=Depends(current_customer)):
    return {'data': customer}


@router.get('/staff')
def employee_session(employee=Depends(current_employee)):
    return {'data': employee}
