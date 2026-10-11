# C 고객 문의 조회

기준: database/shupick_v2_structure.sql의 inquiries, inquiry_responses. 실제 DB와 일치하는지는 실행 환경에서 별도 확인한다.

- GET /api/v1/order-history/inquiries/customer?page=1&page_size=20
- GET /api/v1/order-history/inquiries/customer/{inquiry_id}
- B current_customer → C authenticated_customer → 검증된 customer_id 조건으로 SELECT만 수행한다. 요청 customer_id는 권한 근거로 사용하지 않는다.
- 목록은 created_at DESC, inquiry_id DESC; 답변은 responded_at ASC, inquiry_response_id ASC 순서다. 다른 고객 또는 없는 문의는 동일한 404 / NOT_FOUND를 반환한다.
- data와 pagination을 사용하며 상세 data.responses에 기존 답변 목록을 반환한다. 직원 ID·직급 등은 공개하지 않는다.
- OPEN / ANSWERED / CLOSED만 표시를 해석하고 미지 상태는 원문과 확인 필요 안내를 표시한다. 유형과 날짜 문자열은 변환하지 않는다.
- 기존 FAQ·작성 목업은 유지하되 작성 폼에 서버 저장되지 않는다고 표시한다. 작성한 목업 문의는 실제 서버 목록에 섞지 않는다.
- 추가 쓰기 API, 문의 유형 정책, 직원 답변 권한, DB 변경은 포함하지 않는다.
- 자동 테스트는 가짜 DB와 테스트 전용 인증 의존성 대체를 사용한다. 실제 DB/Firebase/기기 통합은 미검증이다.

## 문의 작성 연결 — 2026-10-11

- 사용자 승인 유형: PRODUCT / DELIVERY / PAYMENT / OTHER.
- POST /api/v1/order-history/inquiries/customer: inquiry_type, title(1~150자), inquiry_content(공백 제외 필수), product_id(null 또는 기존 상품 ID), request_id(재전송 시 동일).
- 고객은 토큰으로 식별한다. OPEN과 created_at은 DB 기본값을 사용한다. 새 문의는 201, 동일 요청·동일 내용 재전송은 기존 inquiry_id와 200, 같은 ID의 다른 내용은 409 / ALREADY_PROCESSED.
- 고객 행 잠금 뒤 기존 audit_logs의 고객·업무·요청 ID를 확인한다. 문의와 INQUIRY_CREATE 감사 기록을 한 번 commit하며 오류 시 rollback한다. 이 경로의 중복 방지는 모든 요청이 같은 고객 잠금 순서를 지키는 것을 전제로 한다.
- Flutter는 저장 중 버튼을 막고 성공 응답 후 입력을 지우고 목록을 다시 조회한다. 실패 시 내용과 요청 ID를 유지한다. 결과가 불명확한 실패 뒤에는 같은 내용으로 재시도하며 자동 재전송하지 않는다. 화면을 닫으면 요청 ID가 사라지므로 앱 재실행을 넘는 복구는 이번 범위에 포함하지 않는다.
- 알림은 구현하지 않았으며 접수 성공 문구에 알림 발송을 약속하지 않는다. 공통 AuthApi에는 POST와 201 처리만 최소 추가했다.
- 실제 DB 생성 테스트는 수행하지 않는다. 담당 간 공유가 필요한 새 감사 값은 INQUIRY_CREATE / INQUIRY이며 기존 varchar 컬럼을 사용하고 스키마는 변경하지 않는다.

## 직원 문의 조회·답변 — 사용자 승인

- HQ_STAFF 역할을 포함한 B 검증 직원만 전체 문의 조회·첫 답변 등록 가능. 다른 직급 단독은 403. 앱 직급 선택값과 branch_id는 권한 근거가 아니다.
- GET /api/v1/order-history/inquiries/staff: page, page_size, inquiry_status(OPEN/ANSWERED/CLOSED, 생략 전체). 생성 시각 내림차순·ID 내림차순.
- GET /api/v1/order-history/inquiries/staff/{inquiry_id}: 문의와 기존 답변 목록.
- POST /api/v1/order-history/inquiries/staff/{inquiry_id}/responses: response_content, request_id. OPEN이고 답변 기록이 없는 문의만 첫 답변을 등록한다. 직원 ID는 인증에서, 시각은 DB에서 가져온다. ANSWERED·CLOSED 추가 답변·수정은 제공하지 않는다.
- 문의 행 FOR UPDATE 후 기존 INQUIRY_ANSWER 감사 기록으로 동일 요청 재전송을 확인한다. 답변 생성·ANSWERED 변경·감사 로그는 같은 연결에서 한 번 commit한다. 실패 시 rollback한다. 새 답변 201, 같은 요청 재전송 200, 다른 내용의 같은 요청 409 ALREADY_PROCESSED, 이미 답변된 문의 409 INVALID_STATE_TRANSITION.
- 직원 메뉴의 고객 문의 항목만 추가하며 기존 고객 관리(B) 및 D 대시보드 업무는 수정하지 않는다. 공통 메뉴 enum의 표시·연결 분기만 추가한다.
- 화면은 로딩·오류·재시도·상태 필터·페이지와 답변 입력을 제공한다. 저장 중 중복 요청 차단, 성공 후 상세·목록 갱신, 종료 후 늦은 응답 무시. 앱 종료를 넘는 요청 ID 복구와 B 알림은 포함하지 않는다.
