# C 초기 조회 구현 및 인계

## 완료 범위

### 연결 전 C 작업 점검 — 2026-10-11

최신 A/C 작업 권한: 사용자가 A의 기존 구조에서 필요한 연결 부분도 최소 수정하도록 위임했다. 조건·계약은 추천안으로 확정할 수 있다. A 전체 기능을 재작성하거나 B/D 업무 규칙을 대신 구현하지 않는다. 기존 파일/함수가 충분하면 변경하지 않는다.

A/C 입고·수령 주문 전이도 준비됐다: order.py::mark_order_ready_for_pickup / mark_order_received, C::transition_pickup_order. 대리점 직원·점장의 실제 소속을 검사하며 D/B 처리가 필요한 최상위 실행 API는 여전히 대기한다. 최신 계약은 C_PICKUP_CONTRACT의 A/C 확정 절을 따른다.

| 순서 | 독립적으로 완료한 것 | 실제 실행 연결이 남은 것 |
|---|---|---|
| 출고 | 실제 대상 조회·확인 창, 전체 주문 배송 준비 생성/재사용 함수, A SHIPPING 연결 함수, 관련 자동 테스트 | D 출고 소비 함수 및 동일 연결 트랜잭션·중복 결과 확인 후 최상위 POST |
| 입고·수령 | 실제 대상/상세 조회, 소속 범위 검사, VM 종료·지점 변경 처리, 실행 준비 안내 | 입고 상태 전이·처리 단위 확정, D 보관 처리, A READY_FOR_PICKUP/COMPLETED 전이, B 이메일·바코드 인증 |
| 취소 | 본인/PAID/출고 흔적/소비 기록 검사 준비 함수·비활성 안내·테스트 | A 결제 취소·환불, D 예약 해제, B 혜택 복원, 전체 트랜잭션과 결과 복구 |
| 반품·환불 | 고객 접수·직원 목록/상세·검수·최종 결정·고객 결과 표시, A 환불 호출 인자 준비, 응답 유실/중복/늦은 응답 테스트 | A 실제 환불·D 정상/불량 재고·B 혜택/알림, 실제 결과 확인 후 업무 완료 |

준비 함수에는 commit/rollback이 없으며 단독 호출 후 잠금을 방치하지 않는다. HTTP 실행 API로 공개하지 않은 함수를 실제 처리 기능으로 세지 않는다. C의 준비 코드를 사용하려면 호출자가 B 검증 정보와 최상위 트랜잭션을 보장해야 한다.

담당에게 받을 파일·함수명·인자·반환값·중간 commit 여부·잠금 순서·중복/오류/복구 계약을 기록하고 연결한다. 구체적인 요청은 C_DISPATCH_CONTRACT / C_PICKUP_CONTRACT / C_AFTER_SALES_CONTRACT 문서를 따른다.

실제 통합 검증 순서: 로컬 DB 대상 확인 → 고객 로그인/본인 주문 조회 → 모의 결제 주문 출고 조회 → 직원 출고 → 소속 대리점 입고/수령 인증/실물 전달 → 구매확정 또는 취소/반품 경로 → 실패/동시 요청/응답 유실 확인. 아직 연결되지 않은 실행은 수행하거나 통과했다고 주장하지 않는다. 다중 역할 계정만으로 단일 역할 거부 검증을 완료하지 않는다.

자동 테스트는 Firebase/DB 의존성을 대체한다. 실제 인증 토큰·MySQL 동시 잠금·외부 결제 원자성·기기 검증은 별도다. 고객 앱 기존 widget_test의 홈/설정/카테고리 3개 실패는 C에서 다른 담당 업무를 바꿔 해결하지 않는다.

이번 연결 전 점검 결과: C 백엔드 test_c_*.py 및 test_order_history.py 184개 통과, 직원 앱 전체 62개 통과, 고객 앱 28개 통과/기존 widget_test 3개 실패. 두 앱 dart format lib test 실행 후 C 밖 포맷 변경은 복원했고 flutter analyze는 문제없다. DB/외부 Firebase를 변경하는 검증은 수행하지 않았다. 조회/접수/검수/결정 통과와 실제 출고·입고·취소·환불 성공을 구분한다.

고객 구매 내역·상세 API와 화면은 B의 current_customer로 확인한 customer_id를 사용한다. 다른 고객 주문 상세는 404이다. 실제 Firebase 로그인 환경에 연결하고 기존 목업 경로는 유지한다.

직원 출고 조회는 current_employee로 인증한다. HQ_STAFF는 전체, BRANCH_STAFF·BRANCH_MANAGER는 소속 대리점만 허용한다. 나머지 직급은 거부한다. 화면에서 직급을 선택해도 서버 권한은 변경되지 않는다.

