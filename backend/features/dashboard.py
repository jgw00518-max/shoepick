"""재고·품의·결재·발주·입고 운영 현황 집계."""

from fastapi import APIRouter

router = APIRouter(prefix="/dashboard", tags=["운영 현황"])

# 1. 요청·응답 모델: 기간·지점별 필터와 현황 응답을 정의한다.
# 2. 업무 함수: 권한 범위 내 재고·결재 대기·미입고 발주 등을 집계한다.
# 3. API 함수: 현황 조회를 연결한다. 업무 데이터를 직접 변경하지 않는다.
#    예: GET /api/v1/dashboard/summary
