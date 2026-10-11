# C 대리점 입고·고객 수령 계약 초안

작성 기준: 2026-10-11 저장소 코드와 database/shupick_v2_structure.sql. 실제 DB와 기준 SQL의 일치는 실행 연결 전 다시 확인한다.

## 연결 전 화면 준비 최신 상태

### 사용자 앱 검증 보고

사용자가 안내한 입고·수령 준비 검증을 완료했다고 보고했다. 보고 범위는 도착 → 정상 검수 → 수령 준비 및 관련 조회 흐름이며, 개별 주문 번호·직급별 제한 계정·동시 요청·네트워크 단절 결과는 제공되지 않았다. 이를 B 수령 인증·실제 전달 완료·반품 환불 검증 완료로 확대하지 않는다.

### 수령 준비 화면 테스트 보강

`apps/staff_app/test/pickup_ready_view_test.dart`에서 검수 대기 상세 → 준비 완료 버튼 → 확인 창 → POST 및 성공 후 목록 갱신을 검증했다. 확인 취소 시 POST 없음과 상세 유지, submit이 없는 조회 전용 상세에서 실행 버튼 제외도 확인했다. 가짜 API 응답을 사용하는 위젯 테스트이며 실제 기기·로그인·서버 통신 검증은 아니다. 기존 서버 권한 검사와 VM 중복·재시도 테스트는 유지했다.

### 로컬 MySQL 트랜잭션 검증

`backend/tests/test_c_pickup_local_transaction.py`는 `SHOEPICK_LOCAL_DB_TEST=1`일 때만 실행한다. DB_HOST가 localhost/127.0.0.1/::1이 아니면 중단한다. 기존 고객·직원·대리점·상품 스냅샷을 참조한 검증용 주문·배송을 한 트랜잭션에 만들고 실제 도착 → 검수 → D 보관/C·A 수령 준비 → 수령 목록 조회를 검사한다. 마지막에 전체 rollback하고 검증 주문이 남지 않았는지 확인한다. 기존 주문·재고는 수정하지 않는다. 자동 증가 ID는 rollback 후에도 소비될 수 있다.

실제 로컬 MySQL에서 통과했다. 테스트 연결 래퍼는 업무 함수의 commit을 억제한다. 따라서 실제 SQL·제약·동일 연결의 함수 연동 검사이며 실제 commit 성공·Firebase 인증·직원 역할 매핑·동시 요청·앱 버튼 검증은 아니다. 실행 코드에 인증 우회는 추가하지 않았다. 공용 DB에는 실행하지 않는다.

### 직원 수령 준비 버튼 연결

PickupCandidatesView의 검수 대기 상세에서 INSPECTING·inspected_at이 있는 배송에 수령 준비 완료 버튼을 연결했다. 기존 대리점 실행용 submit이 전달된 경우에만 제공하며 실제 권한·대리점 검사는 서버가 수행한다. 직원의 전체 상품 보관 준비 확인 후 기존 ready API에 request_id·confirmed를 전달한다. 성공 시 검수 대기 목록을 갱신한다. 고객 수령 대기 메뉴에서 준비된 주문을 조회할 수 있으나 인증·실제 전달 완료는 여전히 별도다.

PickupCandidatesVm은 연속 클릭을 막고 VM 수명 동안 배송별 요청 키를 보존하여 응답 유실 재시도에 재사용한다. 정상 완료 응답의 배송 ID·주문 상태·completed를 확인하고 종료 후 응답은 무시한다. 앱 재시작 후 키 보존은 없으므로 서버의 배송별 완료 기록도 재처리를 방지한다. 아래 직원 버튼 미연결 설명은 이전 기록이며 이 절로 대체한다. 실제 DB·기기 검증은 수행하지 않았다.

### D 최소 보관 함수 및 최상위 수령 준비 API 연결

사용자 승인으로 D `inventory.py::prepare_pickup_holdings(db, order_id=..., fulfillment_id=..., branch_id=...)`를 최소 추가했다. SHIPPING·INSPECTING 및 실제 출고·도착·검수 시각, 전체 주문 배송 수량·대리점을 검사한다. 항목별 보관 기록을 READY_FOR_PICKUP으로 생성하거나 기존 AWAITING_ARRIVAL/INSPECTING을 갱신한다. 이미 준비된 동일 기록은 재사용하고 불일치는 차단한다. 고객 주문 보관이므로 판매 재고·예약 수량을 다시 증가시키지 않는다. 하위 함수는 savepoint를 사용하며 commit하지 않는다.

