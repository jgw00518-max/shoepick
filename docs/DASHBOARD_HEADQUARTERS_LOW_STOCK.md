# 본사 대시보드 재고 부족

- GET /api/v1/dashboard/headquarters/low-stock
- 활성 DB 직책 HQ_STAFF / TEAM_LEAD / DIRECTOR / EXECUTIVE / ADMIN이 조회합니다. 대리점 직책만 있으면 403, 미인증은 401입니다.
- headquarters_inventory, product_variants, products, inventory_policies를 사용합니다. DB 구조와 업무 데이터는 변경하지 않습니다.
- 본사 재고 행이 있는 활성 제품·옵션을 대상으로 합니다. 비활성 재고 정책은 집계 대상에서 제외합니다.
- 재고 정책이 있으면 initial_stock_quantity와 reorder_threshold_percent를 사용하고 없으면 100개·30%를 사용합니다.
- 가용 수량 * 100 < 초기 수량 * 기준 퍼센트인 옵션을 집계합니다. 기본 기준에서 29개는 부족, 30개는 부족 아님입니다. 가용 수량은 실물에서 예약·불량을 제외한 DB 생성 컬럼을 읽습니다.
- low_stock_variant_count는 부족한 제품 옵션 수, monitored_variant_count는 전체 집계 대상 옵션 수입니다. 수량 합계나 상품 종류 수와 구분하며 페이지 제한 없이 전체를 집계합니다.
- 본사 사원·팀장·이사·임원 대시보드의 가용 재고 부족 카드에 N종으로 표시합니다. 부족하면 실제 집계값을 사용한 업무 알림을 표시합니다.
- 새로고침·직책 변경 시 다시 조회하고, 실패 시 이전 값이나 목업 수량 대신 조회 오류와 —를 표시합니다.
- 실제 로그인에서 아직 연결하지 않은 본사 사원·팀장·이사 카드는 API 연결 예정으로 표시합니다. 임원 판매량·매출·주문 카드는 별도 판매 집계 API에 연결합니다. 미리보기의 기존 목업 화면은 유지합니다.
