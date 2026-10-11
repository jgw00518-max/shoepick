# C 직원 출고 확인 API 계약

## 확정 계약 — 사용자 승인 2026-10-11

이 절은 아래 과거 초안의 동일 항목보다 우선한다. 업무 정책은 확정되었지만 A/B/D 연결 함수와 기존 권한 코드의 실제 제공 여부는 별도 확인한다. 없다고 C가 해당 업무를 중복 구현하지 않는다.

- 첫 구현은 **주문 전체 한 번 출고**이다. 부분 출고·재출고는 지원하지 않는다. 여러 배송 기록, 부분 출고 또는 취소된 배송 기록이 있으면 자동 진행하지 않는다.
- 고객이 선택한 orders.pickup_branch_id가 목적 대리점이다.
- 출고 조회: HQ_STAFF 전체, BRANCH_STAFF·BRANCH_MANAGER 활성 소속 대리점만. 그 외 직급 거부.
- 출고 실행: **본사에서 출고하며 HQ_STAFF만 허용**한다. 대리점 직원·점장은 조회 및 이후 입고·수령 업무를 담당한다. 팀장·이사·임원 역할만으로는 출고 실행을 허용하지 않는다.
- 출고 가능 조건: 주문 PAID, 같은 주문의 PAID 결제 기록 존재, 실제 출고 기록 없음, 전체 수량의 유효한 예약 존재. 취소와 동시 처리되지 않도록 주문 행 잠금을 공유한다.
- 직원 실제 출고 확인 후 orders.order_status는 PAID → SHIPPING, fulfillments.fulfillment_status는 PREPARING → IN_TRANSIT로 변경한다. shipped_at은 서버에서 기록한다.
- 배송 기록이 없으면 첫 확인 트랜잭션에서 C가 기존 fulfillments·fulfillment_items에 생성한다. 이미 준비 기록이 하나 있으면 주문 항목·수량·목적 대리점이 일치할 때만 재사용한다. fulfillment_number 생성 규칙은 기존 팀 규칙을 확인한다.
- D가 전체 주문의 예약 소비·본사 실물 및 예약 수량 차감·재고 이력을 같은 연결로 처리한다. 예약 해제를 소비 대신 호출하지 않는다. 대리점 재고를 도착 전에 임의로 증가시키지 않으며 후속 입고 연결은 D와 확인한다.
- D 함수는 commit하지 않는다. C 최상위 함수가 주문·배송·재고·이력 변경 완료 후 한 번 commit하고 실패하면 전체 rollback한다. A의 허용 상태 변경 계약을 따른다.
- 동일 확인 재전송은 기존 완료 결과를 반환하며 다시 차감하지 않는다. 이미 완료된 기록에 다른 출고 내용 요청은 409 / ALREADY_PROCESSED이다. 요청 식별자만으로 중복 방지가 된다고 가정하지 않는다.
- 출고 성공 후 외부 알림 실패는 완료된 출고를 유지하고 알림만 재처리한다. 기존 기록 위치와 B 알림 함수가 없으면 별도 계약을 받아 연결한다.
- 실행 경로: POST /api/v1/order-history/staff/orders/{order_id}/dispatch. Bearer 토큰과 JSON request_id를 사용한다. 운송장 필요·필수 여부와 서버 시간대는 미확정이며 임의 적용하지 않는다.
- 성공 응답: data에 order_id, fulfillment_id, order_status, fulfillment_status, shipped_at, message에 한국어 완료 안내. 새 DB 컬럼·추가 계층을 임의 도입하지 않는다.
- 취소·반품·환불·수령·구매확정 실행과 교환은 이번 구현 범위 밖이다.

### 구현 순서와 연결 준비 사항

1. A의 주문 잠금·허용 상태 변경과 D 출고 소비 함수의 파일·인자·반환값·중복 계약을 받는다. B에는 기존 출고 권한 코드 여부를 확인한다. HQ_STAFF 실행 정책은 위 승인으로 확정됐으며 코드 이름은 임의 생성하지 않는다.
2. C 화면의 출고 확인 창과 실행 상태·결과 모델, 비활성·로딩·실패·재시도 테스트를 준비한다. 실제 호출 미연결이면 명시하고 활성화하지 않는다.
3. 동일 DB 연결의 C POST API를 구현한다. 서버 권한·소속·상태·배송 항목 일치·중복 검사와 기록을 적용하고 A/D 함수로 연결한다. main.py는 기존 C 라우터 등록을 유지한다.
4. C 화면을 연결하여 성공 후 출고 목록을 갱신한다. 응답 유실은 먼저 기존 완료 상태를 조회하고 재시도한다.
5. 가짜 의존성 테스트 후 로컬 DB에서 정상·권한·재전송·동시 요청·단계별 rollback을 검증한다. 실제 기기 검증을 구분하고 변경 Flutter 앱의 format/analyze/test를 실행한다.

## 아래는 이전 검토 기록