POST `/api/v1/order-history/staff/fulfillments/{fulfillment_id}/ready`에 `request_id`, `confirmed: true`를 전달한다. 검증된 대리점 직원·점장의 활성 소속만 허용한다. 주문→배송 잠금과 완료 감사 기록 확인 후 D 보관 → C 기록 및 A 전이 → 감사 기록 → 단일 commit 순서로 실행한다. 실패 시 전체 rollback한다. 같은 요청 내용 충돌은 ALREADY_PROCESSED이며 완료 재전송은 재고·이력을 추가하지 않는다. 보관 기한은 설정하지 않는다.

기존 라우터를 사용하며 main.py 변경은 없다. API는 연결됐지만 직원 버튼은 아직 미연결이다. 수령 준비 완료는 인증·전달 완료가 아니다. B 인증·이메일 알림·혜택을 추가하지 않았다. 아래 D 함수 없음·최상위 API 미구현 설명은 이전 시점 기록이며 이 절로 대체한다. 자동 테스트는 가짜 DB 검사이고 실제 MySQL 동시 요청·DB 영속 rollback·기기 검증은 별도다.

### B 연동 제외 우선 검증

도착·정상 검수 테스트에 요청 키 내용 충돌 차단, 재전송 시 추가 쓰기 방지, 감사 기록 저장 실패 및 commit 예외 시 rollback 호출 검증을 보강했다. 취소·출고·도착·정상 검수·수령 준비 관련 테스트 68개가 통과했다. 의존성 대체·가짜 DB 검증이며 실제 MySQL의 동시 실행, 네트워크 단절 후 commit 여부, 영속 데이터 복구를 증명하지 않는다.

D의 대리점 보관 처리 함수는 현재 코드에 없다. 따라서 수령 가능 최상위 API·직원 실행 버튼은 연결하지 않았다. 후속 순서는 D 동일 연결·중간 commit 없는 보관 계약 확인 → C/A 수령 가능 API와 중복 처리 → 직원 버튼 → 로컬 DB 통합 검증이다. B 수령 인증·알림·혜택 연동은 대기하고 기존 인증·권한 검사는 유지한다.

### C 수령 준비 기록·A 연결 내부 함수

`record_staff_pickup_ready(db, fulfillment_id=..., employee=...)`는 사전 검사 후 C 배송을 READY_FOR_PICKUP으로 기록하고 주문 단위 pickups를 생성하거나 PREPARING 기록을 갱신한다. 도착 시각은 배송 기록, 준비 시각은 DB CURRENT_TIMESTAMP를 사용한다. 기존 배송·수령 이력에 직원과 주문·배송·수령 ID를 남기고 A의 `transition_pickup_order(..., completed=False)`로 연결한다. 보관 기한·재고·수령 인증·구매확정은 변경하지 않는다.

내부 함수이며 HTTP API나 화면 버튼은 연결하지 않았다. 동일 연결에서 D 보관 처리 후 호출해야 한다. commit/rollback과 완료 요청 재전송 판별은 최상위 C 실행 API 책임이다. 실패는 호출자에게 전파하며 부분 변경을 commit하면 안 된다. 최초 처리만 지원하고 완료 재전송은 최상위 API에서 먼저 확인해야 한다. D 함수와 실제 잠금 순서 계약이 아직 없어 실제 수령 가능 처리는 활성화하지 않는다.

### C 수령 가능 전이 사전 검사 함수

`backend/features/order_history.py::prepare_staff_pickup_ready(db, fulfillment_id=..., employee=...)`를 추가했다. HTTP API가 아닌 내부 검사 함수이며 변경·commit·rollback을 하지 않는다. 호출자는 같은 연결의 트랜잭션을 유지하고 오류 시 전체 rollback해야 한다.

검증된 대리점 직원·점장과 활성 소속, SHIPPING 주문·INSPECTING 배송, 실제 출고·도착·검수 시각, 전체 주문과 배송 항목 수량을 검사한다. D 처리 후 항목별 pickup_holdings가 같은 대리점·수량의 READY_FOR_PICKUP이고 received_at·ready_at이 존재하며 전달 전인지 확인한다. 통과 시 order_id·fulfillment_id·branch_id·employee_id를 반환한다. DB 시각은 해석하거나 변환하지 않는다.

보관 기록을 C에서 생성하거나 D 처리 성공으로 간주하지 않는다. 실제 최상위 ready API는 아직 없다. 향후 D의 동일 연결·commit 없는 보관 함수 → 이 검사 → C 배송/수령 기록과 이력 → A transition_pickup_order → 최상위 단일 commit 순서로 연결한다. D의 잠금 순서를 확인한 후 실행 연결하며 실패 시 모든 변경을 rollback한다. B 수령 인증·알림은 이번 범위에서 추가하지 않는다.

### 정상 검수 기록 저장 — D 보관 연결과 분리

