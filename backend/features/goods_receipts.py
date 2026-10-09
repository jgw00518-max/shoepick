"""제조사 납품 입고 등록과 본사 재고 반영.

담당 C의 고객 주문 상품 대리점 입고와 구분한다.
입고 문서·품목 테이블은 기존 DB 확인 및 팀 합의 후 추가한다.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/goods-receipts", tags=["제조사 입고"])

# 1. 요청·응답 모델: 발주 품목·실제 입고 수량·요청 식별자를 정의한다.
# 2. 업무 함수: 발주 잔량·권한·중복 입고를 검증한다.
#    입고 문서·재고 증가·이력·발주 상태를 같은 트랜잭션으로 저장한다.
# 3. API 함수: 입고 등록·목록·상세 요청을 연결한다.
#    예: POST /api/v1/goods-receipts
#        GET /api/v1/goods-receipts