작성 기준: 2026-10-10 로컬 코드와 `database/shupick_v2_structure.sql`.
문서만 작성한다. 실행 코드·DB 구조·데이터는 변경하지 않았다.
이 문서의 **제안**은 팀 승인 전 구현 계약이 아니다. 실사용 DB가 기준 SQL과 같은지는 구현 전에 다시 확인한다.
기존 조회 진행 현황은 [C_ORDER_READ.md](C_ORDER_READ.md)를 참고한다.

### 최신 조회 연결 결정 — 2026-10-11

사용자가 A 코드 재사용, 고객 수령 대리점 기준, 임시 안전 기준 적용을 승인했다. C는 get_paid_orders(db=db)를 읽기 전용으로 호출한다. 직접 호출 시 Depends 기본값에 의존하지 않고 DB 연결을 명시한다. A/B/D 코드는 수정하지 않는다.
직원 범위는 orders.pickup_branch_id를 따른다. 배송 기록 없음 또는 모든 배송이 PREPARING이고 shipped_at 없음인 주문만 표시한다. 일부 출고·CANCELED·미지 상태·시각 불일치 기록은 우선 제외한다. 팀의 후속 구현 계약이 생기면 기준을 대체한다.
아래 이전 초안의 503·미연동 표현은 연결 이전 기록이며 현재 직원 조회는 200 목록 응답이다. 실제 출고 확인 POST의 권한·상태·D 소비 함수 계약은 여전히 미확정이다.
현재 A 함수는 전체 결제 완료 목록을 반환하므로 C는 서버 메모리에서 소속·배송 필터 후 A 정렬을 유지해 페이지 처리한다. 대량 주문에서는 A 조회 계약을 DB 필터·페이지 방식으로 확장해야 한다.

### 2026-10-11 연결 전 재확인

- 최신 A 버전에 주문 생성 create_order 및 30분 결제 대기 만료 처리 cancel_expired_order가 추가되어 있다. 이 기간은 A 코드의 현재 값이며 C 정책으로 새로 확정한 것이 아니다.
- get_paid_orders는 명시적 db 인자를 넘기면 읽기 함수로 호출 가능하고 commit하지 않는다. 다만 전체 목록을 반환하므로 대용량 처리·대리점 필터·출고 제외·페이지 계약은 A와 별도로 확인해야 한다. C 라우터는 답변 전 503을 유지한다.
- D의 출고 소비 함수, 실행 permission_code, 주문 상태 전이, 배송 생성·분할·시간 기준은 여전히 미확정이다. 출고 확인 POST는 아직 구현하지 않는다.
- 로컬 DB에서 테스트 주문 86을 A API로 생성·모의 결제하고 C 고객 목록·상세의 주문·금액·옵션·수량·대리점 일치를 검증했다. 동일 주문·결제 재전송에서도 주문 ID와 결제 기록은 중복되지 않았고 예약 수량은 1만 증가했다.
- 이 검증은 TestClient에서 토큰 검증 의존성만 테스트 계정 UID로 대체했다. 실제 Firebase 토큰 전송·기기 화면·직원 출고 성공 검증을 의미하지 않는다. 주문 86과 관련 테스트 기록은 로컬 DB에 남겨 두었다.

## 1. 현재 구현과 연결 지점 — 확인된 사실

| 담당 | 파일·함수 | 현재 제공 범위 |
|---|---|---|
| A | `backend/features/order.py`의 `get_paid_orders(db: Connection = Depends(get_db)) -> PaidOrderListResponse` | GET `/api/v1/orders/paid`에 해당하는 라우트 함수. 결제 완료 주문 목록 반환. 전용 공통 조회 함수 분리는 없음 |
| A | 같은 파일의 `get_order_detail`, `pay_order_mock` | 주문 상세와 모의 결제. 결제 성공 시 payments·orders·order_status_history 변경 후 자체 commit |
| B | `backend/features/authentication.py`의 `current_employee` | Firebase 검증 UID로 활성 직원 조회. employee_id·roles·permissions·활성 소속 branches 반환 |
| B | `require_permission(permission_code)`, `check_branch(employee, branch_id)` | 기존 권한 코드 검사와 소속 대리점 검사. check_branch 자체에는 본사 예외 없음 |
| D | `backend/features/inventory.py`의 `reserve_order_inventory(db, *, order_id, expires_at)` | 주문 품목 수량 예약. 같은 연결 사용, 자체 commit 없음 |
| D | 같은 파일의 `release_order_inventory(db, *, order_id, reason)` | 결제 대기·취소 주문 예약 해제. 출고 후 변경 차단. 자체 commit 없음 |
| C | `backend/features/order_history.py`의 `authorized_dispatch`, `dispatch_orders` | 조회 직급·대리점 검사 완료. 실제 출고 목록은 503 / INTERNAL_ERROR로 대기 |

