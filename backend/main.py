from fastapi import FastAPI

if __package__:
    from .features import (
        dashboard,
        goods_receipts,
        inventory,
        manufacturer_orders,
        purchase_approvals,
        purchase_requisitions,
        products,
        order,
        branches
    )
else:
    from features import (
        dashboard,
        goods_receipts,
        inventory,
        manufacturer_orders,
        purchase_approvals,
        purchase_requisitions,
        products,
        order,
        branches
    )

app = FastAPI(title="Shoe Store API")

# 기능별 파일에서 정의한 API를 공통 경로에 등록한다.
for feature in (
    inventory,
    purchase_requisitions,
    purchase_approvals,
    manufacturer_orders,
    goods_receipts,
    dashboard,
    products,
    order,
    branches
):
    app.include_router(feature.router, prefix="/api/v1")

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8000)
