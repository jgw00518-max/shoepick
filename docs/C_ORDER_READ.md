# C 초기 조회 구현 및 인계

## 완료 범위

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

직원 API는 인증·범위 검사 후 현재 503 / INTERNAL_ERROR를 반환한다. 화면에는 출고 조회 연동 준비 중 상태를 표시한다. 실제 출고 조회 성공이나 빈 목록을 의미하지 않는다.

A에게 공통 조회 함수의 파일·import·함수명·DB 인자·반환값을 받는다. 결제 완료 기준은 orders.order_status=PAID 및 payments.payment_status=PAID 기록 존재이며 PREPARING 주문은 제외한다.
A 함수 연결 시 C에서 실제 출고 기록 제외 조건, 소속 대리점 필터, 정렬·페이지 처리를 적용한다. A의 결제 규칙을 중복 작성하지 않는다. 출고 기록 상태와 분할 출고 기준은 확인 후 적용한다.

## 실행 및 검증

각 앱에서 flutter run --dart-define=API_BASE_URL=http://서버주소:8000 으로 API 주소를 전달한다. MySQL 주소와 API 서버 주소는 별도 설정이다.

백엔드: python -m pytest backend/tests -q
각 변경 Flutter 앱: dart format lib test, flutter analyze, flutter test

실제 기기 로그인·고객 주문 표시와 A 연결 후 출고 목록 정상·실패·권한 검증은 별도로 수행한다.
DB 저장 시간대를 확인하기 전 임의 변환하지 않는다. 고객 시각은 DB 값의 ISO 문자열이며 현재 화면에 시각을 표시하지 않는다.
취소·반품·환불·수령·구매확정 처리는 이번 초기 조회 범위에 포함하지 않는다. 교환은 제외한다.