A 목록 필드: order_id, order_number, order_status, pickup_branch_id, branch_name, paid_total, ordered_at, paid_at.
A 조회에는 출고 기록 검사·직원 범위·페이지 처리가 없다. 그대로 직원 공개 API로 사용하지 않는다.
D 공개 함수 중 출고 예약 소비·실물 차감 함수는 현재 없다. release를 출고 차감 대신 호출하지 않는다.

## 2. 출고 대상 조회 조건

**확정:** orders.order_status = PAID 및 같은 주문의 payments.payment_status = PAID 기록 존재. 주문 상태 PREPARING은 제외한다. 여러 결제 기록이 있어도 주문은 한 번만 반환한다.

**구조상 확인:** fulfillments는 주문당 여러 행이 가능하다. shipped_at과 fulfillment_status가 있으며 fulfillment_items가 주문 항목·수량을 연결한다. 주문의 PREPARING과 배송 기록의 PREPARING은 다른 상태다.

**포함·제외 제안:** 출고 기록이 없거나 PREPARING 기록만 있고 shipped_at이 없으면 후보로 포함한다. 실제 출고된 기록은 제외한다. D의 현재 출고 후 예약 변경 차단은 shipped_at 존재 또는 IN_TRANSIT/ARRIVED/INSPECTING/READY_FOR_PICKUP/RECALLING/RETURNED_TO_HQ/COMPLETED 기록 존재를 검사한다. 이것은 D의 기존 보호 조건이며 C 최종 목록 계약으로 자동 확정하지 않는다.

**합의 필요:** 분할 출고에서 일부만 출고한 주문의 남은 항목 처리, CANCELED 배송 기록의 재출고, 배송 기록 없는 주문의 생성 시점, 조회 대리점의 기준(pickup_branch_id 또는 destination_branch_id). 조회 시 필터·정렬 후 페이지 처리하며 ordered_at DESC, order_id DESC를 제안한다.

## 3. 조회 권한 — 확정

- HQ_STAFF: 전체 대리점 조회.
- BRANCH_STAFF·BRANCH_MANAGER: 활성 소속 대리점만 조회.
- 그 외 직급: 출고 조회 불가. 여러 역할 중 HQ_STAFF가 있으면 기존 C 어댑터는 전체 범위를 허용한다.
- 요청 branch_id는 필터일 뿐 권한 근거가 아니다. 앱의 직급 선택도 권한을 변경하지 않는다.

**출고 실행 권한은 별도 합의 필요.** 조회가 가능하다는 이유로 실물 출고까지 허용하지 않는다. 사용할 실제 permission_code, 본사와 대리점의 실행 업무 범위를 B/C/D가 확정한다. 새 권한 코드를 이 문서에서 생성하지 않는다.

## 4. 출고 확인 API — 미승인 제안

```text
POST /api/v1/order-history/staff/dispatch/{fulfillment_id}/confirm
Authorization: Bearer <Firebase ID token>
Content-Type: application/json
```

배송 기록이 먼저 존재한다는 전제의 제안이다. 기록 없는 주문의 출고 준비 생성 API는 별도 합의한다. order_id 중심 경로와 어느 것을 선택할지도 확정해야 한다.

요청 예시(새 API 계약 제안이며 새 DB 컬럼을 뜻하지 않음):

```json
{"request_id":"동일 업무 재시도에 유지할 식별자"}
```

처리자·역할·완료 시각·변경할 상태는 앱이 보내지 않고 서버가 결정한다. 운송장 입력이 필요하면 기존 tracking_number를 사용할지 별도 합의한다.

성공 예시:

```json
{
  "data": {
    "order_id": 101,
    "fulfillment_id": 12,
    "fulfillment_status": "IN_TRANSIT",
    "shipped_at": "2026-10-10T15:30:00+09:00"
  },
  "message": "출고 확인이 완료되었습니다."
}
```

IN_TRANSIT는 기존 DB 허용 값이지만 출고 직후 상태로 사용할지는 미확정이다. 예시의 +09:00도 확정된 DB 시간대가 아니다. DB·서버 시간 기준 확인 후 직렬화한다. 주문 PAID → SHIPPING 변경 시점도 A와 합의한다. POST 업무 성공은 200, 처음 배송 준비 기록을 생성하는 별도 API는 201을 제안한다.

## 5. 처리 전 검사

1. B의 current_employee로 토큰·활성 직원·서버 역할을 확인한다.
2. 합의한 출고 실행 권한과 업무 대리점 범위를 검사한다. 본사 예외는 명시적으로 처리한다.
3. 잠근 배송 기록과 주문의 연결, 배송 항목이 해당 주문의 항목인지 확인한다.
4. A의 공통 기준으로 결제 완료·허용 주문 상태를 확인한다. 출고된 기록과 요청 재처리 여부를 먼저 확인한다.
5. D 함수로 예약 상태·실제 출고 가능 수량을 검증한다. 고객 요청 수량·금액을 그대로 신뢰하지 않는다.
6. 실제 물품 출고를 직원이 확인한 경우에만 완료를 기록한다. 이 확인은 외부 운송사 배송 완료를 뜻하지 않는다.

