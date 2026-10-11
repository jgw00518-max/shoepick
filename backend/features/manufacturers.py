"""본사 사원의 제조사 관리 API."""
from fastapi import APIRouter, Depends, HTTPException, Path
from pydantic import BaseModel, Field, field_validator
from pymysql import IntegrityError
from pymysql.connections import Connection
from pymysql.cursors import DictCursor

if __package__ == "backend.features":
    from ..dependencies import get_db
    from .authentication import AuthError, current_employee
else:
    from dependencies import get_db
    from features.authentication import AuthError, current_employee


router = APIRouter(
    prefix="/staff/manufacturers",
    tags=["A 제조사 관리"],
)


def current_product_manager(
    employee: dict = Depends(current_employee),
) -> dict:
    """현재 정한 기준에 따라 본사 사원만 허용한다."""
    role_codes = {
        role["role_code"]
        for role in employee["roles"]
    }

    if "HQ_STAFF" not in role_codes:
        raise AuthError("FORBIDDEN")

    return employee


class ManufacturerResponse(BaseModel):
    manufacturer_id: int
    manufacturer_name: str
    contact_name: str | None
    phone: str | None
    email: str | None


class ManufacturerListResponse(BaseModel):
    data: list[ManufacturerResponse]


@router.get("", response_model=ManufacturerListResponse)
def get_manufacturers(
    employee: dict = Depends(current_product_manager),
    db: Connection = Depends(get_db),
) -> ManufacturerListResponse:
    """실제 DB에 등록된 제조사 목록을 조회한다."""
    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            """
            SELECT
                manufacturer_id,
                manufacturer_name,
                contact_name,
                phone,
                email
            FROM manufacturers
            ORDER BY manufacturer_name, manufacturer_id
            """
        )
        rows = cursor.fetchall()

    return ManufacturerListResponse(
        data=[
            ManufacturerResponse(**row)
            for row in rows
        ]
    )

class ManufacturerSaveRequest(BaseModel):
    manufacturer_name: str = Field(min_length=1, max_length=100)
    contact_name: str | None = Field(default=None, max_length=100)
    phone: str | None = Field(default=None, max_length=20)
    email: str | None = Field(default=None, max_length=255)

    @field_validator(
        "manufacturer_name",
        "contact_name",
        "phone",
        "email",
        mode="before",
    )
    @classmethod
    def trim_text(cls, value):
        """앞뒤 공백을 제거한 뒤 길이를 검사한다."""
        return value.strip() if isinstance(value, str) else value

    @field_validator("contact_name", "phone", "email")
    @classmethod
    def empty_to_none(cls, value):
        """선택 항목의 빈 문자열은 NULL로 저장한다."""
        return value or None


class ManufacturerDetailResponse(BaseModel):
    data: ManufacturerResponse


def read_manufacturer(db: Connection, manufacturer_id: int) -> dict:
    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            """
            SELECT
                manufacturer_id,
                manufacturer_name,
                contact_name,
                phone,
                email
            FROM manufacturers
            WHERE manufacturer_id = %s
            """,
            (manufacturer_id,),
        )
        row = cursor.fetchone()

    if row is None:
        raise HTTPException(
            status_code=404,
            detail={
                "code": "NOT_FOUND",
                "message": "제조사를 찾을 수 없습니다.",
            },
        )

    return row


def raise_manufacturer_duplicate(error: IntegrityError):
    if error.args[0] == 1062:
        raise HTTPException(
            status_code=409,
            detail={
                "code": "DUPLICATE_MANUFACTURER",
                "message": "이미 등록된 제조사 이름입니다.",
            },
        ) from None

    raise error


@router.post(
    "",
    response_model=ManufacturerDetailResponse,
    status_code=201,
)
def create_manufacturer(
    request: ManufacturerSaveRequest,
    employee: dict = Depends(current_product_manager),
    db: Connection = Depends(get_db),
) -> ManufacturerDetailResponse:
    """본사 사원이 제조사를 등록한다."""
    try:
        with db.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO manufacturers (
                    manufacturer_name,
                    contact_name,
                    phone,
                    email
                )
                VALUES (%s, %s, %s, %s)
                """,
                (
                    request.manufacturer_name,
                    request.contact_name,
                    request.phone,
                    request.email,
                ),
            )
            manufacturer_id = cursor.lastrowid

        result = ManufacturerResponse(
            **read_manufacturer(db, manufacturer_id)
        )
        db.commit()

    except IntegrityError as error:
        db.rollback()
        raise_manufacturer_duplicate(error)
    except Exception:
        db.rollback()
        raise

    return ManufacturerDetailResponse(data=result)


@router.put(
    "/{manufacturer_id}",
    response_model=ManufacturerDetailResponse,
)
def update_manufacturer(
    request: ManufacturerSaveRequest,
    manufacturer_id: int = Path(gt=0),
    employee: dict = Depends(current_product_manager),
    db: Connection = Depends(get_db),
) -> ManufacturerDetailResponse:
    """본사 사원이 제조사 정보를 수정한다."""
    try:
        with db.cursor() as cursor:
            cursor.execute(
                """
                SELECT manufacturer_id
                FROM manufacturers
                WHERE manufacturer_id = %s
                FOR UPDATE
                """,
                (manufacturer_id,),
            )

            if cursor.fetchone() is None:
                raise HTTPException(
                    status_code=404,
                    detail={
                        "code": "NOT_FOUND",
                        "message": "제조사를 찾을 수 없습니다.",
                    },
                )

            cursor.execute(
                """
                UPDATE manufacturers
                SET manufacturer_name = %s,
                    contact_name = %s,
                    phone = %s,
                    email = %s
                WHERE manufacturer_id = %s
                """,
                (
                    request.manufacturer_name,
                    request.contact_name,
                    request.phone,
                    request.email,
                    manufacturer_id,
                ),
            )

        result = ManufacturerResponse(
            **read_manufacturer(db, manufacturer_id)
        )
        db.commit()

    except IntegrityError as error:
        db.rollback()
        raise_manufacturer_duplicate(error)
    except Exception:
        db.rollback()
        raise

    return ManufacturerDetailResponse(data=result)