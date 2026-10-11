"""고객 앱에서 사용하는 상품과 상품 옵션 조회 API."""

from fastapi import APIRouter, Depends, HTTPException, Path
from pydantic import BaseModel
from pymysql.cursors import DictCursor
from pymysql.connections import Connection

if __package__ == "backend.features":
    from ..dependencies import get_db
else:
    from dependencies import get_db


router = APIRouter(prefix="/products", tags=["상품"])


# 응답 데이터 구조
class ProductResponse(BaseModel):
    product_id: int
    product_name: str
    price: int
    image_url: str | None
    category_id: int | None
    category_name: str | None
    product_description: str | None = None


class ProductListResponse(BaseModel):
    data: list[ProductResponse]


class ProductOptionResponse(BaseModel):
    product_variant_id: int
    color_code: str
    color_name: str
    size_mm: int
    additional_price: int
    available_quantity: int


class ProductOptionListResponse(BaseModel):
    data: list[ProductOptionResponse]


@router.get("", response_model=ProductListResponse)
def get_products(
    db: Connection = Depends(get_db),
) -> ProductListResponse:
    """판매 중인 상품과 연결된 카테고리를 조회한다."""

    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            """
            SELECT
                p.product_id,
                p.product_name,
                p.product_description,
                p.price,
                c.category_id,
                c.category_name,
                (
                    SELECT pi.image_url
                    FROM product_images AS pi
                    WHERE pi.product_id = p.product_id
                    ORDER BY pi.is_primary DESC,
                             pi.sort_order,
                             pi.product_image_id
                    LIMIT 1
                ) AS image_url
            FROM products AS p
            LEFT JOIN categories AS c
                ON c.category_id = p.category_id
            WHERE p.is_active = TRUE
            ORDER BY p.product_id
            """
        )
        rows = cursor.fetchall()

    return ProductListResponse(
        data=[ProductResponse(**row) for row in rows]
    )


@router.get(
    "/{product_id}/options",
    response_model=ProductOptionListResponse,
)
def get_product_options(
    product_id: int = Path(gt=0),
    db: Connection = Depends(get_db),
) -> ProductOptionListResponse:
    """선택한 상품의 색상·사이즈·구매 가능 수량을 조회한다."""

    with db.cursor(DictCursor) as cursor:
        # 존재하지 않거나 판매 중지된 상품은 구분해서 알린다.
        cursor.execute(
            """
            SELECT product_id
            FROM products
            WHERE product_id = %s
              AND is_active = TRUE
            """,
            (product_id,),
        )

        if cursor.fetchone() is None:
            raise HTTPException(
                status_code=404,
                detail={
                    "code": "NOT_FOUND",
                    "message": "상품을 찾을 수 없습니다.",
                },
            )

        cursor.execute(
            """
            SELECT
                v.product_variant_id,
                v.color_code,
                v.color_name,
                v.size_mm,
                v.additional_price,
                COALESCE(i.available_quantity, 0)
                    AS available_quantity
            FROM product_variants AS v
            LEFT JOIN headquarters_inventory AS i
                ON i.product_variant_id = v.product_variant_id
            WHERE v.product_id = %s
              AND v.is_active = TRUE
            ORDER BY v.color_name, v.size_mm
            """,
            (product_id,),
        )
        rows = cursor.fetchall()

    return ProductOptionListResponse(
        data=[ProductOptionResponse(**row) for row in rows]
    )