import logging

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pymysql import MySQLError

if __package__:
    from .features import (
        authentication,
        dashboard,
        goods_receipts,
        inventory,
        order_history,
        manufacturer_orders,
        purchase_approvals,
        purchase_requisitions,
        products,
        order,
        branches
    )
else:
    from features import (
        authentication,
        dashboard,
        goods_receipts,
        inventory,
        order_history,
        manufacturer_orders,
        purchase_approvals,
        purchase_requisitions,
        products,
        order,
        branches
    )

app = FastAPI(title="Shoe Store API")


@app.exception_handler(authentication.AuthError)
async def handle_auth_error(request: Request, exc: authentication.AuthError):
    unauthenticated = exc.code == "UNAUTHENTICATED"
    return JSONResponse(
        status_code=401 if unauthenticated else 403,
        content={"error": {"code": exc.code, "message": "로그인이 필요합니다." if unauthenticated else "접근 권한이 없습니다."}},
        headers={"WWW-Authenticate": "Bearer"} if unauthenticated else None,
    )



@app.exception_handler(RequestValidationError)
async def handle_invalid_input(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=400,
        content={"error": {"code": "INVALID_INPUT", "message": "입력값을 확인해주세요."}},
    )


@app.exception_handler(MySQLError)
async def handle_database_error(request: Request, exc: MySQLError):
    # 연결 정보나 SQL을 응답에 노출하지 않는다.
    logging.getLogger(__name__).error("MySQL 요청 처리 실패: %s", type(exc).__name__)
    return JSONResponse(
        status_code=500,
        content={"error": {"code": "INTERNAL_ERROR", "message": "데이터 조회 중 오류가 발생했습니다."}},
    )

@app.exception_handler(HTTPException)
async def handle_business_error(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.detail},
        headers=exc.headers,
    )


# 기능별 파일에서 정의한 API를 공통 경로에 등록한다.
for feature in (
    authentication,
    inventory,
    purchase_requisitions,
    purchase_approvals,
    manufacturer_orders,
    goods_receipts,
    dashboard,
    products,
    order,
    branches,
    order_history,
):
    app.include_router(feature.router, prefix="/api/v1")

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8000)