POST `/api/v1/order-history/staff/fulfillments/{fulfillment_id}/inspection`에 `request_id`, `all_items_normal: true`를 전달한다. 검증된 BRANCH_STAFF·BRANCH_MANAGER의 활성 소속 대리점만 실행한다. SHIPPING 주문의 ARRIVED 배송에 실제 출고·도착 시각이 있고 전체 주문 항목 ID·수량이 배송과 일치할 때만 INSPECTING 및 inspected_at을 저장한다. 직원은 실제 전체 상품·옵션·수량·정상 상태 확인 후 실행한다. 파손·부족은 이 정상 검수 API로 처리하지 않는다.

INSPECTING은 정상 검수 관찰 저장 후 D 보관 연결 대기 상태이며 READY_FOR_PICKUP이나 고객 수령 가능을 뜻하지 않는다. 주문·재고·수령 기록은 변경하지 않는다. 기존 배송 상태 이력과 audit_logs에 직원·주문·배송·서버 시각·요청 식별자를 기록하고 한 번 commit, 오류 시 rollback한다. 주문→배송 잠금으로 재전송을 직렬화하며 같은 요청·배송의 완료 기록은 재사용한다.

검수 대기 목록·상세에는 ARRIVED와 INSPECTING 모두 남긴다. 화면은 ARRIVED에서만 정상 검수 저장을 제공하고 INSPECTING은 검수 기록 완료·보관 연결 대기로 표시한다. D의 보관 함수 계약 후 별도 수령 가능 처리를 연결한다. 이 절이 아래의 이전 ‘정상 검수 저장 미구현’ 기록을 대체한다. 실제 DB·기기·동시 요청 검증은 별도다.

- 직원 입고 화면에서 `도착 전 / 검수 대기`를 전환한다. 검수 대기는 기존 목록 API의 `stage=inspection`과 `inspection-candidates/{fulfillment_id}` 상세 API를 사용한다.
- 단계 전환 시 목록·상세·페이지를 초기화하고 이전 요청의 늦은 응답을 폐기한다. 도착 시각은 응답 문자열 그대로 표시한다.
- 검수 대기에서는 도착 확인을 다시 실행하지 않는다. 정상 검수 저장과 D 재고 보관 연결은 아직 미구현이며 성공한 것으로 표시하지 않는다.

### 도착 후 검수 대기 조회 준비

기존 GET /staff/arrival-candidates에 stage=inspection을 추가했다. 기본 stage=arrival은 기존 도착 전 조회를 유지한다. inspection은 SHIPPING 주문, ARRIVED 배송, 실제 출고·도착 시각 존재, 검수/완료 시각 없음, 주문 수령 대리점 일치를 조회한다. arrived_at DESC/fulfillment_id DESC로 정렬 후 페이지 처리하고 기존 HQ 전체/활성 소속 대리점 조회 권한을 재사용한다.

GET /staff/inspection-candidates/{fulfillment_id}는 같은 상태 조건과 소속을 다시 확인하고 기존 배송 항목의 주문 스냅샷을 반환한다. 실제 검수 저장·D 보관·수령 가능 상태 변경은 하지 않는다. 다음 작업은 직원 화면에서 도착 전/검수 대기를 구분하는 조회 연결이며 정상 검수 실행은 D 보관 함수 계약 후 진행한다.

### 실제 도착 확인 후속 연결

POST /api/v1/order-history/staff/fulfillments/{fulfillment_id}/arrival은 request_id/received_product=true를 받아 B 검증 BRANCH_STAFF/BRANCH_MANAGER의 활성 소속 대리점만 허용한다. SHIPPING/IN_TRANSIT 배송의 실제 도착 확인 후 ARRIVED/arrived_at, 직원 상태 이력과 완료 감사 기록을 저장한다. 같은 요청 재전송은 기존 결과를 반환하고 실패 시 전체 rollback한다. 주문 상태·재고·수령 기록은 변경하지 않는다.

PickupCandidatesView/VM에 실제 도착 확인 창과 POST 호출을 연결했다. dashboard_page.dart는 기존 인증 POST 함수 전달에 필요한 최소 부분만 변경했다. 수령 메뉴·본사 조회 화면에서는 도착 실행을 제공하지 않는다. 연속 클릭 방지, 배송별 동일 요청 키 재시도, 성공 후 목록 갱신 및 종료 후 응답 무시를 제공한다. 키는 VM 수명 동안만 유지한다.

도착 확인은 정상 검수·D 보관·READY_FOR_PICKUP과 구분한다. 기존 입고 대상 목록에서 도착 처리된 배송은 제외되므로 이후 검수 대기 조회도 필요하다. D 보관 함수와 정상 검수 실행은 아직 미연결이며 실제 DB·앱 통합은 검증하지 않았다.