## 6. 중복·재전송·동시 요청 — 제안

앱은 처리 중 버튼을 비활성화한다. 서버는 같은 주문의 변경을 orders 행 잠금으로 직렬화하고 배송·재고 행도 일관된 순서로 잠근다. 잠금 순서는 A/D와 통일한다.
동일한 확인의 재전송은 저장된 상태·이력으로 기존 결과를 돌려주는 200을 우선 제안한다. 다른 요청이 충돌하면 409 / ALREADY_PROCESSED 또는 INVALID_STATE_TRANSITION으로 구분한다. 반환 정책은 합의한다.
응답이 유실되면 기록 조회 후 재시도하며 새 배송·재고 이동을 생성하지 않는다.
audit_logs.request_id에는 유일성 제약이 없으므로 이것만으로 중복 방지가 된다고 가정하지 않는다. 기존 배송 상태 잠금·D의 idempotency_key를 어떻게 연결할지 합의하고, 새 테이블은 임의로 추가하지 않는다.

## 7. 기존 기록 구조

| 테이블 | 활용할 기존 필드·역할 |
|---|---|
| orders | order_id, order_status, pickup_branch_id. 상태 변경은 A가 승인한 전이만 수행 |
| payments | order_id, payment_status, paid_at. C는 출고 때문에 결제 기록을 수정하지 않음 |
| fulfillments | fulfillment_id/number, order_id, destination_branch_id, fulfillment_status, tracking_number, shipped_at/arrived_at/completed_at |
| fulfillment_items | fulfillment_id, order_id, order_item_id, quantity. 분할 가능 구조이며 주문 단위 전출고 정책은 미확정 |
| fulfillment_status_history | fulfillment_id, previous_status, new_status, change_source, change_reason, actor_type, actor_employee_id, changed_at |
| order_status_history | order_id, previous_status, new_status, change_source, change_reason, actor_type, actor_employee_id, changed_at |
| inventory_movements | 옵션별 증감·후속 수량, reference_type/id, idempotency_key, created_by_employee_id, created_at. D 소유 |
| audit_logs | 처리자, action_code, entity_type/id, before_data/after_data, request_id, created_at. 요청 ID 고유 제약 없음 |

직원 이력은 actor_type=EMPLOYEE와 검증된 employee_id를 사용한다. change_source/action_code/reference_type 값은 기존 사용값을 확인해 합의한다. 업무 시각은 서버·DB가 기록한다. 비밀번호·토큰·SQL·비밀 키를 로그에 저장하지 않는다.

## 8. 트랜잭션과 외부 실패 — 제안

단일 요청의 배송 상태·출고 시각·허용 주문 상태·D 재고 소비·관련 이력은 같은 MySQL 연결과 트랜잭션 안에서 함께 성공해야 한다. 최상위 C 실행 함수가 마지막 한 번 commit하고 실패하면 전체 rollback한다.
D의 기존 확보·해제는 자체 commit하지 않고 savepoint를 사용한다. 출고용 함수도 같은 방식의 계약이 필요하다. A의 pay_order_mock은 자체 commit하므로 출고 트랜잭션 내부에서 결제 함수로 호출하지 않는다.
운송사 등록·B 알림 같은 외부 작업은 DB 완료 후 별도 처리한다. 실패를 기록하고 해당 작업만 재시도한다. 성공한 출고를 알림 실패 때문에 재생성하거나 되돌리지 않는다. 외부 실패 기록 위치·재시도 주체·결과 확인 방법은 합의 전 임의 구현하지 않는다.

## 9. A/D 연결과 정책 경계

A가 분리한 결제 완료 조회·검사 함수를 사용하고 C는 직원 범위·출고 기록을 적용한다. 함수명·인자·반환값·같은 연결 사용 계약을 받기 전 새 이름을 확정하지 않는다.
D가 예약 소비·실물 출고 변경을 제공한다. C가 직접 본사 재고를 차감하거나 release를 소비로 대체하지 않는다. 예약·실물·불량 수량·재고 이력은 D가 관리한다.
D의 reserve_order_inventory는 DB 기준 naive expires_at을 필수로 요구한다. 팀의 '보관 기한 없음'이 예약 만료에도 적용되는지, 현재 구현의 만료 입력을 어떻게 정할지 A/D에게 확인한다. C가 임의 기간을 넣지 않는다.
혜택·알림은 B, 결제 실행·환불은 A, 재고는 D 기능을 사용한다. 교환은 제외한다.

## 10. 오류·검증 시나리오

