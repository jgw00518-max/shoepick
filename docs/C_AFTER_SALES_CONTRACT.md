# C 구매 취소·반품·환불 계약 초안

작성 기준: 2026-10-11 로컬 코드와 database/shupick_v2_structure.sql. 현재 구현 사실·확정 정책·제안을 구분한다. 실제 DB 구조는 실행 연결 전 다시 확인한다. 실행 단계는 아래 최신 적용 내용을 따른다.

## 1. 확정 정책

### 모의 반품 완료 화면 자동 검증

`return_complete_mock_view_test.dart`에서 승인 반품 상세 → 확인 창 → complete-mock 요청 → 상세 환불 표시·완료 버튼 제거를 검증했다. 취소 시 요청 없음, 서버 실패 시 성공 표시 없음·오류 안내·재시도 버튼 유지도 확인했다. 테스트용 응답을 사용한 위젯 검사이며 실제 앱 로그인·서버 통신·직급별 실행 차단 검증은 아니다. 해당 범위의 추가 실행 코드 수정은 필요하지 않았다.

### 로컬 MySQL 반품 완료 SQL 검증

`SHOEPICK_LOCAL_DB_TEST=1`로 `test_c_return_local_transaction.py`를 실행했다. 로컬 주소만 허용하고 기존 계정·상품을 참조한 별도 수령 완료·승인 반품 fixture를 생성했다. 실제 C/D/A 함수가 정상 재고 1개 복원·MOCK 결제 REFUNDED·반품 COMPLETED·변동 이력 1건을 저장하는지 검사했다. 주문 COMPLETED와 구매 미확정은 유지한다. 마지막에 rollback하고 검증 주문 부재 및 재고 원상태를 확인한다. 자동 증가 ID는 소비될 수 있다.

fixture의 수령 완료·승인 기록은 테스트 전제이며 실제 수령 인증·검수 승인 화면 통과를 주장하지 않는다. 테스트 래퍼가 commit을 억제하므로 실제 commit·응답 유실·동시 요청 검증도 별도다. 인증 대체는 테스트 파일에만 존재한다. 기존 기록을 덮어쓰거나 공용 DB를 변경하지 않는다.

### C/D/A 실제 함수 연결 자동 검사

`test_c_return_complete_connection.py`는 인증과 DB 응답만 테스트 의존성으로 대체하고 실제 C 완료 API·준비 검사·D 재고 복원·A 모의 환불 함수를 같은 연결로 호출한다. 정상 복원 → 금융 기록 → 반품 완료 → 단일 commit을 확인했다. D 복원 뒤 A 금융 저장 오류를 주입해 C 완료 기록이 추가되지 않고 최상위 rollback이 호출되는 것도 확인했다. 실제 DB의 영속 복구나 동시 실행 검증으로 간주하지 않는다. 테스트용 인증 우회를 실행 코드에 추가하지 않았다.

### 직원 정상 반품 모의 완료 화면 연결

승인 반품 상세에 정상 반품 모의 환불 완료 버튼을 추가했다. 확인 창에서 실제 본사 회수·전체 상품 정상 재판매 확인을 받은 뒤 기존 complete-mock API를 호출한다. 본사 사원 전용임을 안내하며 실제 권한·검수·혜택 사용·재고 검사는 서버가 담당한다. 화면의 승인 상태만으로 실행 권한을 부여하지 않는다.

StaffReturnVm은 기존 검수·결정과 동일 saving 및 미완료 요청 상태를 공유한다. 같은 반품·동작·내용으로만 동일 요청 키 재시도를 허용하고 정상 모의 완료 응답의 ID·COMPLETED·completed·is_mock을 확인한 뒤 상세와 목록을 갱신한다. 화면 종료 후 상태 반영을 하지 않는다. 키는 VM 수명 동안 유지한다. B 혜택·알림 및 실제 결제 사업자 연결은 추가하지 않았다. 실제 앱·DB 통합 검증은 별도다.

### 정상 반품 최상위 모의 완료 API

POST `/api/v1/order-history/staff/returns/{return_request_id}/complete-mock` 요청은 `request_id`, `resale_confirmed: true`다. 기존 인증으로 검증한 HQ_STAFF만 실행한다. 실제 본사 회수·정상 재판매 확인은 직원 책임이며 D 함수가 검수 관찰 기록도 검사한다. B 혜택 미사용 주문만 허용한다.

주문→반품 잠금, 완료 감사 기록/요청 내용 재검사, 과거 미완료 금융 기록 차단, C 준비 검사→D 정상 재고 복원→A 모의 환불→C 반품 COMPLETED 및 처리 시각→완료 감사 기록→단일 commit 순서다. 실패는 전체 rollback하며 완료 재전송은 기존 결과를 반환한다. 실제 결제 사업자는 호출하지 않는다.

수령 이력인 orders.COMPLETED와 purchase_confirmed_at은 변경하지 않는다. A가 payments.REFUNDED와 refunds.SUCCEEDED를 처리하고 C는 반품 업무 완료를 기록한다. 별도 주문 REFUNDED 전이는 이번에 도입하지 않는다. 정상 재고 복원이 불가능한 불량 반품은 이 API에서 차단하며 이를 환불 권리 거절로 해석하지 않는다. 관련 별도 처리 기능은 미구현이다.

완료 기록에는 직원·주문/반품/환불 ID·요청·이전/다음 상태와 DB 감사 시각이 남는다. API가 동일 요청 본문과 같은 반품의 완료를 확인한다. 실제 MySQL 동시 요청·commit 유실 복구 검증과 직원 화면 버튼 연결은 아직 남았다. B 알림·혜택은 호출하지 않는다.

### 최신 D 정상 반품 복원 연결 준비

사용자 승인으로 `inventory.py::restore_return_inventory(db, order_id=..., return_request_id=..., employee_id=..., resale_confirmed=True)`를 최소 추가했다. 최상위 C에서 검증한 HQ 직원과 실제 본사 회수·정상 재판매 확인을 전달해야 한다. 함수는 구매 미확정 COMPLETED 주문, APPROVED 반품, ACCEPTED 본사 검수, 전체 반품 수량을 검사한다. 마모·파손·고객 과실·불량·오배송 표시가 있거나 구성품·포장이 온전하지 않으면 정상 재고 복원을 차단한다. 이것은 환불 승인 조건을 변경하는 것이 아니라 이번 정상 재고 복원 함수의 제한이다. 불량 반품 처리는 별도이며 환불 승인만으로 정상 재고를 증가시키지 않는다.

본사 옵션별 on_hand_quantity만 증가시키고 예약·불량 수량은 변경하지 않는다. RETURN 변동에 반품 ID·옵션별 고유 키·처리 직원·DB 시각·정상 재판매 확인 사유를 기록한다. 동일 복원은 재사용, 부분 복원·내용 불일치는 차단한다. 주문→반품→검수→항목→옵션 재고 순으로 잠그고 내부 savepoint를 사용하며 commit하지 않는다. 권한·혜택 미사용 차단·A 모의 환불·C 최종 상태·전체 commit/rollback은 아직 연결하지 않은 최상위 API 책임이다.

자동 테스트 및 기존 소비·보관 회귀 테스트 22개가 통과했다. DB 데이터 변경·실제 회수·실제 동시 요청 검증은 하지 않았다. Flutter와 Git은 변경하지 않았다.

- 결제 완료 후 실제 출고 전만 구매 취소 가능. 출고 이후 취소 불가.
- 첫 반품 접수는 주문 전체 항목·전체 수량을 대상으로 한다. 진행 중 반품이 있으면 구매확정을 차단한다.
- 실제 수령 완료 후 고객 구매확정 전만 반품·환불 가능. 고객이 직접 구매확정한 뒤에는 불가.
- 현재 수령 완료 표현은 orders.order_status=COMPLETED, 구매 미확정은 purchase_confirmed_at IS NULL. 구매확정은 해당 시각을 기록하며 원본 COMPLETED는 유지한다. pickups.COMPLETED와 picked_up_at도 실제 수령 증거로 확인한다.
- 결제 실행/취소/환불은 A, 재고/예약/회수 수량은 D, 쿠폰/적립금/혜택 복원·회수와 알림은 B 기능을 호출한다. C에서 각 담당 규칙을 복제하지 않는다.
- 기간·승인 조건·공제액·환불 소요일을 임의로 추가하지 않는다. 교환은 범위에서 제외한다.
- 기록을 DELETE하여 취소·환불하지 않는다. POST 업무 처리 및 기존 이력을 사용한다.

