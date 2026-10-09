"""구매 품의의 팀장·이사 결재와 승인·반려 이력.

기존 테이블: purchase_approvals, approval_workflows,
approval_workflow_steps, purchase_requisitions.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/purchase-approvals", tags=["구매 결재"])

# 1. 요청·응답 모델: 결재 의견·반려 사유와 결재 결과를 정의한다.
# 2. 업무 함수: 결재자 권한·순서·현재 상태·중복 처리를 확인한다.
#    최종 승인 후 제조사 발주 생성 함수를 같은 DB 연결로 호출한다.
# 3. API 함수: 결재 대기 목록·승인·반려 요청을 연결한다.
#    예: GET /api/v1/purchase-approvals/pending
#        POST /api/v1/purchase-approvals/{purchase_approval_id}/approve
#        POST /api/v1/purchase-approvals/{purchase_approval_id}/reject