### A/C 입고·수령 상태 계약 확정 및 연결 준비

사용자는 A의 기존 틀에서 꼭 필요한 A/C 연결 코드를 함께 수정하고 조건·계약을 추천대로 확정하도록 위임했다. B의 혜택/알림/수령 인증 구현은 계속 미루며 기존 동작하는 B 인증 의존성은 유지한다. D 처리는 구현을 기다린다.

- 입고/전달 실행 역할은 BRANCH_STAFF 또는 BRANCH_MANAGER의 활성 소속 대리점으로 확정한다. HQ_STAFF의 전체 조회를 전달 실행 권한으로 확대하지 않는다.
- 정상 입고·전체 상품 검수와 D 보관 처리 후 SHIPPING → READY_FOR_PICKUP. 실제 수령 인증·전체 상품 전달과 D 처리 후 READY_FOR_PICKUP → COMPLETED. 실제 도착 기록만으로 수령 가능/수령 완료로 변경하지 않는다.
- A order.py에 mark_order_ready_for_pickup / mark_order_received 추가. 공통 인자 db, order_id, fulfillment_id, pickup_id, branch_id, employee_id. C order_history.py::transition_pickup_order가 B 검증 직급·소속을 검사해 A 함수로 연결한다. 라우트가 아닌 내부 함수다.
- A 함수는 주문 → 배송 → 수령 기록을 잠그고 세 기록의 주문·대리점 일치 및 필요한 실제 시각을 검사한다. 입고 전이에는 배송/수령 모두 READY_FOR_PICKUP, shipped_at/arrived_at/inspected_at/ready_at 존재, completed_at/picked_up_at 없음이 필요하다. 수령 전이에는 둘 다 COMPLETED이고 전달 완료 시각이 필요하다.
- 정상 첫 전이만 orders 및 order_status_history를 기록한다. change_source는 STAFF_ARRIVAL/STAFF_PICKUP, 실제 직원 ID·연결 배송/수령 ID를 기록한다. 같은 최종 상태와 동일한 기록으로 재호출하면 replayed=true로 상태/이력을 반복 변경하지 않는다. 다른 상태·기록 불일치는 차단한다.
- A 함수는 purchase_confirmed_at을 변경하지 않는다. 재고·인증·배송/수령 기록 생성은 수행하지 않으며 commit/rollback도 없다. D 처리와 실제 인증 성공을 위 기록의 존재만으로 증명하지 않는다. 최상위 C가 실제 처리·중복 요청·전체 rollback을 보장한 뒤 호출해야 한다.
- 기존 DB 시각은 그대로 사용하고 새로운 시간대/기한을 도입하지 않는다. 실제 입고 세부 단계·D 처리 단위는 D 연결 시 맞춘다. 아직 입고/전달 POST·실행 버튼은 활성화하지 않는다.
- B 수령 인증을 생략한 전달 완료 기능은 만들지 않는다. 이메일·바코드 또는 대체 검증 방식의 별도 계약 전까지 실제 전달 실행은 대기한다.

- 입고·수령 목록과 상품 상세는 기존 실제 조회 API로 연결되어 있다. 화면 VM은 initState에서 한 번 시작하고 dispose에서 종료한다. build에서 새 컨트롤러를 반복 생성하지 않는다.
- 대시보드 직급·대리점 키 변경 시 이전 VM을 종료하여 이전 목록·늦은 응답을 제거한다. 상세를 닫은 후 늦은 응답도 폐기한다.
- 상세에서 도착 수량·상품 정보 확인과 미연결 안내를 제공한다. 입고 및 수령 인증·완료 실행 버튼은 비활성이며 POST·재고·상태 변경은 없다.
- 수령 번호는 이메일·바코드 제공 예정이지만 주문 번호만으로 인증 완료를 주장하지 않는다. B의 인증 수단·검증·재사용 방지 계약이 필요하다.
- 실행 전 확인이 필요한 제안은 아래 문서의 권한·입고 전이·처리 단위다. 실제 입고/전달 함수는 D의 보관·재고 계약 및 A 상태 전이와 함께 연결한다. 미확정 실행 정책을 화면 준비로 확정한 것으로 해석하지 않는다.

## 1. 확정 사항과 문서 범위