## 2. 현재 구현 사실

| 담당·위치 | 사용 가능한 것 | 없는 것·제한 |
|---|---|---|
| A backend/features/order.py | create_order, get_paid_orders, get_order_detail, pay_order_mock, mark_order_shipping | 고객 결제 완료 주문 취소·환불 함수 없음 |
| 같은 파일 cancel_expired_order(db, order_id) | PENDING_PAYMENT 예약 만료 취소, 호출자가 commit | 고객 PAID 취소와 다름. 30분은 A 기존 결제 대기 값이며 C 반품 기한이 아님 |
| B backend/features/authentication.py | current_customer, current_employee, require_permission, check_branch | 혜택 복원/회수·환불 알림 함수는 현재 features에서 확인하지 못함 |
| D backend/features/inventory.py | release_order_inventory(db, *, order_id, reason), 자체 commit 없음 | PAID 상태는 그대로 해제할 수 없음. A가 먼저 CANCELED로 변경한 뒤 같은 연결로 호출해야 함. CONSUMED/실제 출고는 해제 차단. 실물 재고는 변경하지 않음 |
| C backend/features/order_history.py | 본인 주문 조회, 직원 조회, 고객 구매확정 | 고객 취소/반품/환불 실행 API 없음 |
| 고객 presentation/screens/support_screens.dart / commerce_screens.dart | 기존 취소·처리내역 화면/목업 문구 | 실제 결제 취소·환불 성공 증거가 아님 |
| 직원 vm/staff_work_api.dart / view/staff_pages.dart | 메모리 반품 접수·검수·환불 흐름 | 실제 네트워크/DB/결제 처리 없음 |

### 기존 목업과 정책 불일치

- support_screens.dart의 '수령 전까지만 취소'는 확정한 '출고 전까지만 취소'와 다르다.
- staff_work_api.dart는 반품 기한을 pickedUpAt + 7일로 만들지만 확정 기한이 아니다.
- commerce_screens.dart의 영업일 2~5일 환불 안내와 예시 완료 내역은 실제 계약/처리 결과가 아니다.
- return_policies의 standard_return_days 기본 7도 승인된 업무 기한으로 간주하지 않는다. 기존 목업을 그대로 실제 코드로 옮기지 않는다. 이번 작업은 문서만 작성하므로 위 코드는 수정하지 않는다.

## 3. 기존 테이블·상태

| 테이블 | 기존 필드·관계 |
|---|---|
| orders / order_items | 상태·취소 시각·구매확정 시각, 주문 당시 상품·금액·수량 |
| payments | payment_id/order_id, payment_amount/status, transaction_key/paid_at. 상태 PENDING/PAID/FAILED/CANCELED/PARTIALLY_REFUNDED/REFUNDED |
| fulfillments / fulfillment_items | 실제 출고 흔적·배송 상태·항목 수량. PREPARING 기록은 주문 PREPARING과 구분 |
| inventory_reservations / inventory_movements | 예약 해제·소비와 D 변동 이력 |
| return_requests | order_id/customer_id, return_policy_id/branch_id, 처리 직원, 사유 코드/본문, request_status, 기한·검수·거절 이유·처리 시각 |
| return_items | return_request_id/order_item_id/quantity, 같은 요청의 같은 항목 유일 |
| after_sales_inspections | return_request_id, BRANCH/HEADQUARTERS 검수 단계별 유일 기록, 직원·검수 항목·판정·시각 |
| refunds | payment_id/order_id 일치 복합 FK, 선택 return_request_id, 금액·상태·idempotency_key·외부 키·실패/재시도/시각 |
| audit_logs / order_status_history | 요청 식별자·처리자·이전/다음 상태·연결 업무 ID |

return_requests 상태: REQUESTED / APPROVED / REJECTED / COLLECTING / INSPECTING / RETURNED / COMPLETED / CANCELED.
사유 코드: CUSTOMER_CHANGE / PRODUCT_DEFECT / WRONG_ITEM / OTHER.
검수 판정: PENDING / ACCEPTED / REJECTED. 착용·파손·고객 과실·구성품·포장·제품 하자·오배송 필드가 있지만 이 항목만으로 자동 승인 규칙을 정하지 않는다.
refunds 상태: REQUESTED / PROCESSING / SUCCEEDED / FAILED / CANCELED. 유형: ORDER_CANCEL / RETURN / MANUAL_ADJUSTMENT. 마지막 유형은 이번 C 범위에 추가하지 않는다.
refunds.idempotency_key와 provider_refund_key는 유일 제약이 있다. SUCCEEDED는 completed_at, FAILED는 failed_at이 필요하다. DB 허용 상태가 실제 단계 전이를 자동 확정하지 않는다.

## 4. 고객 구매 취소 제안

1. B 검증 고객 ID로 본인 주문을 잠근다. 현재 PAID와 PAID 결제 기록·출고 없음 조건을 확인한다. 이 PAID 제한은 첫 구현 제안이며 PREPARING 취소 포함 여부는 A와 별도 결정한다.
2. fulfillments.shipped_at, 실제 진행 상태, D 예약 CONSUMED 등 출고 증거가 있으면 차단한다. 주문 상태 하나만으로 판정하지 않는다.
3. A 취소/환불 계약을 호출한다. 주문 CANCELED와 결제/환불 성공을 같은 의미로 표시하지 않는다. 외부 환불 진행이면 고객에게 진행 중으로 표시한다.
4. A가 허용한 CANCELED 전이 후 D release_order_inventory를 같은 DB 연결로 호출한다. 준비 배송 기록 처리 방식은 합의 후 적용한다.
5. B 혜택 복원·회수와 알림을 연결한다. 현재 예약된 혜택과 실제 사용 혜택 구분은 B가 결정한다.
6. 최상위 C가 상태·예약·내부 환불 기록·이력을 함께 저장한다. 실제 외부 환불은 아래 실패 계약을 따른다.

출고와 취소는 orders 행 잠금을 공유한다. 선행 업무가 완료된 뒤 후행 업무가 상태를 다시 검사하여 차단해야 한다. 취소 승인 필요 여부·부분 취소·배송 준비 기록 취소 방법은 미확정.

## 5. 반품·환불 제안

1. 본인 주문, 실제 수령 완료, purchase_confirmed_at IS NULL 확인 후 REQUESTED 접수. 요청 수량은 주문 항목·기존 접수/환불 수량과 비교한다.
2. 실제 반환 상품 접수·회수·검수를 기록한다. BRANCH/HEADQUARTERS의 검수 단계가 둘 다 필요한지와 최종 승인 담당을 정한다.
3. 검수 판정과 승인 조건을 서버에서 검사한다. 착용·포장 항목을 임의의 자동 거절 조건으로 만들지 않는다.
4. D가 회수품의 보관·정상/불량 재고를 처리한다. 접수만으로 판매 가능 재고를 증가시키지 않는다.
5. 승인된 환불은 A 함수로 실행하고 B 혜택 조정을 연결한다. 금액은 앱 값이 아니라 A/B 공통 계산 결과를 사용한다.
6. A가 성공한 환불 기록을 확인한 뒤 C 업무 완료로 연결한다. 주문 REFUNDED는 전체/부분 환불 의미를 A와 확정한 뒤 적용한다.

