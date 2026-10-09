from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException
from typing import Any, Literal

from pydantic import BaseModel, Field


class PageQuery(BaseModel):
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)
    keyword: str | None = None
    order: Literal['asc', 'desc'] = 'desc'


def success(data: Any = None, message: str | None = None) -> dict:
    result = {'data': data}
    if message is not None:
        result['message'] = message
    return result


def paginated(data: list, page: int, page_size: int, total_count: int) -> dict:
    return {'data': data, 'pagination': {
        'page': page, 'page_size': page_size, 'total_count': total_count,
    }}


ERRORS = {
    'INVALID_INPUT': (400, '입력값을 확인해주세요.'),
    'UNAUTHENTICATED': (401, '로그인이 필요합니다.'),
    'FORBIDDEN': (403, '접근 권한이 없습니다.'),
    'NOT_FOUND': (404, '대상을 찾을 수 없습니다.'),
    'INSUFFICIENT_STOCK': (409, '재고가 부족합니다.'),
    'INVALID_STATE_TRANSITION': (409, '현재 상태에서는 처리할 수 없습니다.'),
    'ALREADY_PROCESSED': (409, '이미 처리된 요청입니다.'),
    'INTERNAL_ERROR': (500, '서버 처리 중 오류가 발생했습니다.'),
}


class ApiError(Exception):
    def __init__(self, code: str):
        self.code = code
        self.status_code, self.message = ERRORS[code]


def error_response(code: str, status_code: int | None = None):
    status, message = ERRORS[code]
    headers = {'WWW-Authenticate': 'Bearer'} if (status_code or status) == 401 else None
    return JSONResponse(
        status_code=status_code or status,
        content={'error': {'code': code, 'message': message}}, headers=headers,
    )


def register_error_handlers(app: FastAPI):
    """입력·인증·내부 예외를 통일하고 토큰이나 SQL은 응답에 포함하지 않는다."""
    async def api_error(request: Request, exc: ApiError):
        return error_response(exc.code)

    async def validation_error(request: Request, exc: RequestValidationError):
        return error_response('INVALID_INPUT')

    async def http_error(request: Request, exc: HTTPException):
        code = {400: 'INVALID_INPUT', 401: 'UNAUTHENTICATED',
                403: 'FORBIDDEN', 404: 'NOT_FOUND',
                409: 'INVALID_STATE_TRANSITION'}.get(exc.status_code, 'INTERNAL_ERROR')
        return error_response(code, exc.status_code)

    async def internal_error(request: Request, exc: Exception):
        return error_response('INTERNAL_ERROR')

    app.add_exception_handler(ApiError, api_error)
    app.add_exception_handler(RequestValidationError, validation_error)
    app.add_exception_handler(HTTPException, http_error)
    app.add_exception_handler(Exception, internal_error)