직원 화면은 실제 로그인 환경의 본사 배송 메뉴와 대리점 출고 대상 조회 메뉴에 연결한다. 로딩·빈 결과·오류·재시도·페이지 이동을 처리한다. 화면 종료 또는 직급·대리점 변경 시 컨트롤러를 정리하고 늦게 도착한 응답을 무시한다.

## 파일 위치

- backend/features/order_history.py: 고객 조회 SQL, 인증 어댑터, 직원 범위 검사.
- backend/tests/test_order_history.py: 소유자·인증·입력·직급·대리점 검사.
- 고객 lib/model/order_history.dart, lib/vm/order_history_vm.dart, lib/view/order_history_view.dart.
- 직원 lib/model/dispatch_order.dart, lib/vm/dispatch_vm.dart, lib/view/dispatch_view.dart.
- 기존 메뉴 연결: 고객 presentation/store_shell.dart, 직원 view/staff_app.dart, view/dashboard_page.dart, model/staff_views.dart.
- 직원 vm/auth_api.dart: getResponse(path)로 목록·페이지 전체 응답 제공. 기존 get(path)는 유지.
- 직원 pubspec.yaml: 팀 규칙의 GetBuilder 상태 관리를 위한 get 패키지 추가.
- backend/main.py: C 라우터 등록.

DB 구조·공용 데이터는 변경하지 않는다.

## API

GET /api/v1/order-history/customer?page=1&page_size=20
GET /api/v1/order-history/customer/{order_id}
GET /api/v1/order-history/staff/dispatch?page=1&page_size=20&branch_id=3

Bearer Firebase ID 토큰을 전달한다. branch_id는 필터이며 권한 근거가 아니다. 소속 외 대리점 요청은 403이다.
목록은 data와 pagination(page/page_size/total_count)을 사용한다. 기본20건, 최대100건이다.
직원 화면에 필요한 주문 필드는 order_id, order_number, branch_name, paid_total이다.

## 남은 A 연결

2026-10-11 사용자 확인 후 A의 get_paid_orders(db=db)를 재사용하여 직원 조회를 실제 연결했다. 기존 503 대기 응답은 더 이상 사용하지 않는다.

조회 범위는 고객이 선택한 orders.pickup_branch_id를 기준으로 한다. 본사 사원은 전체, 대리점 직원·점장은 활성 소속 지점만 조회한다.
임시 안전 기준: 배송 기록이 없거나 모든 기록이 PREPARING이고 shipped_at이 없을 때만 표시한다. 일부 출고·취소·알 수 없는 상태·상태와 시각 불일치는 제외한다. 후속 팀 계약이 생기면 이 기준을 수정한다.
필터를 적용한 뒤 A의 ordered_at DESC, order_id DESC 순서를 유지하여 페이지를 처리한다. A 함수가 전체 결제 완료 주문을 읽으므로 현재 소규모 초기 구현에 맞는 방식이다. 목록이 커지면 A가 DB 필터·페이지 인자를 제공하도록 계약을 확장해야 한다.

A에게 공통 조회 함수의 파일·import·함수명·DB 인자·반환값을 받는다. 결제 완료 기준은 orders.order_status=PAID 및 payments.payment_status=PAID 기록 존재이며 PREPARING 주문은 제외한다.
A의 결제 규칙은 C에서 중복 작성하지 않는다. 부분 출고 잔량·재출고 처리와 실제 출고 확인 실행은 별도 계약 대기다.

## 실행 및 검증

각 앱에서 flutter run --dart-define=API_BASE_URL=http://서버주소:8000 으로 API 주소를 전달한다. MySQL 주소와 API 서버 주소는 별도 설정이다.

백엔드: python -m pytest backend/tests -q
각 변경 Flutter 앱: dart format lib test, flutter analyze, flutter test

실제 기기 로그인·고객 주문 표시와 A 연결 후 출고 목록 정상·실패·권한 검증은 별도로 수행한다.
DB 저장 시간대를 확인하기 전 임의 변환하지 않는다. 상세 화면의 배송 기록 시각은 DB 값의 ISO 문자열을 시간대 변환 없이 서버 원문으로 표시한다.
취소·반품·환불·수령·구매확정 처리는 이번 초기 조회 범위에 포함하지 않는다. 교환은 제외한다.

## 2026-10-11 통합 검증

A의 실제 주문 생성·모의 결제 API를 로컬 DB에서 호출한 뒤 C 고객 목록·상세에 테스트 주문 86이 일치함을 확인했다. 옵션 3 수량1의 재고 예약과 결제 기록은 동일 요청 재전송에도 한 번만 반영됐다. 테스트 기록은 삭제하지 않았다.
토큰 검증은 테스트 의존성으로 대체했으며 실제 기기 통합 성공을 뜻하지 않는다. 당시 503 대기였던 직원 조회는 이후 위 사용자 확인 기준으로 연결했다.
