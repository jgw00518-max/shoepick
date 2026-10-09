"""제조사 발주 생성·조회와 발주 전송 상태 관리.

제조사 기본 정보는 담당 A의 manufacturers 테이블을 참조한다.
발주 문서·품목 테이블은 기존 DB 확인 및 팀 합의 후 추가한다.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/manufacturer-orders", tags=["제조사 발주"])

# 1. 요청·응답 모델: 근거 품의·제조사·발주 품목·수량을 정의한다.
# 2. 업무 함수: 최종 승인 여부·누적 발주량·중복 생성을 확인한다.
#    외부 전송 실패는 같은 발주번호로 재시도하고 새 발주를 만들지 않는다.
# 3. API 함수: 발주 목록·상세·전송 요청을 연결한다.
#    예: GET /api/v1/manufacturer-orders
#        GET /api/v1/manufacturer-orders/{manufacturer_order_id}