REQUESTED → COLLECTING → INSPECTING → RETURNED → COMPLETED는 가능한 설명용 흐름이다. APPROVED를 어느 단계에서 기록할지와 REJECTED 이후 상품 반환 방식은 승인되지 않았다.
첫 버전 전체 주문 취소·반품·환불만 지원하는 방식을 추천하나 미확정이다. 테이블이 항목별 수량을 지원한다고 부분 처리 정책까지 자동 채택하지 않는다.
반품 접수와 구매확정 동시 요청은 같은 주문 잠금으로 처리해야 한다. 접수된 반품 진행 중 구매확정 허용 여부는 별도 정책 확정 및 기존 구매확정 API 검토가 필요하다. 이번 문서 작업에서 실행 코드를 변경하지 않는다.

## 6. 권한 제안

- 고객: 본인 취소/반품 요청·진행내역 조회. customer_id는 토큰으로 식별.
- 대리점 직원·점장: 활성 소속 대리점의 반환 상품 접수·검수. 본사 사원: 본사 검수·처리. 환불 실행 권한은 별도로 확정한다.
- 기존 출고·문의 권한을 환불 권한으로 확대하지 않는다. B에 실제 업무 권한 코드·직급·지점 범위를 확인한다.
- 요청 branch_id나 화면 선택 직급은 권한 근거가 아니다. 기록의 주문 수령 지점과 업무 지점 일치 조건도 결정한다.

## 7. API 제안 — 아직 구현·확정 아님

기존 C APIRouter를 유지한다. 다음 경로·본문은 팀 계약 제안이다.

| 용도 | 경로·입력 제안 |
|---|---|
| 고객 취소 요청 | POST /api/v1/order-history/customer/{order_id}/cancel, request_id와 사유 |
| 고객 반품 접수 | POST /api/v1/order-history/customer/{order_id}/returns, request_id/return_reason_code/return_reason/items(order_item_id,quantity) |
| 고객 처리내역 | GET /api/v1/order-history/customer/{order_id}/after-sales |
| 직원 반품 목록 | GET /api/v1/order-history/staff/returns, page/page_size/branch_id/request_status |
| 직원 검수 | POST /api/v1/order-history/staff/returns/{return_request_id}/inspection, 요청 ID와 기존 검수 필드 |
| 환불 업무 연결 | POST /api/v1/order-history/staff/returns/{return_request_id}/refund, 요청 ID. 금액/직원/상태는 서버 결정 |

공통 data/message/pagination, error.code/message, snake_case와 정수 ID/원 단위 금액을 유지한다. 접수 성공과 실제 환불 완료는 분리한다. 목록 결과 없음은 200/data:[].

## 8. 트랜잭션·중복·외부 실패

- 같은 MySQL에서 함께 성공해야 하는 주문·반품·예약·혜택·이력은 같은 연결을 사용하며 최상위가 commit/rollback한다. 하위 함수 중간 commit 금지.
- 주문 → 관련 배송/반품/결제 → 예약/재고 순서를 제안하며 실제 A/D 잠금 순서와 맞춘다.
- 신규 접수는 요청 ID를 저장해 재전송 결과를 확인한다. refunds 기존 고유 idempotency_key를 활용하되 업무 키 범위/생성은 A와 합의한다. audit_logs.request_id만으로 중복 방지가 된다고 가정하지 않는다.
- 같은 요청 재전송은 기존 결과 반환, 내용 충돌은 409 ALREADY_PROCESSED. 환불 성공 합계가 결제 금액을 넘지 않도록 A가 검증한다. 실패/진행 기록이 있는 재시도도 함께 고려한다.
- 외부 결제 환불 성공은 MySQL rollback으로 취소할 수 없다. A가 외부 키·PROCESSING/FAILED/SUCCEEDED·기존 결과 조회·재시도/복구 방법을 제공해야 한다. 응답 유실을 새 환불로 처리하지 않는다.
- 외부 성공 후 내부 실패는 복구 대상이지 새 결제/환불 실행 근거가 아니다. 장시간 DB 잠금을 잡고 외부 호출할지는 A와 정하며 단순 한 트랜잭션으로 외부 원자성을 주장하지 않는다.
- B 알림 실패는 해당 알림만 재처리한다. 완료된 취소·환불을 다시 실행하지 않는다.
- 인증 토큰·비밀번호·SQL·내부 예외는 응답/감사 기록에 노출하지 않는다. 처리자·서버 시각·변경 내용·업무 ID를 기록한다.

## 9. 오류·검증

401 UNAUTHENTICATED, 403 FORBIDDEN, 404 NOT_FOUND, 400 INVALID_INPUT, 409 INVALID_STATE_TRANSITION/ALREADY_PROCESSED, 500 INTERNAL_ERROR. 재고 오류는 D 공통 코드, 외부 결제 오류 세부 코드는 A와 합의한다.
자동 테스트: 본인/타인, 직원 역할·소속, 출고 후 취소, 수령 전 반품, 구매확정 후 반품, 항목 소유/수량, 중복·응답 유실, 금액 초과, 각 단계 실패.
로컬 통합 테스트: 취소와 출고 동시 요청, 구매확정과 반품 동시 요청, 각 하위 함수 실패 전체 rollback, 외부 성공 후 내부 실패 복구. 실제 기기/결제 모의 검증은 별도.

## 10. 담당별 받아야 할 계약

- A: 결제 완료 취소·환불 함수명/파일/인자/반환값, PAID/PREPARING 취소 범위, 주문·결제 상태 전이, 전체/부분 금액 계산, idempotency_key·외부 결과 확인·commit 책임.
- B: 혜택 복원/회수 함수와 부분 환불 배분 규칙, 직원 환불/검수 권한, 알림 실패 재처리. 리뷰·구매확정 조건 연결.
- D: 취소된 준비 배송/보관 기록 처리, 반환품 정상/불량 재고 함수, 실제 회수 시점, 잠금 순서·같은 연결·중복·commit 없음.
- C/팀: 취소 승인 여부, 반품 접수·검수·최종 승인 주체, 파손/포장 조건, 전체/부분 처리, 진행 중 반품의 구매확정 차단, 기한/수수료/환불 일정 필요 여부. 새 기간·금액은 합의 전 구현하지 않는다.

## 11. 사용자 승인에 따른 A 연결안과 C 선행 구현

이 절은 C에서 채택한 A 연결 요청안이다. A에게 공유해야 하며, 아래 함수가 현재 A 코드에 존재한다는 뜻은 아니다. A/B/D 코드 및 공통 스키마는 이번 선행 작업에서 수정하지 않는다.

### A에게 제공할 입력과 책임

- 첫 연결은 전체 주문 취소·전체 환불을 대상으로 준비한다. 부분 금액 계산은 구현하지 않는다.
- C는 B가 검증한 customer_id 또는 employee_id, order_id, request_id, 사유, 반품 환불이면 return_request_id를 전달한다. 금액·결제 상태·권한은 앱 입력을 신뢰하지 않는다.
- C는 본인 주문·실제 출고 여부 또는 실제 수령·구매확정 여부를 검사한다. 직원 환불 실행 권한과 반품 승인 조건은 아직 대기한다.
- 취소 실행 시작은 PAID에 한정한다. PREPARING을 취소 가능 상태로 임의 확대하지 않는다.
- 최상위 C가 동일 MySQL 연결에서 잠금과 commit/rollback을 담당한다. A/D/B 하위 함수는 중간 commit하지 않는다.

### A에게 요청할 함수 계약 — 이름은 신규 요청안

기존 backend/features/order.py 위치를 유지하고, 라우트와 분리된 호출 함수를 요청한다. 새 Service/Repository 계층은 필요하지 않다.

1. `cancel_paid_order(db, *, order_id, customer_id, request_id, reason)`
   - 잠근 주문의 PAID 및 PAID 결제 기록, 허용된 상태 전이를 다시 검사한다.
   - A가 주문 CANCELED와 기존 주문 상태 이력을 기록한다. 결제/환불 상태는 별도 결과로 제공한다.
   - 기존 예약 만료 함수 cancel_expired_order를 대체 사용하지 않는다.