- 기존 C_DISPATCH_CONTRACT.md와 사용자 합의가 우선한다. 본사 출고는 HQ_STAFF, 고객이 선택한 orders.pickup_branch_id가 수령 대리점이다. 대리점 직원·점장은 이후 입고·수령 업무 담당이다.
- 결제 완료 → 출고 → 수령 → 고객이 직접 구매확정한다. 출고 후 취소 불가, 수령 후 구매확정 전만 반품·환불 가능하다. 수령 완료를 구매확정으로 자동 처리하지 않는다.
- 보관 기한은 정하지 않는다. 기존 정책 테이블·기본값 때문에 14일 기한·자동 회수·자동 구매확정을 적용하지 않는다.
- A 주문·결제, B 인증·혜택·알림, D 재고 기능을 사용한다. 교환은 제외한다.
- UUID 배송 번호·DB CURRENT_TIMESTAMP 및 시간대 변환 없음은 기존 승인 계약이다. 업무 시각에 앱 시각을 사용하지 않는다.
- 아래 API·세부 상태 전이·수령 인증 방식은 별도 승인 전까지 제안이다.

## 2. 확인된 구조와 현재 연결

| 위치 | 확인한 내용 | 현재 제한 |
|---|---|---|
| backend/features/authentication.py | current_customer: Firebase UID로 삭제되지 않은 고객; current_employee: 활성 직원과 역할·권한·활성 소속 branches | 각 C 실행 API가 업무 범위를 검사해야 함 |
| 같은 파일 require_permission / check_branch | 실제 코드 권한, 활성 소속 대리점 검사 | 입고·수령 전용 코드 미확인. HQ 예외를 자동 추가하지 않음 |
| backend/features/inventory.py | list_branch_inventory: pickup_holdings와 배송 항목·주문 스냅샷 조회 | 수량은 기록 수량이며 현재 보관 수량 총합으로 간주하면 안 됨 |
| 같은 파일 reserve_order_inventory / release_order_inventory | 주문 예약·해제, 하위 함수 commit 없음 | 대리점 입고·고객 전달 처리 함수 없음. release를 출고/전달로 사용하지 않음 |
| backend/features/c_dispatch.py | 전체 주문 배송 준비 생성·재사용 | 실제 출고 POST/D 소비 연결 없음 |
| backend/features/order.py | 주문 결제·상세 및 mark_order_shipping 준비 | READY_FOR_PICKUP/수령 완료 전이 함수 없음 |
| apps/staff_app/lib/vm/staff_order_api.dart | MockStaffOrderRepository.verifyPickup / completePickup / markArrived | 네트워크 없음. 주문 번호를 코드로 비교하고 메모리 상태 변경 |
| apps/staff_app/lib/view/staff_pages.dart | 입고·수령 코드 확인·전달 완료 화면 존재 | 위 목업 동작. 화면 문구의 픽업 결제 코드는 실제 결제 인증이 아님 |
| apps/customer_app/lib/view/order_history_detail.dart | 배송 상태·송장·시각 읽기 표시 | 실제 수령 인증 수단 없음 |

목업 markArrived의 주문 IN_TRANSIT 조건·completePickup의 주문 COMPLETED 변경을 실제 계약으로 복사하지 않는다. 주문 상태와 배송 상태는 별개이며 현재 출고 주문 상태 계약은 SHIPPING이다.

## 3. 기존 테이블

| 테이블 | 기존 필드·제약 | 책임 연결 |
|---|---|---|
| orders | order_id, customer_id, pickup_branch_id, order_status, purchase_confirmed_at | A 승인 상태 전이만 사용 |
| fulfillments | fulfillment_id/number, order_id, destination_branch_id, fulfillment_status, shipped_at/arrived_at/inspected_at/completed_at | C 배송 처리 |
| fulfillment_items | fulfillment_id, order_id, order_item_id, quantity | 전체 주문 배송 항목 기준 |
| pickup_holdings | fulfillment_item_id 유일, branch_id, quantity, holding_status, received_at/ready_at/picked_up_at | D 보관 기록 처리와 협의 |
| pickups | order_id 유일, branch_id, handled_by_employee_id, pickup_status, arrived_at/ready_at/picked_up_at | C 주문 단위 수령 기록 |
| fulfillment_status_history / pickup_status_history / order_status_history | 이전·다음 상태, 처리 출처·이유·직원/고객·DB 시각 | C/A 각 상태 변경 기록 |
| inventory_movements / audit_logs | D 재고 변동 및 업무 요청 식별자·처리자 기록 | 새 스키마를 임의로 도입하지 않음 |
| pickup_retention_policies / pickup_reminders | 기존 보관 기한·주간/회수 알림 구조 | 존재만 확인. 현재 기한 없음 정책에 자동 적용하지 않음 |