| 상황 | 제안 또는 공통 응답 |
|---|---|
| 잘못된 ID·본문 | 400 / INVALID_INPUT |
| 토큰 없음·무효 | 401 / UNAUTHENTICATED |
| 비활성 직원·권한 없음·소속 외 접근 | 403 / FORBIDDEN |
| 없는 주문·배송 | 404 / NOT_FOUND. 소속 외 대상 은닉 정책은 B와 합의 |
| 미결제·불허 전이 | 409 / INVALID_STATE_TRANSITION |
| D 수량 부족 | 409 / INSUFFICIENT_STOCK |
| 중복 충돌 | 409 / ALREADY_PROCESSED. 동일 재시도 성공 재반환 정책은 위 제안 참고 |
| 내부 실패 | 500 / INTERNAL_ERROR. 내부 예외 노출 금지 |
| 현재 미연동 조회 | 기존 503 / INTERNAL_ERROR 유지. 실행 API 완료를 의미하지 않음 |

error.code로 구분하고 message는 짧은 한국어를 사용한다. 정상 확인, 각 권한 범위, 동일 요청 재전송, 서로 다른 동시 확인, 취소와 출고 동시 요청, DB 단계별 실패 rollback, 응답 유실 후 조회, 알림 실패 후 중복 출고 방지를 검증한다.
분할 출고·CANCELED 기록 재처리는 정책 합의 후 시나리오를 확정한다. 현재 조회 단위·화면 테스트 통과는 이 실행 API의 통합 검증이 아니다.

## 11. 담당별 전달 질문

- **A:** get_paid_orders를 재사용 함수로 분리할 파일·함수·인자·반환값은? 출고 직후 주문 상태와 변경 허용 함수는? 분할 출고에서 주문 전체 상태는 언제 변경하는가? C가 조회할 대리점 기준은?
- **B:** 출고 실행에 사용할 기존 permission_code와 허용 직급은? 비활성·소속 변경을 처리 시 다시 확인할 방법은? 본사 전체 실행 허용 여부와 알림 함수·실패 재처리 계약은?
- **D:** 출고 예약 소비 함수는 어떻게 제공하는가? 실제 수량 차감과 이력의 동일 트랜잭션·잠금 순서·중복 키 계약은? 예약 만료와 보관 기한 없음 정책의 관계는? 분할 출고 잔량 처리 방식은?
- **C 및 관련 담당 공동:** 주문·배송 상태 전이, 기존 기록 없는 주문의 준비 생성, 실행 단위(주문/배송), 운송장 필수 여부, 서버 시간대, 동일 재시도 응답과 외부 실패 기록 위치를 확정한다.

## D 구현 대기 중 C 화면 준비 — 2026-10-11

- 직원 출고 목록의 `출고 내용 확인` 버튼에서 주문 번호·수령 대리점·결제 금액을 확인한다. 표시값은 현재 C 조회 응답만 사용한다.
- 주문 전체를 한 번에 출고한다는 안내와 확인 체크를 제공한다. 상품별 내역은 현재 목록 응답에 없으므로 임의로 표시하지 않는다.
- 실제 실행 연결 전에는 `출고 실행 준비 중` 버튼을 비활성화한다. 이 창은 실행 권한을 부여하지 않으며 POST 요청·주문 상태·재고 변경을 하지 않는다.
- 중복 창 열기를 막고, 창을 닫으면 확인 체크를 폐기한다. 화면 종료 뒤에는 화면 상태를 갱신하지 않는다.
- 다음 연결 조건: A 상태 변경 함수, D 출고 소비 함수, B 실행 권한 코드 적용 계약, 배송 번호 생성 및 서버 시각 기준 확인. 연결 이후 서버가 HQ_STAFF 실행 권한을 검사한다.
- 현재는 실행 결과 모델·요청 식별자·재시도 실행을 추가하지 않는다. 실제 함수의 반환 계약과 처리 결과 조회 방법이 준비된 뒤 연결하여 가짜 성공과 무조건 재전송을 방지한다.

## A 상태 변경 연결 준비 — 사용자 위임 2026-10-11

사용자가 A 연결 계약을 이 작업에서 정하고 진행하도록 위임했다. 다음은 로컬 구현된 계약이며 A 팀원에게 병합 전 공유·검토한다. D 소비 함수는 계속 대기하며 실제 출고 POST는 활성화하지 않는다.