2. `refund_return_order(db, *, order_id, return_request_id, employee_id, request_id)`
   - C가 확정된 권한·검수 조건을 확인한 승인 건만 전달한다.
   - A가 기존 결제와 이전 환불·진행 중 금액을 기준으로 환불 가능 금액을 계산한다.
   - refunds.idempotency_key를 활용하여 같은 업무의 재전송이 새 환불을 만들지 않게 한다.
3. 두 함수의 반환 계약: 기존 필드 기준 order_id/order_status/refund_id/refund_status/refund_amount/completed_at. 아직 생성되지 않은 환불 ID·시각은 null. SUCCEEDED만 환불 완료이며 PROCESSING을 성공 완료로 표시하지 않는다.
4. 외부 결제 연동 시에는 A가 기존 결과 확인·재시도·외부 성공 후 DB 실패 복구 계약을 먼저 제공한다. DB 트랜잭션으로 외부 환불까지 원자적이라고 가정하지 않는다. 현재 모의 결제도 실제 카드 환불로 표현하지 않는다.

B/D 연결이 대기 중이므로 위 함수 구현·호출 및 취소/반품/환불 POST는 아직 활성화하지 않는다. A 연결안 승인만으로 재고·혜택을 생략한 취소 완료를 허용하지 않는다.

### 이번에 실제 구현한 C 조회

`GET /api/v1/order-history/customer/{order_id}/after-sales`

- 기존 C 라우터와 B authenticated_customer 의존성을 사용한다. 서버 검증 고객 ID로 orders 소유권을 먼저 확인한다. 타인/없는 주문은 404, 잘못된 ID는 400, 인증 없음은 401.
- data: order_id/order_status/canceled_at/return_requests/refunds. 반환 목록 없음은 각각 [].
- return_requests는 해당 주문과 고객 조건으로 조회한다. 기존 사유·상태·지점·접수/처리 시각·검수 결과·거절 이유를 반환한다.
- refunds는 소유권을 확인한 주문의 기존 기록만 조회한다. refund_id/refund_number/return_request_id/refund_type/refund_status/refund_amount 및 requested_at/processing_at/completed_at/failed_at을 반환한다.
- 요청 시각 DESC, 각 기록 ID DESC로 같은 시각의 순서를 고정한다. 기존 날짜·상태값을 변환하지 않는다.
- 결제 외부 키·idempotency_key·내부 실패 메시지는 노출하지 않는다. 주문 CANCELED와 환불 SUCCEEDED를 동일하게 취급하지 않는다.
- 조회만 수행하며 commit/rollback, 주문/결제/혜택/재고 변경은 없다. 고객 구매 내역의 주문 상세 창에서 OrderHistoryDetailVm.loadAfterSales → AuthApi.get → 이 API → OrderAfterSales → 처리내역 표시로 연결했다. 기존 별도 목업 처리내역 화면은 실제 조회로 간주하지 않는다.
- 상세 창을 열면 주문 상세와 처리내역을 독립적으로 조회한다. 처리내역 로딩·빈 결과·실패·재시도를 제공하고, 중복 조회 및 창 종료 후 늦은 결과 반영을 막는다. 서버 시각은 원문 표시하며 알려지지 않은 상태는 확인되지 않은 상태로 표시한다. 실행 버튼은 추가하지 않는다.

### 다음 연결 순서

A가 위 함수 계약을 구현하거나 기존 함수명을 공유 → D 예약 해제/B 혜택 계약 확인 → C 취소 POST 및 고객 화면 연결 → 반품 접수/검수 권한·구매확정 동시 처리 합의 → 반품·환불 실행 연결. 미확정 기간·수수료·검수 승인 규칙은 계속 대기한다.

## 12. 전체 반품 접수 구현 — 최신 확정 내용

사용자 승인으로 전체 주문 반품과 진행 중 반품의 구매확정 차단을 확정했다. 앞 절의 부분 처리·동시 구매확정 미확정 설명은 이 절로 대체한다. 검수·승인·환불 실행 권한은 여전히 미확정이다.

- POST /api/v1/order-history/customer/{order_id}/returns: request_id, return_reason_code, return_reason. 앱이 항목·수량·금액·상태를 보내면 거부한다. 사유는 기존 CUSTOMER_CHANGE/PRODUCT_DEFECT/WRONG_ITEM/OTHER만 사용한다.
- 서버 검증 고객 ID로 본인 주문을 확인하고 COMPLETED, purchase_confirmed_at IS NULL, 같은 대리점의 pickups.COMPLETED/picked_up_at 기록을 검사한다.
- 고객 행 → 주문 행 순으로 잠금. 고객별 요청 ID 재전송을 직렬화하고 기존 RETURN_CREATE 감사 기록의 주문·사유가 같으면 200/기존 접수 ID, 다르면 409. 신규는 201/data.return_request_id.
- 기존 반품 중 REJECTED/CANCELED 이외의 기록 또는 CANCELED 이외의 환불 기록이 있으면 안전하게 재접수를 차단한다. 기존 환불 FAILED 복구를 신규 반품으로 처리하지 않는다. 거절 후 재접수 권한·정책은 실행 연결 시 재검토한다.
- 서버 주문 항목의 전체 수량을 return_items에 기록한다. return_requests 기본 REQUESTED와 DB CURRENT_TIMESTAMP를 사용한다. 임의 기한/정책 ID는 만들지 않는다. 감사 로그와 접수 항목은 같은 트랜잭션에서 commit하며 실패하면 rollback한다.
- 구매확정과 접수 모두 orders 행을 FOR UPDATE로 잠근 뒤 다시 검사한다. REQUESTED/APPROVED/COLLECTING/INSPECTING/RETURNED는 진행 중이므로 구매확정 불가. 상태 이름의 의미를 확장하여 환불 완료로 간주하지 않는다.
- 고객 상세에 전체 반품 접수 사유 입력을 연결했다. 중복 클릭을 막고 응답 불명 시 화면이 유지되는 동안 같은 request_id·내용으로 재시도한다. 창을 다시 열면 기존 처리내역을 먼저 조회한다. 앱 재시작을 넘는 요청 ID 영구 저장은 아직 없다.
- 성공 안내는 접수이며 환불 완료가 아니다. 실제 환불/혜택/재고/알림은 실행하지 않는다. 반품 진행 중 구매확정 버튼도 비활성화한다.
- 실제 DB 생성·수정 테스트는 수행하지 않았다. DB 의존성 대체 테스트로 분기·잠금 SQL·rollback을 검증하며 실제 MySQL 동시 요청 검증은 별도 필요하다.

## 13. 직원 반품 조회 구현

- 사용자 진행 요청으로 조회 범위 확정: HQ_STAFF 전체, BRANCH_STAFF/BRANCH_MANAGER는 B가 검증한 활성 소속 대리점, 그 외 거부. 조회 권한만 확정하며 실행 권한은 확대하지 않는다.
- GET /api/v1/order-history/staff/returns: page/page_size/branch_id. return_requests.branch_id(접수 시 기록한 주문 수령 대리점)를 기준으로 서버 권한 필터 → requested_at DESC/return_request_id DESC 정렬 → 페이지 처리한다. 소속 없는 직원은 빈 목록, 소속 외 branch_id 요청은 403.
- GET /api/v1/order-history/staff/returns/{return_request_id}: 범위 밖/없는 접수는 404. 주문 번호·지점·상태·사유·접수 시각·항목 스냅샷·검수·연결 환불 기록을 반환한다. 결제 외부 키·내부 실패 메시지는 노출하지 않는다.
- StaffReturn/StaffReturnVm/StaffReturnView로 기존 대시보드 반품 메뉴에 실제 조회를 연결했다. 직급·지점 키가 변경되면 기존 화면과 VM을 폐기하여 이전 목록을 제거한다. 로딩·오류·재시도·빈 결과·페이지·상세 닫힘 후 늦은 응답 무시를 제공한다.
- 주문 항목의 옵션·접수 수량을 표시하고 원본 서버 시각을 유지한다. 검수/환불 결과는 기존 기록이며 승인·검수 저장·환불 실행은 제공하지 않는다. 인증 요청 함수가 없는 목업 대시보드는 기존 목업으로 유지하며 실제 조회로 간주하지 않는다.

