"""구매 품의 작성·조회·수정·상신.

기존 테이블: purchase_requisitions, purchase_requisition_items.
직원 ID는 요청 본문 대신 검증된 로그인 정보에서 가져온다.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/purchase-requisitions", tags=["구매 품의"])

# 1. 요청·응답 모델: 품의 제목·사유·상품 옵션·수량을 정의한다.
# 2. 업무 함수: 작성자·수량·현재 상태를 검증하고 품의·품목을 저장한다.
# 3. API 함수: 목록·상세·작성·초안 수정·상신 요청을 연결한다.
#    예: POST /api/v1/purchase-requisitions
#        POST /api/v1/purchase-requisitions/{purchase_requisition_id}/submit
