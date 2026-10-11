# 임원 판매 지표

- GET /api/v1/dashboard/executive/sales
- 활성 DB 직책 EXECUTIVE / ADMIN만 조회합니다. 기존 직원 계정 권한을 사용하며 DB 구조를 변경하지 않습니다.
- 한국 시간 기준 오늘을 포함한 28개 날짜의 첫날 00:00부터 조회 시각까지 집계합니다. 결제 완료 시간(paid_at)이 기준이며 DB DATETIME은 기존 프로젝트의 한국 시간 기준입니다.
- PAID / PREPARING / SHIPPING / READY_FOR_PICKUP / COMPLETED 주문 중 PAID 또는 PARTIALLY_REFUNDED 결제 기록이 있는 주문을 집계합니다. 미결제·취소·전액 환불 주문은 제외합니다.
- 주문별 결제 기록을 먼저 그룹화하고 최초 유효 결제 시간을 사용합니다. 주문 품목도 주문별로 먼저 합산하여 여러 결제 시도나 여러 품목으로 인한 중복 집계를 방지합니다.
- sales_quantity: 해당 주문의 order_items.quantity 합계(켤레).
- revenue_amount: 해당 주문의 orders.paid_total 합계(원). 쿠폰·적립금 사용 이후 주문 결제액이며 부분 환불 금액은 차감하지 않습니다. 순매출 지표와 구분합니다.
- order_count: 해당 결제 완료 주문 수. 결제 시도 횟수와 구분합니다.
- period_start, period_end, timezone도 반환합니다. 데이터가 없으면 세 지표는 모두 0입니다.
- 실제 로그인 임원 대시보드의 최근 28일 판매량·매출·주문 카드에 연결합니다. 매출 카드에 부분 환불 차감 전 기준을 명시합니다.
- 판매 집계 조회 실패 시 판매 지표만 —와 오류 안내로 표시하고 조회된 재고 부족 지표는 유지합니다. 새로고침으로 재시도합니다. 미리보기는 기존 목업을 유지합니다.