## 14. 직원 검수 관찰 저장 — 최신 확정 내용

사용자가 제안 기준을 승인했다. 대리점 직원·점장은 활성 소속 대리점의 BRANCH 검수, HQ_STAFF는 HEADQUARTERS 검수를 수행한다. 조회 권한을 재사용하여 실행 범위를 자동 확대하지 않는다.

- POST /api/v1/order-history/staff/returns/{return_request_id}/inspection. 요청: request_id, inspection_stage, received_product=true, 기존 7개 관찰 bool 필드, inspection_notes. 서버 검증 직원 ID와 DB CURRENT_TIMESTAMP를 기록한다.
- 직원이 실제 반환 상품 수령을 확인해야 한다. REQUESTED/COLLECTING에서 최초 관찰 저장 후 INSPECTING으로 변경한다. INSPECTING에서도 아직 없는 다른 단계의 최초 기록만 추가한다. 단계별 기록 수정은 제공하지 않는다.
- 검수 판정은 기존 기본 PENDING으로 유지한다. 관찰 값만으로 자동 승인·거절하지 않으며 결제·재고·혜택은 변경하지 않는다.
- 직원 행 → 반품 접수 행 잠금 후 요청 감사 기록/단계별 기록을 검사한다. 기존 단계 유일 제약과 함께 동시 저장을 차단한다. 관찰·접수 상태·감사 로그는 같은 연결에서 한번 commit하고 실패하면 rollback한다.
- RETURN_INSPECT 감사 기록의 동일 직원 요청 ID/본문 재전송은 기존 ID 반환, 내용 충돌 또는 다른 요청 ID로 이미 저장된 단계는 409. 동일 본문 재전송은 신규 201과 달리 200이다.
- 직원 화면은 저장 중 중복 클릭을 막으며 응답 불명 시 같은 요청 키·입력값으로 재시도한다. 화면 종료 후 늦은 응답은 반영하지 않는다. 앱 재시작을 넘는 요청 키 영구 저장은 없다.
- B 인증·직급·소속 검증은 연결됨. B 혜택/알림 및 D 실제 출고 소비·반품 재고 복원은 미연결이며 이 API는 호출하지 않는다.

## 15. 검수 후 최종 승인·거절 — 최신 확정 및 구현

사용자 진행 승인으로 HQ_STAFF 최종 결정, 본사 검수 기록이 있는 INSPECTING 상태, 거절 사유 필수, 최초 결정만 허용을 확정했다. APPROVED는 접수 승인 대신 **검수 후 최종 승인**을 뜻한다. 환불 준비 상태이며 실제 환불 성공이 아니다. 기존 데이터의 APPROVED 의미가 다르면 연결 전에 확인하고 자동 변환하지 않는다.

- POST /api/v1/order-history/staff/returns/{return_request_id}/decision. 본문 request_id/decision(APPROVED 또는 REJECTED)/rejection_reason. 거절 사유는 거절 시에만 필수이며 승인 시 null이다. 직원·상태·시각은 서버가 결정한다.
- B current_employee 결과의 HQ_STAFF만 허용. 직원 행 → return_requests 행 → HEADQUARTERS 검수 행 순으로 잠근다. INSPECTING 및 본사 inspection_decision=PENDING을 확인한 뒤 결정한다. 대리점 검수만으로 결정할 수 없다.
- 본사 검수 판정은 승인 시 ACCEPTED, 거절 시 REJECTED로 기록한다. 관찰 값 자체는 바꾸지 않는다. 접수 request_status, rejection_reason, handled_by_employee_id, processed_at=CURRENT_TIMESTAMP와 감사 로그를 같은 트랜잭션으로 기록한다. 여기 processed_at은 최종 결정 시각이며 환불 완료 시각이 아니다.
- RETURN_DECIDE 감사 로그에 처리 직원·이전 상태·연결 검수 ID·결정·사유·요청 ID를 기록한다. 동일 직원의 같은 요청·본문은 기존 결정 결과를 반환하고, 본문 충돌은 409. 이미 결정된 접수는 새 요청으로 반대 결정/수정 불가.
- 승인·거절은 200/data.return_request_id/request_status. 실제 환불·주문 REFUNDED 변경·D 재고 복원·B 혜택/알림은 호출하지 않는다. APPROVED는 진행 중 반품으로 유지되어 구매확정을 계속 차단한다. 거절 후 상품 반환 절차는 미확정이며 구현하지 않는다.
- 직원 상세의 본사 판정 대기 기록이 있는 접수에 결정 입력을 제공하고 서버에서 HQ_STAFF 권한을 최종 검사한다. 화면상 직급 선택은 권한 근거가 아니다. 저장 중 검수·결정 동시 전송을 막고 응답 불명 시 같은 키·내용으로 재시도한다.
- 고객 기존 처리내역에서 APPROVED는 ‘반품 최종 승인 · 환불 대기’, REJECTED는 거절 및 사유로 표시한다. 신규 환불 기록을 만들어 완료로 표시하지 않는다.
- 자동 테스트는 DB·인증 대체로 권한·상태·본사 검수 필요·거절 사유·중복/반대 결정·트랜잭션 실패를 검증한다. 실제 DB 동시 요청·기기 검증은 아직 별도 수행해야 한다.

## 16. A 환불 연결 준비 구현

이 준비 단계 당시 order.py에는 환불 함수가 없었다. 이후 추가한 모의 환불 계약은 아래 18절을 따른다. staff_payments.py는 조회만 제공하며 실제 결제 사업자 환불은 구현하지 않았다.

`backend/features/order_history.py::prepare_approved_return_refund(db, *, return_request_id, request_id, employee)`를 추가했다. 라우트 함수가 아니며 HTTP 실행 API·환불 버튼에는 아직 연결하지 않는다.

- B가 검증한 HQ_STAFF의 **연결 준비**만 허용한다. 이는 환불 실행 권한을 확정한 것이 아니다.
- 주문 → 반품 접수 → 본사 검수/수령/항목을 잠그고 APPROVED, 주문 COMPLETED, 구매 미확정, HEADQUARTERS ACCEPTED, 실제 수령 완료, 전체 주문과 정확히 같은 반품 항목·수량을 검사한다. 과거 APPROVED 기록도 본사 승인 증거 없이는 통과하지 않는다.
- 반환값은 기존 A 요청안 인자 order_id/return_request_id/employee_id/request_id다. 금액을 계산하거나 refunds/주문/재고/혜택을 변경하지 않으며 commit/rollback하지 않는다. 준비 함수 오류 후 rollback과 잠금 해제는 호출자의 책임이다.
- 함수가 반환된 것은 환불 가능 금액 확정·실행 허가·환불 성공이 아니다. 준비 상태가 끝난 뒤 실제 호출까지 동일 트랜잭션 또는 A 복구 계약에 따라 재검증해야 한다. 최상위 직원 행 잠금 등이 추가되면 기존 직원→주문→접수 순서와 일치시킨다.
- 실제 A 연결 예상: C 실행 권한 확인 → 이 준비 함수 → A refund_return_order(db, **준비결과) → A 실제 결과 확인 → D/B 및 최상위 완료 처리. 함수명은 아직 A 요청안이지 존재하는 구현이 아니다. 부분 작업만 연결해 반품 COMPLETED나 주문 REFUNDED로 변경하지 않는다.

### A에 전달할 구체적인 요청

기존 order.py 위치에 라우트와 분리된 전체 반품 환불 함수를 제공하거나 실제 함수 계약을 공유해주세요. 입력은 위 4개 인자와 db이며 앱 금액은 받지 않습니다. 다음 책임을 명시해야 합니다.