pickups 허용 상태: PREPARING / READY_FOR_PICKUP / COMPLETED / CANCELED. 별도 ARRIVED/INSPECTING 상태를 pickups에 새로 넣지 않는다.
pickup_holdings 허용 상태: AWAITING_ARRIVAL / INSPECTING / READY_FOR_PICKUP / PICKED_UP / RECALLING / RETURNED_TO_HQ / DAMAGED / CANCELED.
fulfillments는 IN_TRANSIT / ARRIVED / INSPECTING / READY_FOR_PICKUP / COMPLETED 등을 허용한다. DB 허용값이 업무 전이를 자동 확정하지는 않는다.
기준 SQL pickups에는 수령 인증 코드·해시·사용 여부 컬럼이 없다. 새 인증 테이블·컬럼을 임의로 추가하지 않는다.

## 4. 권한 제안 — 승인 필요

- 입고·검수·전달 실행: BRANCH_STAFF 또는 BRANCH_MANAGER이고 B의 활성 소속 branches에 대상 대리점이 포함되어야 한다.
- orders.pickup_branch_id = fulfillments.destination_branch_id = pickups.branch_id = 보관 기록 branch_id 일치를 서버에서 검사한다. 불일치 기록은 자동 수정하지 않는다.
- HQ_STAFF 전체 진행 조회는 제안 가능하지만 대리점 전달 실행까지 자동 확대하지 않는다. 기존 출고 조회 권한과 후속 입고 권한은 구분한다.
- 고객은 토큰으로 식별한 본인 주문의 수령 상태·인증 정보만 조회한다. 앱의 customer_id·role·branch_id를 권한 근거로 쓰지 않는다.
- 다중 역할 테스트 계정의 화면 직급 선택만으로 단일 역할 차단 검증을 완료했다고 주장하지 않는다.

## 5. 처리 흐름 제안 — 승인 필요

1. 대리점 실제 도착 확인: 전체 배송 항목·수량과 대리점 일치를 검사한다. fulfillments IN_TRANSIT → ARRIVED, arrived_at 기록. D가 항목별 보관 기록의 received_at·보관 상태를 처리한다.
2. 정상 검수 완료: 필요하면 ARRIVED → INSPECTING 단계를 기록하고 전체 정상 수량 확인 후 READY_FOR_PICKUP. inspected_at 기록. D 보관 READY_FOR_PICKUP/ready_at, pickups READY_FOR_PICKUP/ready_at, A 주문 READY_FOR_PICKUP 전이 연결.
3. 수령 인증 확인: 서버가 본인 주문과 현재 수령 가능 상태·대리점을 확인한다. 인증 확인만으로 재고·주문 상태를 변경하지 않는다.
4. 직원 실제 전달 확인: 전체 주문 한 번 전달. C 배송·pickups COMPLETED와 완료 시각, D 보관 PICKED_UP/picked_up_at 처리. A 수령 완료 상태 전이 계약을 호출한다.
5. 구매확정은 고객의 별도 동작이다. purchase_confirmed_at은 수령 완료 단계에서 변경하지 않는다.

첫 구현은 부분 입고·부분 수령·재출고를 지원하지 않는 방향을 제안한다. 파손·부족은 성공으로 처리하지 말고 실제 정책 합의 전 별도 차단·안내한다. ARRIVED/INSPECTING을 별도 버튼으로 둘지 정상 입고 확인 한 번으로 기록할지는 결정 필요하다.
orders.COMPLETED를 수령 완료로 사용할지는 미확정이다. 목업처럼 자동 적용하지 않는다. 반품·환불 조건이 수령 완료와 구매확정을 구분할 수 있어야 한다.

## 6. API 제안 — 구현·확정 아님

기존 C APIRouter 경로를 유지한다. 실제 이름은 관련 담당과 합의 후 적용한다.

| 용도 | 경로·메서드 제안 | 입력·출력 |
|---|---|---|
| 입고 대상 | GET /api/v1/order-history/staff/arrival-candidates | page/page_size/branch_id; data와 pagination |
| 도착 확인 | POST /api/v1/order-history/staff/fulfillments/{fulfillment_id}/arrival | JSON request_id; 배송 상태·arrived_at |
| 정상 검수 | POST /api/v1/order-history/staff/fulfillments/{fulfillment_id}/ready | JSON request_id; 수령 가능 상태·ready_at |
| 고객 수령 상태 | GET /api/v1/order-history/customer/{order_id}/pickup | 본인 주문만; pickup_id/branch_id/pickup_status/ready_at/picked_up_at |
| 수령 인증 확인 | POST /api/v1/order-history/staff/pickups/verify | 인증 수단 합의 후 본문 정의; 변경 없이 확인 결과 |
| 실제 전달 | POST /api/v1/order-history/staff/pickups/{pickup_id}/complete | JSON request_id 및 인증 증명 합의 후; 완료 결과 |

