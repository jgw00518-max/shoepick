# 제조사 발주 목록·상세 조회

DB 구조 변경 없이 기존 audit_logs의 PROCUREMENT_ORDER_PLACED / PURCHASE_REQUISITION 기록을 조회합니다.

- GET /api/v1/manufacturer-orders: 목록. page(기본 1), page_size(기본 20, 최대 100), order(desc/asc), keyword(최대 150자)를 받습니다.
- GET /api/v1/manufacturer-orders/{audit_log_id}: 목록에서 반환한 audit_log_id로 상세 조회합니다. 발주번호나 품의 ID와 구분합니다.
- Firebase Bearer 인증이 필요하며 활성 직원의 DB 직책으로 범위를 결정합니다. HQ_STAFF는 본인이 작성한 품의의 발주만, TEAM_LEAD / DIRECTOR / EXECUTIVE / ADMIN은 전체를 조회합니다. 대리점 직책만 있는 직원은 403입니다. 여러 직책 보유 시 상위 조회 범위를 적용하므로 테스트 계정도 기존 직책으로 전체를 조회합니다.
- 상세에도 같은 범위를 적용합니다. 다른 직원의 발주 또는 없는 기록은 404입니다. 요청으로 role이나 직원 ID를 보내도 조회 권한을 부여하지 않습니다.
- 제목·제조사·발주번호를 검색하고, 등록일과 감사 로그 ID로 최신순·오래된순 정렬을 적용합니다. SQL에는 검색값을 바인딩하고 LIKE 특수문자를 이스케이프합니다.
- 발주 당시 JSON 스냅샷의 제조사·제목·사유·제품·옵션·수량을 표시합니다. 품의 현재 상태와 작성자·등록자 이름은 기존 테이블에서 조회합니다. 취소된 품의라도 발주 기록은 조회 대상으로 유지합니다.
- 전달 상태는 현재 NOT_SENT(외부 전송 전)입니다. 접수 결과는 아래 API로 별도 기록하며 접수 확인 시 전체 자동 입고합니다. 실제 외부 전송은 후속 기능입니다. 조회 API는 쓰기나 재고 변경을 수행하지 않습니다.

직원 앱 일반 로그인 → 본사 역할 → 제조사 발주 메뉴에서 검색·정렬·페이지 이동·새로고침·상세 보기를 사용할 수 있습니다. 대리점에는 메뉴를 표시하지 않습니다. 미리보기에서는 실제 발주 조회를 연결하지 않고 로그인 안내를 표시합니다.

Swagger에서는 직원 토큰으로 Authorize 후 목록을 조회하고 반환된 audit_log_id를 상세 API에 입력합니다. 이사 최종 승인 이전에 만들어진 기존 APPROVED 품의는 발주 로그가 없으면 목록에 나타나지 않습니다.

## 제조사 접수 확인·거절

POST /api/v1/manufacturer-orders/{audit_log_id}/reception

요청 예시:
```json
{"decision":"ACCEPTED","confirmation_method":"PHONE","comment":"담당자와 통화 후 접수 확인","request_id":"unique_request_1234567890"}
```

