"""고객이 수령 대리점을 선택할 때 사용하는 조회 API."""

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from pymysql.connections import Connection
from pymysql.cursors import DictCursor

if __package__ == "backend.features":
    from ..dependencies import get_db
else:
    from dependencies import get_db


router = APIRouter(prefix="/branches", tags=["수령 대리점"])


class PickupBranch(BaseModel):
    branch_id: int
    branch_name: str
    district_code: str
    address: str
    phone: str


class PickupBranchListResponse(BaseModel):
    data: list[PickupBranch]


@router.get("/pickup", response_model=PickupBranchListResponse)
def get_pickup_branches(
    db: Connection = Depends(get_db),
) -> PickupBranchListResponse:
    """현재 사용 가능한 수령 대리점 목록을 조회한다."""

    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            """
            SELECT
                branch_id,
                branch_name,
                district_code,
                address,
                phone
            FROM branches
            WHERE is_active = TRUE
            ORDER BY district_code, branch_name, branch_id
            """
        )
        rows = cursor.fetchall()

    return PickupBranchListResponse(
        data=[PickupBranch(**row) for row in rows]
    )