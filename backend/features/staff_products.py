"""본사 사원의 상품 관리 API."""

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator
from pymysql import IntegrityError
from pymysql.connections import Connection
from pymysql.cursors import DictCursor

from fastapi import APIRouter, Depends, HTTPException, Path

if __package__ == "backend.features":
    from ..dependencies import get_db
    from .manufacturers import current_product_manager
else:
    from dependencies import get_db
    from features.manufacturers import current_product_manager


router = APIRouter(
    prefix="/staff/products",
    tags=["A 상품 관리"],
)


class StaffProductResponse(BaseModel):
    product_id: int
    product_name: str
    model_code: str

    brand_id: int
    brand_name: str

    category_id: int
    category_name: str

    manufacturer_id: int | None
    manufacturer_name: str | None

    gender_code: str
    product_description: str | None
    price: int
    is_active: bool


class StaffProductListResponse(BaseModel):
    data: list[StaffProductResponse]


@router.get("", response_model=StaffProductListResponse)
def get_staff_products(
    employee: dict = Depends(current_product_manager),
    db: Connection = Depends(get_db),
) -> StaffProductListResponse:
    """판매 중지 상품을 포함한 전체 상품을 조회한다."""
    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            """
            SELECT
                p.product_id,
                p.product_name,
                p.model_code,
                p.brand_id,
                b.brand_name,
                p.category_id,
                c.category_name,
                p.manufacturer_id,
                m.manufacturer_name,
                p.gender_code,
                p.product_description,
                p.price,
                p.is_active
            FROM products AS p
            JOIN brands AS b
                ON b.brand_id = p.brand_id
            JOIN categories AS c
                ON c.category_id = p.category_id
            LEFT JOIN manufacturers AS m
                ON m.manufacturer_id = p.manufacturer_id
            ORDER BY p.product_id DESC
            """
        )
        rows = cursor.fetchall()

    return StaffProductListResponse(
        data=[
            StaffProductResponse(**row)
            for row in rows
        ]
    )

class BrandChoice(BaseModel):
    brand_id: int
    brand_name: str


class CategoryChoice(BaseModel):
    category_id: int
    category_name: str


class ProductFormOptions(BaseModel):
    brands: list[BrandChoice]
    categories: list[CategoryChoice]


class ProductFormOptionsResponse(BaseModel):
    data: ProductFormOptions


@router.get(
    "/form-options",
    response_model=ProductFormOptionsResponse,
)
def get_product_form_options(
    employee: dict = Depends(current_product_manager),
    db: Connection = Depends(get_db),
) -> ProductFormOptionsResponse:
    """상품 등록 화면에서 선택할 브랜드와 카테고리를 조회한다."""
    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            """
            SELECT brand_id, brand_name
            FROM brands
            ORDER BY brand_name, brand_id
            """
        )
        brands = cursor.fetchall()

        cursor.execute(
            """
            SELECT category_id, category_name
            FROM categories
            ORDER BY category_name, category_id
            """
        )
        categories = cursor.fetchall()

    return ProductFormOptionsResponse(
        data=ProductFormOptions(
            brands=[BrandChoice(**row) for row in brands],
            categories=[CategoryChoice(**row) for row in categories],
        )
    )

class StaffProductCreateRequest(BaseModel):
    product_name: str = Field(min_length=1, max_length=150)
    model_code: str = Field(min_length=1, max_length=40)
    brand_id: int = Field(gt=0)
    category_id: int = Field(gt=0)
    manufacturer_id: int | None = Field(default=None, gt=0)
    gender_code: Literal["M", "W", "U", "K"]
    product_description: str | None = None
    price: int = Field(ge=0)
    is_active: bool = True

    @field_validator(
        "product_name",
        "model_code",
        "product_description",
        mode="before",
    )
    @classmethod
    def trim_text(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator("product_description")
    @classmethod
    def empty_to_none(cls, value):
        return value or None


class StaffProductCreated(BaseModel):
    product_id: int


class StaffProductCreateResponse(BaseModel):
    data: StaffProductCreated


@router.post(
    "",
    response_model=StaffProductCreateResponse,
    status_code=201,
)
def create_staff_product(
    request: StaffProductCreateRequest,
    employee: dict = Depends(current_product_manager),
    db: Connection = Depends(get_db),
) -> StaffProductCreateResponse:
    """본사 사원이 상품을 등록한다. 옵션과 재고는 별도로 처리한다."""
    try:
        with db.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO products (
                    product_name,
                    model_code,
                    brand_id,
                    category_id,
                    manufacturer_id,
                    gender_code,
                    product_description,
                    price,
                    is_active
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    request.product_name,
                    request.model_code,
                    request.brand_id,
                    request.category_id,
                    request.manufacturer_id,
                    request.gender_code,
                    request.product_description,
                    request.price,
                    request.is_active,
                ),
            )
            product_id = cursor.lastrowid

        db.commit()

    except IntegrityError as error:
        db.rollback()

        if error.args[0] == 1062:
            raise HTTPException(
                status_code=409,
                detail={
                    "code": "DUPLICATE_PRODUCT",
                    "message": "이미 등록된 모델 코드입니다.",
                },
            ) from None

        if error.args[0] == 1452:
            raise HTTPException(
                status_code=400,
                detail={
                    "code": "INVALID_REFERENCE",
                    "message": "브랜드·카테고리·제조사 정보를 확인해주세요.",
                },
            ) from None

        raise

    except Exception:
        db.rollback()
        raise

    return StaffProductCreateResponse(
        data=StaffProductCreated(product_id=product_id)
    )