- decision: ACCEPTED(접수 확인), REJECTED(접수 거절).
- confirmation_method: PHONE / EMAIL / OTHER. 실제 제조사 답변을 직원이 확인한 방법입니다.
- comment: 최대 2,000자. 접수 거절 시 공백 제외 필수입니다.
- request_id: 영문·숫자·밑줄·하이픈 16~100자. 동일 요청을 재시도할 때 유지합니다.
- 본사 사원은 본인 발주, 팀장·이사·ADMIN은 전체 발주를 기록합니다. 임원 단독 직책은 조회 전용이며 여러 직책이 있으면 기록 가능한 직책을 적용합니다.
- 서버가 처리 직원·시간을 기록합니다. 클라이언트가 처리 직원 ID를 지정할 수 없습니다.
- ORDERED 품의만 처리하며 부모 품의를 잠근 후 최신 접수 기록을 확인합니다. 최초 접수 결과를 확정한 뒤 다른 결과·다른 요청 ID로 덮어쓰면 409입니다. 동일 직원·요청 ID·내용의 재시도는 기존 결과를 반환합니다.
- audit_logs에 action_code=PROCUREMENT_ORDER_RECEPTION, entity_type=PURCHASE_REQUISITION, entity_id=품의 ID로 추가 저장합니다. 발주 원본 스냅샷은 변경하지 않습니다.
- 목록·상세에 reception_status(PENDING/ACCEPTED/REJECTED), reception(방법·사유·직원·시간), can_record_reception을 반환합니다.
- 앱의 제조사 발주 → 상세 보기에서 접수 확인·접수 거절을 선택합니다. 성공 시 목록을 갱신하고 이미 처리된 건은 버튼을 숨깁니다.
- 품의 ORDERED 상태는 유지합니다. ACCEPTED는 접수 확인과 동시에 발주 당시 수량 전부가 도착한 것으로 간주하여 본사 실물 재고를 증가시킵니다. REJECTED는 재고를 변경하지 않습니다. 실제 제조사에 메시지를 전송하지 않습니다.

## 접수 확인 시 전체 자동 입고 (FastAPI)

- 기존 POST reception 요청 본문을 유지합니다. 서버가 저장된 발주 스냅샷의 품목·수량을 사용하며 클라이언트는 입고 수량을 지정하지 않습니다.
- goods_receipts.py의 receive_full_order를 같은 DB 연결로 호출하고 접수 기록·입고 감사 로그·재고 증가·재고 이동 이력을 함께 commit합니다. 실패 시 전체 rollback합니다.
- audit_logs에 PROCUREMENT_GOODS_RECEIVED / PURCHASE_REQUISITION으로 입고 기록을 저장합니다.
- headquarters_inventory의 on_hand_quantity만 증가하며 reserved_quantity, defective_quantity는 유지합니다. 재고 행이 없으면 생성합니다. available_quantity는 기존 생성 컬럼으로 계산됩니다.
- inventory_movements에 PROCUREMENT_RECEIPT, 품의 참조, 품목별 증가량과 처리 후 재고, 직원 ID를 기록합니다. idempotency_key는 procurement-receipt:{발주 감사 로그 ID}:{옵션 ID}입니다.
- 부모 품의를 잠그고 옵션 ID 순으로 재고를 잠급니다. 기존 입고 로그·이동 이력, 잘못된 품목·수량, 재고 저장 범위 초과를 차단합니다.
- 응답 data.goods_receipt에 입고 로그 ID, 입고일, 총입고량, 품목별 수량과 처리 후 실물 재고를 반환합니다. 거절은 null입니다. 동일 접수 요청 재시도에서는 기존 입고 기록만 반환하고 재고를 다시 증가시키지 않습니다.
- 과거 버전에서 접수 확인만 저장한 건은 재시도해도 소급 입고하지 않습니다. 별도 일괄 데이터 보정은 수행하지 않습니다.
- 테이블·컬럼 구조 변경은 없습니다. 부분 입고·추가 입고 API는 이번 범위에 포함하지 않습니다.

## 직원 앱 자동 입고 UI

- 제조사 발주 상세의 버튼을 접수 확인 및 전체 입고로 표시합니다.
- 확인 창에 발주 총수량과 본사 재고 자동 반영 안내를 표시하고 전체 입고 확정으로 저장합니다.
- API 응답의 goods_receipt를 받아 실제 입고 수량을 완료 메시지에 표시합니다. 실패 시 입력 내용과 요청 식별자를 유지해 같은 요청으로 재시도합니다.
- 목록·상세 조회 응답에 기존 입고 감사 로그로 구성한 goods_receipt를 포함합니다. 다시 화면을 열어도 입고량·입고일·품목별 처리 후 실물 재고를 조회합니다.
- 처리 후 실물 재고는 입고 당시 기록이며 현재 재고와 구분합니다. 현재 재고는 본사 재고 메뉴에서 조회합니다.
- 입고 로그가 없는 과거 접수 확인은 입고 기록 없음으로 표시합니다. 접수 거절은 재고를 변경하지 않습니다.
