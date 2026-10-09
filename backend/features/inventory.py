"""본사·대리점 재고 조회, 주문 재고 예약·해제, 이동 이력.

기존 테이블: headquarters_inventory, inventory_policies,
inventory_reservations, inventory_movements, pickup_holdings.
대리점의 고객 수령 대기 물품과 일반 판매 재고는 구분한다.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/inventory", tags=["재고"])

# 1. 요청·응답 모델: Pydantic 모델을 이 위치에 작성한다.
# 2. 업무 함수: 조회·예약·해제·출고·입고·재고 이력 처리를 작성한다.
#    다른 기능에서도 호출하므로 내부 함수는 독립적으로 commit하지 않는다.
# 3. API 함수: 위 업무 함수를 호출하고 공통 응답 형식으로 반환한다.
#    예: GET /api/v1/inventory, GET /api/v1/inventory/movements