- A 파일 backend/features/order.py에 mark_order_shipping(db, *, order_id, fulfillment_id, employee_id) 추가. 기존 함수와 공개 라우트는 변경하지 않는다.
- C 연결 함수 backend/features/order_history.py의 transition_dispatched_order(db, *, order_id, fulfillment_id, employee). B 검증 직원 정보에서 HQ_STAFF와 employee_id를 확인하고 A 오류를 C 공통 오류로 변환한다.
- A는 주문 잠금, PAID 상태, PAID 결제 기록, 동일 주문·수령 대리점의 IN_TRANSIT 배송과 shipped_at 존재를 검사한다. PAID → SHIPPING과 order_status_history를 기록하고 order_id/order_status/fulfillment_id dict를 반환한다.
- 이력 change_source=STAFF_DISPATCH, actor_type=EMPLOYEE, 인증 직원 ID를 사용한다. 기존 varchar 필드에 기록하며 스키마를 변경하지 않는다.
- 호출 순서: C의 인증/중복/주문 잠금 → 배송 준비 검증 → D 재고 소비 → C 배송 IN_TRANSIT와 출고 시각 기록 → C 연결 함수를 통해 A 상태 변경 → 최상위 C commit. 중간 실패는 최상위에서 전체 rollback한다.
- A 함수는 commit/rollback하지 않는다. 같은 연결을 필수로 사용하며 배송 존재만으로 D 재고 소비를 증명한다고 간주하지 않는다. D 호출 성공은 최상위 C가 보장한다.
- 이미 SHIPPING인 주문을 A 함수에 재호출하면 409 INVALID_STATE_TRANSITION. 동일 업무 재전송은 C가 먼저 저장된 배송·처리 결과를 확인하고 반환하여 이 함수를 다시 호출하지 않는다.
- 아직 남은 것: D 소비 함수·잠금 순서, 배송 번호 생성, 서버 시간 기준, 실행 권한 코드 적용 여부, 실제 최상위 POST 구현·통합 검증. 현재 조회 화면과 비활성 실행 버튼은 유지한다.

## C 배송 준비 함수 — 2026-10-11

- 파일: backend/features/c_dispatch.py. 기존 order_history.py가 문의·주문 조회를 포함하므로 배송 준비 검증만 C 전용 features 파일로 최소 분리했다. 새 라우터·추가 계층은 없다.
- prepare_order_fulfillment(db, *, order_id, employee, fulfillment_number) → fulfillment_id / fulfillment_number / created dict.
- 직원 정보는 B 인증 결과이며 HQ_STAFF만 허용한다. 주문을 먼저 잠그고 PAID·PAID 결제·수령 대리점·양수 주문 항목을 검사한다.
- 배송 없음: 전체 항목의 fulfillments/fulfillment_items와 PREPARING 이력 생성. 배송 한 건: PREPARING·동일 대리점·진행 시각 없음·전체 항목/수량 일치일 때 번호를 유지해 재사용. 여러 기록·취소·출고 흔적·부분 수량은 차단한다.
- 함수는 commit/rollback하지 않는다. 호출자는 실패 시 배송 항목을 포함한 전체 변경을 rollback한다. 아직 최상위 출고 POST는 없으며 준비만 독립 commit하는 공개 API도 추가하지 않는다.
- 기존 생성·이력 시각은 DB CURRENT_TIMESTAMP 기본값을 사용하며 시간대는 변환하지 않는다. 실제 shipped_at 기록과 시간 기준은 출고 실행 연결 전 별도 확인한다.
- 배송 번호 UUID 32자리 제안은 사용자 확인 대기다. 현재 함수는 번호를 인자로 받으며 자체 생성 규칙을 확정하지 않는다.
- 별도 권한 코드는 만들지 않고 승인된 HQ_STAFF 역할을 검사한다. B의 코드가 제공되면 적용 범위를 협의한다.
- 자동 테스트는 생성·재사용·불일치·권한·실패 후 commit 없음과 SQL 잠금 구문을 검증한다. 실제 동시 요청 직렬화·전체 rollback은 가짜 DB 테스트만으로 검증 완료했다고 주장하지 않는다. D 함수와 최상위 실행 계약을 받은 후 로컬 MySQL 통합 테스트로 확인한다.

### 배송 번호·시각·권한 확정 — 사용자 승인 2026-10-11

위의 배송 번호 확인 대기 항목을 다음으로 대체한다.
- prepare_order_fulfillment(db, *, order_id, employee): 새 배송 기록 생성 직전에 uuid4().hex로 32자리 번호를 생성한다. 번호를 요청이나 호출 인자로 받지 않는다. 기존 준비 기록 재사용 시 번호는 유지한다.
- 생성·이력 시각은 기존 DB CURRENT_TIMESTAMP 기본값을 사용하며 시간대를 임의로 변환하지 않는다. 실제 출고 시각도 DB 기준으로 기록하도록 최상위 실행에서 연결한다.
- 실행 역할은 HQ_STAFF이며 별도 권한 코드를 새로 만들지 않는다. 향후 B 공통 권한 코드가 제공되면 관련 담당과 적용을 협의한다.
- D 연결 전에는 실제 출고 POST·독립적인 준비 생성 API를 제공하지 않는다.

### develop 494ba80 확인 — 2026-10-11

D의 제조사 인수/입고 자동 처리와 직원 대시보드 변경을 가져왔다. 제조사에서 본사로 들어오는 goods_receipts 업무와 고객 주문의 fulfillments 출고는 서로 다른 업무다. 이번 변경을 고객 주문 출고 재고 소비 함수로 재사용하지 않는다.

현재 inventory.py에는 주문 reserve_order_inventory/release_order_inventory가 있으나, 고객 주문 출고 예약 소비 및 검수 승인 반품의 재고 복원 함수는 없다. 따라서 C 실제 출고·반품 환불 최종 완료 API의 해당 연결은 계속 대기한다. 이미 구현한 혜택 미사용 모의 취소는 기존 release_order_inventory를 사용한다.