1. 기존 결제·진행/성공/실패 환불을 확인하여 금액 및 중복 실행을 서버에서 검증.
2. 기존 refunds.idempotency_key의 업무 범위·request_id 연결 규칙, 다른 키로 같은 반품 재요청한 경우의 기존 결과 조회.
3. 반환 order_id/order_status/refund_id/refund_status/refund_amount/completed_at, 오류 코드, PROCESSING/FAILED 복구·응답 유실 후 조회 방법.
4. MySQL 하위 함수의 commit 없음과 실제 외부 결제 작업의 트랜잭션·복구 책임. 외부 성공을 DB rollback으로 되돌릴 수 있다고 가정하지 않음.
5. 모의 환불이라면 모의 처리임을 분명히 표시. 실제 환불 실행 직원 권한은 최종 결정 권한과 별도로 합의.

현재 자동 테스트는 준비 검증·호출 인자·읽기 전용 SQL·트랜잭션 소유 책임만 검증한다. **A 환불 성공·중복 환불 방지·실제 환불 실패 복구는 아직 검증되지 않았다.** Flutter의 기존 PROCESSING/SUCCEEDED/FAILED 표시를 환불 실행 기능이 완성된 것으로 간주하지 않는다.

## 17. 구매 취소 연결 전 준비

`prepare_customer_order_cancel(db, *, order_id, customer_id, request_id, reason)`를 기존 C 파일에 추가했다. customer_id는 B가 검증한 고객 정보에서만 전달한다. HTTP 실행 API는 아니며 고객 앱 입력 ID를 직접 신뢰하는 연결을 하지 않는다.

- 주문 소유권·PAID·동일 주문 PAID 결제 기록을 검사한다. PREPARING 주문은 제외한다.
- 배송 없음 또는 단일 PREPARING 배송의 모든 진행 시각 없음만 허용한다. 배송 취소·다중 기록·실제 진행 흔적은 자동 판단하지 않고 차단한다.
- D inventory_reservations의 CONSUMED 또는 consumed_at 흔적이 있으면 차단한다. 기록만 읽으며 예약 해제·재고 계산은 D에서 수행해야 한다.
- 반환 order_id/customer_id/request_id/reason은 A 취소 계약의 호출 준비 인자다. 금융 금액·상태 전이는 계산하지 않는다. 하위 commit/rollback 없음, 주문 잠금과 호출자 최상위 트랜잭션 필요.
- 고객 상세의 PAID 주문에 출고 전 취소 조건 및 연결 준비 중 안내를 제공한다. 비활성 버튼이며 취소 요청·가짜 완료를 만들지 않는다. PAID 표시만으로 실제 취소 실행 가능성을 보장하지 않는다.
- 반품 접수 응답이 유실되어 미확정이면 같은 내용/키로 재시도하며, 그 사이 구매확정을 막는다. 처리내역이 로딩·오류이거나 아직 확인되지 않으면 구매확정/새 반품을 허용하지 않는다.
- 반품·환불 실패/완료 시각은 원문이며 알려지지 않은 상태를 성공으로 표시하지 않는다.

## 18. 전체 반품 모의 환불 — 구현된 내부 계약

`backend/features/order.py::refund_return_order_mock(db, *, order_id, return_request_id, employee_id, request_id)`를 제공한다. 기존 A 파일의 내부 함수이며 새 실행 API나 버튼에 연결하지 않았다. 요청안 `refund_return_order`와 구분한다.

- 호출자는 B 검증 직원의 실행 권한 및 C `prepare_approved_return_refund`의 전체 반품·본사 검수 조건을 같은 트랜잭션에서 먼저 검사해야 한다. 이 금융 함수 자체는 인증·직급·전체 반품 검수를 대신하지 않는다.
- 주문 → 반품 → 환불/결제 잠금 순서다. 신규 환불은 COMPLETED·구매 미확정·APPROVED이며 동일 주문의 단일 PAID/MOCK 결제 금액이 paid_total과 일치해야 한다. 앱에서 금액을 받지 않는다.
- 기존 refunds에 RETURN/SUCCEEDED 전체 금액 모의 환불을 기록하고 payments를 REFUNDED로 변경한다. 외부 결제 호출 및 provider_refund_key 생성은 없다. DB CURRENT_TIMESTAMP, UUID 32자리 refund_number를 사용한다.
- request_id를 SHA-256으로 변환한 `mock-return:` 키를 refunds.idempotency_key에 저장한다. 같은 키를 다른 주문/반품에 사용하면 차단한다. 다른 키라도 같은 주문·반품의 성공한 모의 환불이 있으면 기존 결과를 반환한다. 진행/실패/다른 환불 기록이 있으면 추가 실행을 막고 별도 복구가 필요하다. 취소된 키 재사용도 차단한다.
- 결과: refund_id/order_id/return_request_id/refund_type/refund_status/refund_amount/completed_at/replayed/is_mock. `is_mock=true`는 실제 카드 환불이 아니라 테스트용 금융 기록임을 뜻한다.
- audit_logs에 MOCK_RETURN_REFUND, 검증 직원 ID, 환불 ID 및 요청 ID를 기록한다. 환불 행 자체에 금액·상태·서버 시각·연결 주문/반품/결제 ID가 남는다.
- 하위 commit/rollback은 없다. 호출자는 오류 시 전체 rollback해야 하며 주문 잠금을 유지한 동일 연결에서 D/B 처리 및 최상위 완료 여부를 결정한다. 주문 REFUNDED·반품 완료 변경은 이 함수가 수행하지 않는다. 이 함수를 단독 commit하여 C 전체 처리가 끝난 것으로 간주하지 않는다.
- 이 단계 당시 구매 취소 모의 환불은 미구현이었다. 후속 구현은 아래 19절을 따른다. 실제 환불 사업자 연결, D 재고 복원, B 혜택/알림 및 C 최종 실행 API는 미구현이다. 실제 DB 동시 요청·롤백 검증은 별도로 필요하다.

자동 테스트는 대체 DB로 성공·업무 재전송·요청 키 충돌·부적격 상태·실결제 차단·금액 불일치·진행/실패 기록 차단·쓰기 실패 전파 및 하위 commit 없음만 검증한다.

## 19. 출고 전 구매 취소 모의 환불 — 내부 함수 구현

`backend/features/order.py::cancel_paid_order_mock(db, *, order_id, customer_id, request_id, reason)`를 추가했다. 기존 제안 `cancel_paid_order`와 구분하며 실행 라우트·고객 버튼은 활성화하지 않았다.

- customer_id는 B 인증 결과에서만 전달한다. 고객 입력 ID나 UID를 인증 대신 사용하지 않는다. 소유권 확인 후 주문 행을 잠그고 처리하며, 타인 주문/없는 주문은 404로 응답한다.
- 신규 금융 처리는 주문 PAID, 배송 없음 또는 단일 PREPARING이며 모든 진행 시각 없음, D 예약 CONSUMED/consumed_at 흔적 없음일 때만 허용한다. 주문 PREPARING은 제외한다. 재고 기록은 검사만 하고 D 예약 해제를 대신 구현하지 않는다.
- 기존 단일 PAID/MOCK 결제의 payment_amount가 orders.paid_total과 같은 경우 서버 기록의 전체 금액을 모의 환불한다. 실결제·다중 결제·부분 환불·불일치 금액은 차단한다.
- refunds에 ORDER_CANCEL/SUCCEEDED 및 DB CURRENT_TIMESTAMP, UUID 32자리 번호를 기록하고 payments를 REFUNDED로 변경한다. 반품 접수 ID는 null이다. 실제 외부 환불은 없다.
- 요청 키는 `mock-cancel:` + SHA-256(request_id)이며 기존 100자 컬럼을 사용한다. 같은 키의 다른 주문/유형 또는 취소된 키 재사용은 차단한다. 동일 키 재전송 시 감사 기록의 정규화된 사유도 확인한다. 다른 키라도 해당 주문의 성공한 모의 취소 환불이 있으면 기존 결과를 반환하고 추가 환불하지 않는다. 진행/실패/다른 유형의 환불은 별도 복구가 필요하다.
- audit_logs의 MOCK_ORDER_CANCEL에 검증 고객 ID, 환불 ID, 요청 ID와 취소 사유를 남긴다. 결과는 refund_id/order_id/return_request_id/refund_type/refund_status/refund_amount/completed_at/replayed/is_mock다.
- 주문 CANCELED 및 canceled_at, 재고·혜택·알림은 변경하지 않는다. 실제 주문 취소 완료가 아니라 내부 금융 처리다. 하위 commit/rollback 없이 호출자가 동일 연결의 최상위 트랜잭션 전체를 책임진다. 예외 발생 시 호출자는 반드시 전체 rollback해야 한다.