Authorization: Bearer Firebase ID token. API 필드 snake_case, ID int, 빈 선택 null, 목록 없음 []. 성공 data/message, 오류 error.code/message. 인증 값은 URL·로그에 넣지 않는다. 조회는 200, 완료 업무는 200을 제안한다.

## 7. 수령 인증 추천과 선택 사항

추천은 고객의 인증된 화면에서 서버가 제공하는 일회성 수령 증명을 직원이 확인하고, 실제 전달을 별도 확인하는 방식이다. 다만 현재 스키마에는 일회성 코드 저장 구조가 없어 B와 코드/서명 토큰 제공·사용 결과 기록 계약이 필요하다.
단순 주문 번호는 식별 정보이며 비밀 인증 수단으로 간주하지 않는다. 기존 목업처럼 번호 입력만으로 전달 완료를 허용하지 않는다.
QR/숫자 코드/서명 토큰 중 방식, 재발급·만료·시도 제한·대리 수령 허용 여부는 미확정이다. 보관 기한 없음과 보안 인증의 유효기간은 별개이며 임의의 기간을 정하지 않는다.

## 8. 중복·트랜잭션·실패

- 최상위 C가 같은 MySQL 연결로 A 상태, D 보관/재고, C 배송·수령·이력을 묶어 한 번 commit한다. 하위 함수는 commit하지 않는다. 실패 시 전체 rollback.
- 주문 → 배송 → 수령/보관 → 재고 순서의 잠금을 제안하되 D 함수의 실제 잠금 순서와 맞춰 확정한다.
- 동일 요청 재전송은 기존 완료 결과 반환, 다른 내용의 같은 식별자는 ALREADY_PROCESSED. 현재 상태와 항목별 이력을 검사하고 이미 전달한 수량을 다시 변경하지 않는다.
- 응답 유실 시 먼저 기존 결과를 조회한다. audit_logs.request_id는 고유 제약이 없으므로 행 잠금·현재 상태·D idempotency_key를 함께 사용한다.
- 입고/전달 처리자·서버 시각·이전/다음 상태·배송/주문/수령 ID를 기존 이력에 기록한다. 인증 코드·토큰은 이력에 넣지 않는다.
- B 알림은 commit 후 별도 처리. 실패해도 입고·전달을 다시 실행하지 않는다. 실패 기록 위치와 재시도 계약은 B 제공 기능 확인 후 정한다.

## 9. 오류와 테스트

401 UNAUTHENTICATED, 403 FORBIDDEN, 404 NOT_FOUND, 400 INVALID_INPUT, 409 INVALID_STATE_TRANSITION/ALREADY_PROCESSED, 500 INTERNAL_ERROR를 사용한다. 재고 부족 오류는 D가 제공하는 공통 코드로 처리한다.
자동 테스트: 고객 본인/타인, 직급·소속 범위, 배송-주문-대리점 불일치, 준비/이미 완료 상태, 전체 수량 불일치, 중복 요청, 오류·재시도·페이지·종료 후 응답.
로컬 DB 통합 테스트: 실제 동시 요청, A/D 단계별 실패 rollback, 응답 유실 후 완료 결과 조회. 실제 기기: 고객 인증 정보 표시·직원 확인·물품 전달 후 상태 반영. 가짜 DB 테스트를 실제 잠금 검증으로 표현하지 않는다.

## 10. 담당별 확인 질문

- A: SHIPPING → READY_FOR_PICKUP → 수령 완료의 주문 상태명·하위 함수? 수령 완료와 고객 구매확정 구분? 동일 연결/commit 없음/이력 계약?
- B: 입고·전달 권한 코드가 필요한가? 수령 인증은 코드/QR/서명 토큰 중 무엇으로 제공할 것인가? 소유자·재발급·사용 완료·만료·대리 수령·알림 실패 재처리 계약?
- D: pickup_holdings 생성 시점과 소유 함수? 대리점 입고·고객 전달 시 어떤 보관/재고 수량을 변경하는가? 일반 판매 재고와 고객 주문 보관을 구분하는가? 잠금·중복·commit 없음 계약?
- C/팀: 별도 도착/검수 단계 여부, 첫 버전 전체 입고·전체 수령만 허용할지, 파손·부족 처리, 직원 소속만 실행·본사 조회 범위, 수령 인증 방법을 확정해야 한다.

## 수령 완료·구매확정 분리 — 사용자 위임 2026-10-11