D에게 필요한 후속 계약: 출고 소비·반품 복원 각각의 함수 위치/이름/인자/반환값, 기존 업무 ID 기반 중복 방지, 허용 상태, 기록 위치 및 같은 DB 연결의 하위 commit 없음. 제조사 입고 완료를 고객 주문 출고 완료로 간주하지 않는다.

### C 배송 출고 기록 내부 함수 준비

`c_dispatch.py::record_dispatched_fulfillment(db, *, order_id, fulfillment_id, employee)`를 추가했다. B가 검증한 HQ_STAFF를 전달하며 실제 직원 확인을 받은 최상위 실행에서만 호출해야 한다. 현재 공개 API/버튼 연결은 없다.

동일 연결의 D 출고 소비 이후, PAID 주문/PAID 결제·단일 PREPARING 배송·수령 대리점·전체 배송 항목·주문별 예약의 옵션/수량/CONSUMED/consumed_at 일치를 확인한다. 배송을 IN_TRANSIT/shipped_at=CURRENT_TIMESTAMP로 변경하고 처리 직원·주문 ID·상태 이력을 기록한다. D 재고 값은 변경하지 않고 주문 SHIPPING 변경도 이 함수가 수행하지 않는다.

하위 commit/rollback 없음. 호출자는 A mark_order_shipping과 전체 업무를 같은 트랜잭션에서 수행해야 하며 실패하면 전부 rollback한다. 재전송된 IN_TRANSIT 배송을 다시 변경하지 않는다. 최상위 요청 식별자/완료 결과 기반 재전송 계약은 D 함수 연결 때 구현한다.

CONSUMED 기록의 일치는 D 함수 실행 결과를 대신하는 인증이나 실물 출고 증거가 아니다. D 실제 소비 함수 및 기존 데이터의 의미를 확인하기 전에는 이 함수를 공개 실행에 연결하지 않는다. 대체 DB 테스트만 추가했으며 실제 출고 데이터는 만들지 않았다.

### C 배송 → A 주문 상태 연결 검증

기존 test_c_dispatch_record.py에 같은 대체 DB 연결로 record_dispatched_fulfillment → transition_dispatched_order → A mark_order_shipping을 호출하는 테스트를 보강했다. 배송 IN_TRANSIT 기록 후 주문 SHIPPING 변경 순서와 두 이력을 확인한다. D 소비 기록이 없으면 쓰기 전에 차단하며, A 상태 변경/이력 실패는 최상위 테스트 호출자의 rollback까지 전파된다.

이 테스트는 D 출고 함수 호출이나 실제 MySQL rollback을 검증하지 않는다. CONSUMED 응답은 대체 데이터이고 실행 코드의 인증 우회·재고 소비 구현은 추가하지 않았다. 최상위 출고 API/버튼은 계속 비활성이다.

연결 전 C에서 준비 가능한 배송 생성·출고 기록·A 상태 변경과 관련 자동 테스트는 마련됐다. 다음 작업은 D 실제 소비 함수 계약 확인 및 최상위 직원 확인/요청 식별자/완료 결과 재전송 처리와 단일 트랜잭션 연결이다. 해당 계약 없이 새 준비 함수를 계속 추가하지 않는다.

### 사용자 승인으로 D 출고 소비 함수 추가

이전의 소비 함수 부재는 후속 구현으로 해소했다. 기존 `inventory.py`에 `consume_order_inventory(db, *, order_id, employee_id) -> OrderReservationResult`를 추가했다. 구조·스키마와 기존 확보/해제 함수를 변경하지 않았다.

신규 소비는 PAID 주문 및 PAID 결제, 출고 전, 전체 주문 항목과 정확히 일치하는 RESERVED 예약을 요구한다. 본사 실물/예약 수량을 함께 차감하고 예약 CONSUMED/consumed_at과 SHIPMENT 변동 이력을 기록한다. 변동의 reference_type=ORDER/reference_id=order_id, 키는 reservation:{예약ID}:consume, 직원 ID와 시각은 기존 컬럼을 사용한다. SKU 잠금은 기존 정렬 방식을 따른다.

전체 예약이 이미 CONSUMED이면 PAID/SHIPPING 범위에서 기존 소비 시각과 동일 수량의 변동 이력을 확인하고 changed=false를 반환한다. 부분 소비/해제/수량 불일치는 차단한다. 결제 완료 주문의 소비에 예약 만료 조건을 새로 추가하지 않는다.

하위 commit/전체 rollback 없음, 기존 savepoint 사용. 호출자는 B 검증 직원의 HQ_STAFF 실행 권한과 실제 출고 확인을 먼저 검사하고, 동일 연결에서 D 소비 → C 배송 기록 → A SHIPPING → 전체 commit을 수행해야 한다. 이 내부 함수 자체는 직원 ID를 인증하거나 최종 배송 완료를 수행하지 않는다.