@router.put(
    "/{product_id}",
    response_model=StaffProductCreateResponse,
)
def update_staff_product(
    request: StaffProductCreateRequest,
    product_id: int = Path(gt=0),
    employee: dict = Depends(current_product_manager),
    db: Connection = Depends(get_db),
) -> StaffProductCreateResponse:
    """본사 사원이 상품 정보와 가격·판매 상태를 수정한다."""
    try:
        with db.cursor() as cursor:
            cursor.execute(
                """
                SELECT product_id
                FROM products
                WHERE product_id = %s
                FOR UPDATE
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
                UPDATE products
                SET product_name = %s,
                    model_code = %s,
                    brand_id = %s,
                    category_id = %s,
                    manufacturer_id = %s,
                    gender_code = %s,
                    product_description = %s,
                    price = %s,
                    is_active = %s
                WHERE product_id = %s
                """,
                (
                    request.product_name,
                    request.model_code,
                    request.brand_id,
                    request.category_id,
                    request.manufacturer_id,
                    request.gender_code,
                    request.product_description,
                    request.price,
                    request.is_active,
                    product_id,
                ),
            )

        db.commit()

    except IntegrityError as error:
        db.rollback()

        if error.args[0] == 1062:
            raise HTTPException(
                status_code=409,
                detail={
                    "code": "DUPLICATE_PRODUCT",
                    "message": "이미 등록된 모델 코드입니다.",
                },
            ) from None

        if error.args[0] == 1452:
            raise HTTPException(
                status_code=400,
                detail={
                    "code": "INVALID_REFERENCE",
                    "message": "브랜드·카테고리·제조사 정보를 확인해주세요.",
                },
            ) from None

        raise

    except Exception:
        db.rollback()
        raise

    return StaffProductCreateResponse(
        data=StaffProductCreated(product_id=product_id)
    )

class StaffProductOptionResponse(BaseModel):
    product_variant_id: int
    product_id: int
    product_code: str
    color_code: str
    color_name: str
    size_mm: int
    additional_price: int
    is_active: bool


class StaffProductOptionListResponse(BaseModel):
    data: list[StaffProductOptionResponse]


@router.get(
    "/{product_id}/options",
    response_model=StaffProductOptionListResponse,
)
def get_staff_product_options(
    product_id: int = Path(gt=0),
    employee: dict = Depends(current_product_manager),
    db: Connection = Depends(get_db),
) -> StaffProductOptionListResponse:
    """판매 중지 여부와 관계없이 상품의 전체 옵션을 조회한다."""
    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            """
            SELECT product_id
            FROM products
            WHERE product_id = %s
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
                product_variant_id,
                product_id,
                product_code,
                color_code,
                color_name,
                size_mm,
                additional_price,
                is_active
            FROM product_variants
            WHERE product_id = %s
            ORDER BY color_name, size_mm, product_variant_id
            """,
            (product_id,),
        )
        rows = cursor.fetchall()

    return StaffProductOptionListResponse(
        data=[
            StaffProductOptionResponse(**row)
            for row in rows
        ]
    )

class StaffProductOptionCreateRequest(BaseModel):
    product_code: str = Field(min_length=1, max_length=64)
    color_code: str = Field(min_length=1, max_length=20)
    color_name: str = Field(min_length=1, max_length=50)
    size_mm: int = Field(gt=0, le=65535)
    additional_price: int = Field(
        default=0,
        ge=0,
        le=2147483647,
    )
    is_active: bool = True

    @field_validator(
        "product_code",
        "color_code",
        "color_name",
        mode="before",
    )
    @classmethod
    def trim_text(cls, value):
        return value.strip() if isinstance(value, str) else value


