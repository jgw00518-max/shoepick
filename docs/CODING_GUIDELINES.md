# SHOEPICK 공통 개발 기준

저장소는 apps/customer_app, apps/staff_app, backend, database, docs로 유지한다.
Flutter는 model(데이터·JSON), view(화면·입력), vm(GetxController·상태·계산·API)으로 작성한다.
기본 GetBuilder + update(), 기존 Rx는 .obs/.value/Obx를 유지한다.
같은 상태에 두 갱신 방식을 불필요하게 섞지 않는다. 등록 위치를 정하고 Get.find로 사용한다.
build에서 등록·요청을 반복하지 않는다. Repository 등 추가 계층은 임의 도입하지 않는다.
컨트롤러 자원은 onClose, 화면 자원은 dispose에서 해제하고 로그아웃 상태를 초기화한다.
파일/API 필드는 snake_case, Dart 함수·변수 lowerCamelCase, 클래스 UpperCamelCase.
이름은 영어, 설명 주석은 한국어다. 로딩·빈 결과·실패·재시도를 구분한다.
저장 완료 후 성공을 안내하고 화면을 사용하는 비동기 작업 후 mounted를 확인한다.

기존 DB/API 이름을 유지한다. 공통 모델·API·테이블 변경은 영향 담당과 합의한다.
SQL 변경은 database에 기록하고 적용 순서·이력을 관리한다. 기준 SQL을 기존 DB에 재실행하지 않는다.
실제 키·비밀번호는 Git에 올리지 않는다. 가격·재고·혜택·권한·금액은 서버가 검증한다.
관련 작은 작업 단위로 커밋하고 정상·실패·권한·중복·담당 간 연결을 검증한다.
Flutter 변경 시 해당 앱에서 dart format lib test, flutter analyze, flutter test를 실행한다.

## 확정된 업무 정책

- 결제 완료 후 출고 전 취소 가능. 출고 이후 취소 불가.
- 수령 후 구매확정 전 반품·환불 가능. 고객이 직접 구매확정하면 이후 불가. 교환 제외.
- 구매확정 상품 리뷰 작성 후 500원 적립. 중복 지급·삭제 회수 조건은 임의로 추가하지 않는다.
- 초기 재고 100개 기준 30개 미만이면 100개까지 보충 발주(27개면 73개). 보관 기한 없음.
- 최근 12개월 구매확정금액 기준 월 쿠폰: BASIC 30만원 미만 5% 1장,
  BRONZE 30~60만원 미만 5% 2장, SLIVER 60~100만원 미만 5% 2장+10% 1장,
  GOLD 100~150만원 미만 10% 2장+15% 1장, VIP 150만원 이상 10% 2장+15% 2장.
  모두 생일쿠폰 포함. SLIVER는 전달된 표기이며 실제 DB 이름은 B와 확인한다.
- 쿠폰 유효기간·생일 할인·재고 확보 시점 등 전달되지 않은 정책은 확인 후 구현한다.

## 담당과 연결

| 담당 | 영역 | 연결 |
|---|---|---|
| A | 상품·옵션·가격·제조사·주문·결제 | B 혜택, D 재고 확보·해제, 결제 후 C 출고 |
| B | 회원·직원·인증·권한·장바구니·리뷰·혜택·알림 | 공통 인증 및 혜택 함수 제공 |
| C | 구매 내역·배송·수령 인증·취소·반품·환불·문의 | A 결제, B 혜택·알림, D 재고 기능 호출 |
| D | 본사·대리점 재고·품의·결재·발주·입고·현황 | 공통 재고 기능 제공 |

교환은 제외한다. 사용자 담당은 C다. 서버 운영과 API 기능 담당은 별개다.
공통 파일 변경은 팀에 범위를 공유한다. 각 담당은 자신의 API 권한을 검사한다.
담당 간 호출 함수와 요청·응답은 합의 후 기록한다.

## API 공통 약속

현재 공통 경로는 설정 가능한 /api/v1 초안이다. 팀 승인 및 기존 API 확인 후 통일한다.
GET 조회, POST 생성·업무, PATCH 일부 수정, DELETE 삭제 가능한 데이터만 사용한다.
취소·환불은 별도 POST로 처리하고 기록을 삭제하지 않는다.
조회 조건은 query, 변경은 JSON, 이미지 업로드는 multipart/form-data다.

성공은 {"data": 값}, 작업 안내는 message 추가, 반환값 없음은 data:null.
목록 없음은 HTTP200/data:[]. 페이지 응답은 pagination:{page,page_size,total_count}.
page 기본1, page_size 기본20 최대100. 서버에서 필터·정렬 후 페이지 처리한다.
정렬 필드는 각 API에서 허용 목록으로 검증하고 SQL 문자열에 사용자 값을 직접 삽입하지 않는다.
최신 생성순을 기본으로 하고 ID로 동률을 고정한다.

오류는 {"error":{"code":"INVALID_INPUT","message":"입력값을 확인해주세요."}}.
400 INVALID_INPUT, 401 UNAUTHENTICATED, 403 FORBIDDEN, 404 NOT_FOUND,
409 INSUFFICIENT_STOCK/INVALID_STATE_TRANSITION/ALREADY_PROCESSED,
500 INTERNAL_ERROR. 앱은 code로 구분한다. 새 데이터 생성 성공은201, 나머지 성공은200.

API snake_case, Dart lowerCamelCase. ID 정수, firebase_uid 문자열, 금액 원 단위 비음수 정수,
구매 수량1 이상. null은 미선택. 기존 customer_id/product_variant_id를
member_id/product_option_id로 일괄 변경하지 않는다. 담당끼리 외부 이름·변환을 먼저 합의한다.

Authorization: Bearer <Firebase ID token>. UID는 토큰이 아니다.
verified_uid -> current_customer 또는 current_employee로 검증된 DB 사용자만 사용한다.
직원은 require_permission(B와 합의한 실제 코드), check_branch를 사용한다.
직급·업무 조건은 조회한 position/department 및 해당 업무 정책으로 추가 검사한다.
고객 조회 SQL은 반드시 인증된 customer_id로 제한한다. 요청의 회원ID·직급을 신뢰하지 않는다.
401은 앱에서 토큰 갱신 후1회 재시도, 다시 실패하면 재로그인한다.

주문 입력 최소 branch_id, items:[{product_option_id,quantity}]. 가격·최종금액은 서버 계산.
바로 구매와 장바구니 구매는 같은 주문 기능을 사용한다.
업무 상태 이름·전이 및 실제 연결 함수는 담당끼리 합의한다.
주문·결제·환불·수령·발주·입고는 DB 상태와 요청 식별자를 이용해 중복을 방지한다.
이 기반은 업무별 중복 방지를 자동 제공하지 않는다. 응답 유실 시 결과 조회 후 재시도한다.
알림 실패만 재처리하고 주문을 재생성하지 않는다.
시각은 시간대 포함 ISO8601, 날짜는 YYYY-MM-DD. 한국 시간은 제안이며 기존 UTC를 바꾸지 않는다.