자동 테스트는 대체 DB로 신규 소비·재전송·상태/예약/재고 오류·savepoint 복구를 확인했다. 실제 DB/동시 요청 및 최상위 출고 API/직원 버튼 연결은 아직 남아 있다. 반품 재고 복원은 이번 범위가 아니다.

### 최상위 출고 확인 API 구현

기존 C 라우터에 `POST /api/v1/order-history/staff/dispatch/{order_id}/confirm`을 추가했다. 본문 request_id(1~100자), confirmed=true를 요구한다. B current_employee의 HQ_STAFF만 실행 가능하며 조회 권한을 실행 권한으로 확대하지 않는다.

주문 잠금 → 동일 요청/주문의 DISPATCH_COMPLETE 완료 감사 기록 확인 → prepare_order_fulfillment → consume_order_inventory → record_dispatched_fulfillment → A 주문 SHIPPING 변경 → 완료 감사 기록 → 단일 commit 순서다. 모든 함수에 동일 DB 연결을 전달하고 실패하면 전체 rollback한다. autocommit 연결은 거부한다.

동일 직원의 요청 키/본문 재전송 및 같은 주문의 다른 키 재전송은 기존 완료 결과를 반환한다. 같은 요청 키로 다른 주문을 보내면 409다. 완료 이력 없이 부분 출고 기록만 존재하면 선행 검증에서 차단하며 자동 복구하지 않는다. 알림·실결제는 호출하지 않는다.

성공 data는 order_id/order_status=SHIPPING/fulfillment_id/fulfillment_number/completed/replayed다. 처리 직원·요청 ID·연결 주문/배송 ID는 감사 및 상태/재고 변동 이력에 기록된다. confirmed는 직원의 실제 출고 확인 입력이며 앱이 자동으로 보내 완료 처리해서는 안 된다.

API 자동 테스트는 인증·권한·처리 순서·각 단계 실패·완료 재전송을 의존성 대체로 검증한다. 실제 MySQL 전체 실행/동시 요청은 아직 검증하지 않았다. 직원 화면의 실행 버튼은 아직 연결하지 않았으며 다음 작업에서 명시적 확인 입력·중복 클릭 방지·동일 키 재시도를 제공해야 한다.

### 직원 출고 버튼 후속 연결

DispatchView/DispatchVm에 POST 호출과 실제 출고 확인 체크를 연결했다. staff_app.dart → dashboard_page.dart는 기존 인증 API의 post 함수 전달에 필요한 최소 인자만 추가했다. 화면의 hqStaff만 실행 함수를 전달하며 서버의 HQ_STAFF 검사가 최종 권한 기준이다. 목업·타 직급 화면은 기존 읽기 전용을 유지한다.

저장 중 중복 클릭을 막고 주문별 요청 키를 VM에서 유지하여 응답 유실 재시도 시 같은 키를 사용한다. 서버 completed=true/SHIPPING/동일 주문 결과만 성공으로 인정하고 목록을 새로 조회한다. 컨트롤러는 화면 initState에서 생성하고 dispose에서 종료하며 늦은 응답은 무시한다. 앱 재시작/직급 전환을 넘는 요청 키 영구 저장은 제공하지 않는다. 서버는 같은 주문의 다른 키 재전송도 완료 이력으로 처리한다.

자동 테스트는 VM 중복/재시도/종료/불완전 응답과 기존 화면 회귀를 검증했다. 실제 직원 앱 버튼부터 MySQL 재고 반영까지의 검증은 아직 남아 있다.

### 로컬 DB 출고 통합 검증 — 2026-10-11

127.0.0.1/shupick_v2에서 신규 테스트 주문 90번을 생성하고 실제 Firebase 고객/직원 토큰으로 FastAPI TestClient 요청을 수행했다. 인증 의존성 대체는 없었다. 모의 결제 → 직원 출고 → 동일 요청 재전송 → 고객 상세 조회가 성공했다. 고객 토큰의 출고 실행 요청은 403이었다.

주문 SHIPPING, 배송 54번 IN_TRANSIT/shipped_at, 예약 CONSUMED/consumed_at, SHIPMENT 변동 1건을 실제 DB에서 확인했다. 옵션 1번 실물 수량은 18→17, 예약 수량은 0으로 돌아왔다. 출고된 테스트 기록은 보존했다. 실제 물건을 발송한 것이 아니라 테스트 데이터로 출고 확인 요청을 실행한 검증이다.

실제 네트워크 서버/직원 앱 버튼 조작, 단일 직급 직원의 권한 제한, 동시 요청 및 출고 도중 실제 DB 실패 rollback은 이 검증에 포함하지 않았다. 다음 입고·수령 실행은 기존 계약의 D 보관/수령 재고 처리와 B 수령 인증 연결 여부를 확인한 뒤 진행한다.