class StaffProductOptionDetailResponse(BaseModel):
    data: StaffProductOptionResponse


@router.post(
    "/{product_id}/options",
    response_model=StaffProductOptionDetailResponse,
    status_code=201,
)
def create_staff_product_option(
    request: StaffProductOptionCreateRequest,
    product_id: int = Path(gt=0),
    employee: dict = Depends(current_product_manager),
    db: Connection = Depends(get_db),
) -> StaffProductOptionDetailResponse:
    """상품 옵션을 등록한다. 재고 수량은 변경하지 않는다."""
    try:
        with db.cursor(DictCursor) as cursor:
            cursor.execute(
                """
                SELECT product_id
                FROM products
                WHERE product_id = %s
                FOR UPDATE
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
                INSERT INTO product_variants (
                    product_id,
                    product_code,
                    color_code,
                    color_name,
                    size_mm,
                    additional_price,
                    is_active
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    product_id,
                    request.product_code,
                    request.color_code,
                    request.color_name,
                    request.size_mm,
                    request.additional_price,
                    request.is_active,
                ),
            )
            product_variant_id = cursor.lastrowid

            cursor.execute(
                """
                SELECT
                    product_variant_id,
                    product_id,
                    product_code,
                    color_code,
                    color_name,
                    size_mm,
                    additional_price,
                    is_active
                FROM product_variants
                WHERE product_variant_id = %s
                """,
                (product_variant_id,),
            )
            result = StaffProductOptionResponse(
                **cursor.fetchone()
            )

        db.commit()

    except IntegrityError as error:
        db.rollback()

        if error.args[0] == 1062:
            raise HTTPException(
                status_code=409,
                detail={
                    "code": "DUPLICATE_OPTION",
                    "message": (
                        "이미 등록된 상품 코드이거나 "
                        "같은 상품의 색상·사이즈 조합입니다."
                    ),
                },
            ) from None

        raise

    except Exception:
        db.rollback()
        raise

    return StaffProductOptionDetailResponse(data=result)

@router.put(
    "/{product_id}/options/{product_variant_id}",
    response_model=StaffProductOptionDetailResponse,
)
def update_staff_product_option(
    request: StaffProductOptionCreateRequest,
    product_id: int = Path(gt=0),
    product_variant_id: int = Path(gt=0),
    employee: dict = Depends(current_product_manager),
    db: Connection = Depends(get_db),
) -> StaffProductOptionDetailResponse:
    """선택한 상품의 옵션 정보를 수정한다. 재고는 변경하지 않는다."""
    try:
        with db.cursor(DictCursor) as cursor:
            cursor.execute(
                """
                SELECT product_variant_id
                FROM product_variants
                WHERE product_id = %s
                  AND product_variant_id = %s
                FOR UPDATE
                """,
                (product_id, product_variant_id),
            )

            if cursor.fetchone() is None:
                raise HTTPException(
                    status_code=404,
                    detail={
                        "code": "NOT_FOUND",
                        "message": "해당 상품의 옵션을 찾을 수 없습니다.",
                    },
                )

            cursor.execute(
                """
                UPDATE product_variants
                SET product_code = %s,
                    color_code = %s,
                    color_name = %s,
                    size_mm = %s,
                    additional_price = %s,
                    is_active = %s
                WHERE product_id = %s
                  AND product_variant_id = %s
                """,
                (
                    request.product_code,
                    request.color_code,
                    request.color_name,
                    request.size_mm,
                    request.additional_price,
                    request.is_active,
                    product_id,
                    product_variant_id,
                ),
            )

            cursor.execute(
                """
                SELECT
                    product_variant_id,
                    product_id,
                    product_code,
                    color_code,
                    color_name,
                    size_mm,
                    additional_price,
                    is_active
                FROM product_variants
                WHERE product_id = %s
                  AND product_variant_id = %s
                """,
                (product_id, product_variant_id),
            )
            result = StaffProductOptionResponse(
                **cursor.fetchone()
            )

        db.commit()

    except IntegrityError as error:
        db.rollback()

        if error.args[0] == 1062:
            raise HTTPException(
                status_code=409,
                detail={
                    "code": "DUPLICATE_OPTION",
                    "message": (
                        "이미 등록된 상품 코드이거나 "
                        "같은 상품의 색상·사이즈 조합입니다."
                    ),
                },
            ) from None

        raise

    except Exception:
        db.rollback()
        raise

    return StaffProductOptionDetailResponse(data=result)