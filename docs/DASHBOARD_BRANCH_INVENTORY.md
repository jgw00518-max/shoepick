# 대리점 대시보드 보관 수량

- GET /api/v1/dashboard/branches/{branch_id}/inventory
- Firebase 직원 인증과 DB의 활성 소속 대리점 검증을 적용합니다. 소속 외 지점은 403, 없는·비활성 지점은 404입니다.
- 기존 branches, pickup_holdings를 사용하며 DB 구조는 변경하지 않습니다.
- INSPECTING, READY_FOR_PICKUP, RECALLING, DAMAGED 상태의 quantity를 합산합니다. AWAITING_ARRIVAL, PICKED_UP, RETURNED_TO_HQ, CANCELED는 제외합니다.
- held_quantity는 켤레 수이고 holding_count는 보관 기록 건수입니다. 페이지 제한 없이 전체 지점을 집계하며 보관 기록이 없으면 0입니다.
- Flutter 실제 로그인 대리점 사원·점장 대시보드의 현재 보관 수량 카드에 선택한 지점의 held_quantity를 표시합니다. 지점 변경·새로고침 시 다시 조회하고 실패·미선택 시 목업 수량이나 이전 수량으로 대체하지 않습니다.
- 실제 로그인에서 아직 연결하지 않은 입고 확인 대기·고객 수령 대기·반품 요청 카드는 API 연결 예정으로 표시합니다. Firebase 없는 미리보기는 기존 목업 대시보드를 유지합니다.
- 기존 재고 목록 API의 인증 적용 여부는 변경하지 않습니다. 새 대시보드 API에만 인증·소속 검증을 적용합니다.