### 이후 연결 시 주의

최초 요청 순서는 아래 20절에서 확인한 D의 상태 조건을 따른다. 기존 D 함수가 PAID에서 바로 예약을 해제한다고 가정하지 않는다. 실행 API는 아직 만들지 않는다.

이미 금융 결과가 저장된 요청은 C 준비 함수의 PAID 결제 검사부터 다시 시작하면 실패할 수 있다. 최상위 API는 인증·소유권 검증 후 기존 업무 결과를 먼저 확인하고, 반환된 환불 성공만으로 D/B까지 완료됐다고 판단하지 않아야 한다. 부분 결과만 단독 commit하지 않는 것이 기본이며, 과거 부분 저장 데이터의 복구는 관련 담당 계약 확인 후 수행한다.

현재 검증은 대체 DB 자동 테스트다. 실제 MySQL 동시 요청·트랜잭션 롤백, 실제 앱 및 공통 업무 통합 검증은 별도 남아 있다. B 혜택 처리를 제외하려면 제외 정책을 명시적으로 확정해야 하며 누락한 채 완료 처리하지 않는다.

## 20. C → A 연결 자동 검증 및 D 전달 내용

`backend/tests/test_c_mock_refund_connection.py`에서 C 준비 함수와 A 모의 환불 함수를 실제로 같은 대체 DB 연결에 호출했다. 테스트 안의 연결 함수는 검증 전용이며 실행 코드·인증 우회를 추가하지 않는다.

확인한 내용:

- 고객 소유권 또는 직원 HQ_STAFF 준비 권한 검사 실패 시 A 함수를 호출하지 않는다. 실제 환불 실행 권한은 여전히 별도 확정이 필요하다.
- C 준비 결과의 ID·요청 정보가 A 함수에 전달되고 금액은 A의 기존 결제 기록에서 결정된다. C에서 PAID 기록을 확인해도 A에서 CARD 결제이면 차단한다.
- 정상 결과도 모의 금융 결과일 뿐 주문·반품 최종 완료 필드를 반환하거나 변경하지 않는다. 하위 함수는 commit/rollback하지 않는다.
- 환불 INSERT 이후 결제 UPDATE 실패는 최상위 테스트 호출자까지 전달되고 호출자 rollback이 호출된다. 이는 실제 MySQL 롤백이나 동시 요청 성공을 검증한 것이 아니다.
- 기존 금융 처리 후 PAID 결제가 없어지면 C 취소 준비 검사는 통과하지 않는다. 향후 재전송 API는 기존 업무 결과를 먼저 확인해야 한다. A 단독 중복 처리 테스트가 C 최상위 재시도 API 완성을 뜻하지 않는다.

### D 기존 함수에서 확인한 사실

`backend/features/inventory.py::release_order_inventory(db, *, order_id, reason)`는 `OrderReservationResult`를 반환한다. 기존 구현은 PENDING_PAYMENT 또는 CANCELED 주문만 허용하며 PAID 주문은 먼저 주문 담당이 취소 상태로 변경해야 한다. commit하지 않고 savepoint를 사용한다. 이미 해제된 예약을 다시 차감하지 않으며 실물 재고는 변경하지 않는다. reason은 공백 제거 후 255자 이내이다.

따라서 향후 취소 실행의 추천 순서는 인증·기존 결과 확인 → C 조건 검사 → A 모의 환불 → A 주문 CANCELED/이력 기록(아직 미커밋) → D 예약 해제 → 확정된 나머지 처리 → 최상위 commit이다. 어느 단계라도 실패하면 전체 rollback한다. 미커밋 상태 변경은 고객에게 최종 완료로 응답하지 않는다. 주문 취소 상태 전이 함수와 최상위 실행 API는 아직 구현하지 않았다.

### D에게 전달할 확인 요청

1. **취소 예약 해제:** 위 기존 함수의 동일 연결 사용, 하위 commit 없음, 잠금 순서, 이미 해제된 예약 재호출 결과 계약을 최종 확인해주세요. A가 같은 트랜잭션에서 CANCELED로 변경한 직후 호출할 계획입니다. 연결 시 C 취소 사유와 D의 255자 제한을 함께 검증해야 합니다.
2. **반품 재고 복원:** 전체 주문·APPROVED·본사 ACCEPTED 검수의 실제 반환 상품을 어느 위치에 어떤 상태로 복원할지, 호출 함수 위치·이름·인자·반환값을 공유해주세요. C는 반품 항목/수량을 검증하지만 재고 계산을 대신 구현하지 않습니다.
3. **중복·실패:** 같은 반품의 재전송/동시 요청을 어떤 기존 업무 ID·이력으로 구분하는지, 잠금 순서·부분 실패·savepoint 및 최상위 rollback 책임을 알려주세요.
4. **공통 연결:** 처리자·업무 ID·서버 시각 기록과 하위 commit 여부를 확인해주세요. 출고 예약 소비와 반품 복원은 예약 해제 함수로 대체하지 않습니다.

D 함수 호출 및 B 혜택 처리는 이번 테스트에 포함하지 않았다. 실제 DB/기기 통합, 최상위 API의 인증·응답 유실 복구·동시 요청 검증도 남아 있다.

## 21. A 주문 취소 상태 전이 — 후속 내부 구현

20절의 미구현 상태 전이 함수는 후속 작업으로 추가했다. `backend/features/order.py::mark_order_canceled_mock(db, *, order_id, customer_id, refund_id, reason)`이며 최상위 실행 API는 여전히 없다.

- B가 검증한 고객 ID와 같은 연결에서 생성/확인한 모의 환불 ID를 전달한다. 본인 주문을 잠그고 PAID 또는 재전송된 CANCELED만 허용한다.
- 같은 주문의 ORDER_CANCEL/SUCCEEDED·반품 ID null·완료 시각 존재, MOCK/REFUNDED 결제와 환불 금액 모두 주문 paid_total과 일치해야 한다. 감사 기록의 처리 고객·원래 취소 사유도 일치해야 한다.
- 배송 없음 또는 단일 PREPARING/진행 시각 없음과 D 소비 흔적 없음을 재검사한다. 이 함수는 재고를 변경하지 않는다.
- 신규 변경은 orders.order_status=CANCELED, canceled_at=CURRENT_TIMESTAMP 및 고객/사유/서버 시각의 order_status_history를 기록한다. 재전송은 기존 취소 시각과 MOCK_ORDER_CANCEL 상태 이력이 있는 경우만 기존 결과를 반환하고 이력을 중복 생성하지 않는다.
- 반환 order_id/order_status/refund_id/replayed/is_mock는 내부 미커밋 단계의 결과다. 사용자 최종 성공 응답으로 직접 사용하지 않는다.
- commit/rollback 없이 동일 연결에서 이후 D 예약 해제와 확정된 나머지 처리를 수행해야 한다. 어느 단계든 실패하면 최상위에서 전체 rollback한다. B 제외 여부가 미확정이면 최종 완료 API를 활성화하지 않는다.
- 기존 이력 컬럼과 D 사유 제한에 맞춰 사유는 공백 제거 후 255자 이내로 통일했다. `cancel_paid_order_mock`도 금융 기록 생성 전에 같은 제한을 검사한다.