- 현재 orders CHECK 제약을 유지한다. COMPLETED는 실제 수령 완료, purchase_confirmed_at NULL은 구매 미확정, 값이 있으면 고객 구매확정이다. 새로운 RECEIVED/CONFIRMED 상태값이나 DB 컬럼은 추가하지 않는다.
- 고객 표시: COMPLETED + NULL → 수령 완료, COMPLETED + 시각 → 구매확정. 원본 order_status는 유지하고 시각은 변환하지 않는다.
- 고객 직접 POST /api/v1/order-history/customer/{order_id}/purchase-confirmation. B 검증 고객 소유 주문을 잠그고 COMPLETED와 동일 대리점의 pickups.COMPLETED/picked_up_at을 검사한다. 시각을 DB CURRENT_TIMESTAMP로 저장하고 PURCHASE_CONFIRM 감사 기록을 남긴다. 재전송은 기존 결과를 반환한다.
- 직원 실제 수령 완료 처리는 향후 B 인증 확인·D 보관 처리와 같은 트랜잭션에서 orders.COMPLETED, pickups.COMPLETED/picked_up_at 및 배송 완료를 함께 기록한다. 이 단계에서 purchase_confirmed_at은 변경하지 않는다.
- 기존 COMPLETED 데이터가 실제 수령과 일치하는지는 팀이 확인해야 한다. 기존 데이터를 자동 수정하지 않으며 실제 수령 기록이 없는 주문은 구매확정 API에서 차단한다.
- A/B/C 공통 반품·환불은 실제 수령 완료이며 purchase_confirmed_at IS NULL일 때만 허용해야 한다. B 리뷰는 purchase_confirmed_at이 있는 주문 항목만 허용해야 한다. 해당 담당 API는 이번에 수정하지 않으며 이 기준 전달이 필요하다.
- 수령 인증은 이메일 방식으로 예정됐지만 B 연결은 대기한다. 주문 번호를 인증 비밀로 취급하지 않는다. 기존 수령 실행 화면은 아직 목업이고 활성화하지 않는다.

## 입고 대상·수령 대기 읽기 연결 — 2026-10-11

- 기존 C APIRouter에서 GET /api/v1/order-history/staff/arrival-candidates 및 /staff/pickup-candidates를 제공한다. page/page_size/branch_id, data/pagination 규칙 유지.
- 입고 대상: orders.SHIPPING, fulfillments.IN_TRANSIT, shipped_at 존재·arrived_at 없음, 목적 대리점=주문 수령 대리점. 전체 배송 기록을 자동 수정하거나 입고 처리하지 않는다.
- 수령 대기: orders.READY_FOR_PICKUP, pickups.READY_FOR_PICKUP, ready_at 존재·picked_up_at 없음, 수령 기록 대리점=주문 수령 대리점. 목록 존재만으로 인증·전달 완료를 허용하지 않는다.
- 조회 권한은 기존 C 출고 조회와 동일한 B 검증 역할 범위를 재사용한다: HQ_STAFF 전체, BRANCH_STAFF/BRANCH_MANAGER 활성 소속 지점, 그 외 차단. 이는 읽기 범위이며 실행 권한을 확대하지 않는다.
- 서버에서 대리점·상태 필터 후 시각 DESC, 해당 기록 ID DESC로 정렬·페이지 처리한다.
- 직원 로그인 세션의 Dashboard 입고·수령 메뉴만 연결한다. 인증 요청이 없는 목업 모드는 기존 목업 화면을 유지한다. 새 조회 화면은 로딩/빈 결과/오류/재시도/페이지와 실행 준비 중 표시를 제공한다.
- D 재고, B 수령 인증, 입고·수령 완료 POST는 아직 연결하지 않는다. 실제 DB와 기기 통합 검증은 별도이며 자동 테스트만으로 전체 처리 완료라고 주장하지 않는다.

## 입고·수령 상품 상세 조회 — 2026-10-11

- GET /api/v1/order-history/staff/arrival-candidates/{fulfillment_id}: 목록과 같은 현재 상태 조건을 검사하고 배송 항목 수량과 주문 당시 상품 스냅샷을 반환한다.
- GET /api/v1/order-history/staff/pickup-candidates/{pickup_id}: 수령 대기 상태·대리점 일치를 검사하고 전체 주문 항목을 반환한다.
- 상세에서 B 직원 역할·활성 소속을 다시 검사한다. 소속 외·없는 기록·현재 대상 상태가 아닌 기록은 동일 404 NOT_FOUND로 처리한다.
- 입고의 quantity는 fulfillment_items 수량, 수령의 quantity는 order_items 수량이다. unit_price/line_total은 주문 당시 값이며 배송 금액을 새로 계산하지 않는다.
- 상세 창에서 상품명·코드·색상·사이즈·수량·단가·주문 항목 금액을 표시한다. 중복 창·중복 조회 방지, 로딩·오류·재시도, 닫힘/종료 후 늦은 결과 무시를 적용한다.
- 입고·전달 변경 API, 인증 코드, 재고 변경은 추가하지 않는다.