신규 자동 테스트는 대체 DB로 상태/모의 금융 증거/소유권/사유/배송·소비 흔적/재전송/쓰기 실패를 검증한다. 실제 D 호출·MySQL 원자성·동시 요청·앱 통합은 검증하지 않았다. 고객 버튼과 새 라우트는 추가하지 않았다.

## 22. C 최초 취소 내부 연결 — D/B 실행 전 단계

`backend/features/order_history.py::stage_customer_order_cancel_mock(db, *, order_id, customer, request_id, reason)`를 추가했다. customer는 기존 `authenticated_customer`가 B 인증 결과로 만든 `CustomerScope`를 전달해야 한다. 타입 검사는 인증 검증을 대체하지 않는다. HTTP 라우트가 아니며 고객 입력 ID를 인증으로 사용하는 API를 만들지 않는다.

동일 연결에서 C prepare_customer_order_cancel → A cancel_paid_order_mock → A mark_order_canceled_mock 순서로 호출한다. A HTTPException은 C OrderReadError로 변환하고 다른 DB 예외는 호출자에게 전파한다. 하위 commit/rollback은 없으며 예외 뒤 최상위 호출자는 전체 rollback해야 한다.

반환값은 order_id/refund_id/is_mock=true/requires_inventory_release=true/completed=false다. D 예약 해제와 B 정책 처리가 미연결이므로 취소 완료 응답을 반환하지 않는다. DB 트랜잭션 안에서 CANCELED로 변경된 상태는 D의 다음 단계 입력 준비일 뿐이며 이 함수를 단독 commit하면 안 된다.

이 함수는 **최초 요청 단계 전용**이다. 저장된 금융 결과의 재전송 조회는 제공하지 않는다. 기존 금융 처리 뒤 PAID 결제 기록이 없으면 C 준비 검사에서 거부되므로, 향후 최상위 API는 인증·소유권 확인 후 기존 결과 조회/복구를 먼저 처리해야 한다. 이 제한을 인증 우회나 신규 결제 생성으로 해결하지 않는다.

기존 연결 테스트에 실제 C 내부 함수와 A 금융/상태 함수를 함께 호출하는 검증을 추가했다. 입력 범위, 호출 순서, D/B 미호출, 완료 아님 표시, 상태 변경 실패의 오류 변환과 최상위 rollback 호출을 확인한다. 실제 DB 롤백·응답 유실 후 전체 복구·동시 요청을 검증한 것은 아니다.

## 23. 응답 유실 후 기존 모의 취소 금융 결과 조회

`read_customer_cancel_mock_result(db, *, order_id, customer: CustomerScope)`를 C 기존 파일에 추가했다. B 검증 결과로 만든 CustomerScope만 전달해야 하며 타입 확인 자체는 인증이 아니다. 내부 읽기 전용 함수이고 HTTP 라우트·고객 버튼·자동 재시도는 연결하지 않았다.

- 본인 주문 존재를 먼저 확인한다. 타인 주문/없는 주문은 404이며 환불 목록 조회까지 진행하지 않는다.
- 해당 주문의 ORDER_CANCEL·반품 ID null·MOCK 결제 환불 기록만 읽는다. requested_at DESC, refund_id DESC로 동일 시각의 순서를 고정한다. 상태는 변경하거나 임의로 해석하지 않는다.
- 주문 ID/기존 상태/취소 시각, refunds의 ID/상태/금액/요청·완료·실패 시각을 반환한다. provider 키, idempotency 키, 내부 실패 메시지는 제외한다. 날짜·시간은 원문이다.
- `completion_confirmed=false`는 전체 완료 여부가 아직 확인되지 않았다는 내부 표시다. 금융 SUCCEEDED나 주문 CANCELED만으로 D/B 완료를 증명하지 않는다. 빈 목록도 신규 실행 허가가 아니며 진행 중 미커밋 작업을 배제하지 못한다.
- 이 함수는 작업 상태의 원자적 스냅샷/잠금 또는 요청 본문 일치 검사를 제공하지 않는다. 최상위 재시도 API에서 동일 트랜잭션 잠금 아래 기존 업무를 다시 확인해야 하며 이 조회 결과만으로 중복 처리 여부를 결정하면 안 된다.
- DB 조회 예외는 빈 결과로 감추지 않고 전파한다. commit/rollback이나 DB 변경은 하지 않는다.

대체 DB 테스트는 소유권·조회 범위·금융 상태 유지·안전한 필드·정렬 SQL·빈 결과·입력·읽기 실패를 확인한다. SQL 필터/정렬을 실제 MySQL에서 실행한 검증과 실제 응답 유실/동시 요청 검증은 아직 아니다.

### 다음 단계

현재 C/A 최초 취소 내부 단계와 기존 금융 결과 읽기가 준비됐다. 다음 실행 연결 전에는 D release_order_inventory의 최종 계약과 B 혜택 제외/연결 정책을 확정해야 한다. 그 뒤 인증 → 주문 잠금/기존 결과 재검증 → 최초 C/A 처리 또는 기존 결과 복구 → D 예약 해제 → 나머지 처리 → 단일 commit의 최상위 API를 구현하고, 실패 시 전체 rollback 및 응답 유실 재전송을 실제 DB에서 검증한다. 기존 내부 조회/단계 함수를 실행 API 완성으로 간주하지 않는다.

## 24. 혜택 미사용 주문의 모의 취소 실행 API — 후속 구현

사용자가 결제·환불을 모의 처리로 확정하고 실행 연결을 요청하여 기존 C 라우터에 `POST /api/v1/order-history/customer/{order_id}/cancel-mock`를 추가했다. 기존 문서의 실행 API 미구현 설명은 이 절의 제한된 구현으로 갱신된다. 실제 결제 사업자는 호출하지 않으며 모의 금융 기록과 실제 로컬/설정 DB의 주문·예약 상태를 변경하는 업무 API다.

- JSON 요청은 request_id(1~100자), reason(공백 제거 후 1~255자). B 인증 결과의 CustomerScope만 사용한다.
- DB autocommit이 꺼져 있어야 한다. 본인 주문 행 잠금 → 요청 완료 기록/주문 완료 기록 확인 → 혜택 미사용 확인 → 과거 미완료 환불 기록 검사 → C/A 최초 처리 → 기존 D release_order_inventory → 완료 감사 기록 → 단일 commit 순서다. 실패하면 전체 rollback한다.
- 기존 D의 동일 연결, CANCELED 허용, 하위 commit 없음 계약을 그대로 사용한다. 새 재고 규칙·테이블·공통 함수는 만들지 않는다.
- coupon_discount 또는 points_used가 0이 아니면 409로 차단한다. B 혜택 복원 없이 혜택 사용 주문을 완료하지 않는다. B 알림은 호출하지 않으며 취소 핵심 거래 완료 여부와 분리한다.
- MOCK_CANCEL_COMPLETE 감사 기록은 고객 ID·주문 ID·요청/사유·환불 ID·전체 결과를 같은 트랜잭션에서 저장한다. 동일 요청 키의 본문이 다르면 409, 같은 주문의 다른 키 재전송은 기존 완료 결과를 반환한다. 주문 잠금으로 동일 주문의 첫 처리 요청을 직렬화한다.
- 과거 일부만 저장된 환불 기록이 있으면 409로 차단하며 자동 재환불/복구하지 않는다. 기존 완료 기록 없이 금융 성공만으로 전체 취소 완료를 추정하지 않는다.
- 성공 응답 data: order_id/order_status=CANCELED/refund_id/is_mock=true/completed=true/replayed. 여기 completed는 혜택 미사용 모의 취소 거래와 D 예약 해제를 같은 트랜잭션에서 완료했다는 의미이며 실제 카드 환불이 아니다.
- 고객 버튼 연결은 이번 작업에 포함하지 않았다. 실제 MySQL 동시 요청·commit 실패 후 결과 조회·재고 반영·실제 기기 검증은 별도 필요하다. 자동 테스트는 인증/DB 및 D 호출 대체로 성공·혜택 차단·소유권·요청 충돌·재전송·과거 부분 기록·D 실패 rollback을 확인한다.
