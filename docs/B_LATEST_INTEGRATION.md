# 최신 팀 구현과 B 인증 연결 — 2026-10-26

> 이후 실제 휴대전화 검증 결과는 [모바일 검증 기록](B_MOBILE_VERIFICATION_2026-10-26.md)을 참고한다.
> 아래 모바일 미검증 설명은 이 문서를 작성했던 시점의 상태다.

## 먼저 알아둘 점

기존 `shoepick` 폴더의 `feature/b-auth`는 오래된 커밋 `5f4a47d` 기준이었다.
원격을 fetch한 결과 최신 `origin/develop`의 `99e37f6`에는 팀원들의 주문 생성,
모의 결제/환불, 재고 확보·해제, 출고·도착·검수·수령, 품의·결재·입고 등이 이미 구현돼 있었다.
따라서 과거 로컬 분석의 “업무 미구현” 설명은 최신 develop에 적용되지 않는다.

기존 미커밋 변경을 덮어쓰지 않기 위해 별도 worktree를 만들었다.

- 작업 폴더: `../shoepick_b_auth_integration`
- 작업 브랜치: `feature/b-auth-integration`
- 기준 커밋: `99e37f6` (`origin/develop`)
- 기존 폴더의 사용자·팀원 변경 보존. 이번에 잠시 작성했던 구버전용 출고 구현만 제거했다.
- 커밋·푸시·PR 생성 없음. 원격 최신 정보는 fetch만 했다.

## 이번 연결 내용

| 영역 | 수정 내용 | 유지한 팀원 기능 |
|---|---|---|
| A 주문 조회 | `/orders/paid`, `/orders/{order_id}`에 고객 인증·본인 주문 조건 | 경로·응답 모델·주문 생성·결제·환불·재고 호출 |
| A/C 공통 조회 | HTTP 전용 `get_customer_paid_orders`를 분리하고 내부 `get_paid_orders(db=...)` 유지 | C가 전체 결제 완료 주문을 읽고 자신의 직원 범위로 제한하는 계약 |
| C 출고/후보 조회 | 기존 범위 의존성에 `orders.dispatch.read` 연결 | 최신 C의 실제 조회·출고 상태 판정·후속 업무 처리 |
| D 재고 조회 | 본사 권한, 지점 조회 권한 및 현재 유효 소속 검사 연결 | 내부 재고 계산·예약·해제·소비·반품 재고 복구 |
| 직원 재고 클라이언트 | 기본 HTTP 클라이언트에 Firebase Bearer·401 갱신 연결 | 주입 가능한 테스트 클라이언트와 응답 모델 |
| 두 앱 공통 요청 | 빈 토큰 거부, 401 갱신 1회, 동시 갱신 공유, JSON 아닌 401/403 처리, 리다이렉트 차단 | 최신 POST/PATCH의 서로 다른 응답 반환 계약과 업무 오류 안내 |
| 세션 종료 | 기존 B의 고객 개인 상태·직원 프로필 초기화를 최신 UI에 연결 | 최신 팀원 화면·미리보기·업무 API 주입 |
| 직원 로그인 | 서버 권한 목록 보존, 디버그 토큰 출력 제거 | 최신 Firebase 오류별 안내와 실패 세션 정리 |

새로운 직원 쓰기 권한을 만들어 배정하지 않았다. 최신 팀원이 이미 구현한
역할·업무 상태·본인 여부·지점 검사와 트랜잭션을 유지한다.
읽기 권한을 모든 직원 쓰기 업무의 허용 근거로 사용하지 않는다.

## 검증

### 자동 테스트

연결 전 최신 develop 백엔드: **656 통과, 2 건너뜀**.
연결 후 백엔드: **674 통과, 2 건너뜀**.
건너뛴 항목은 명시적으로 활성화해야 하는 실제 DB 수령/반품 트랜잭션 검사다.
실제 주문·재고를 변경하지 않기 위해 실행하지 않았다.
Starlette/httpx 사용 중단 예고 경고 1건은 테스트 실패가 아니다.

직원 앱: **107개 통과**, 정적 분석 `No issues found`.
고객 앱: **46개 통과**, 정적 분석 `No issues found`.

기존 데이터 조회 테스트는 인증된 가짜 직원을 주입하도록 보완했고,
별도 권한 테스트에서 토큰 없음·권한 없음·고객 계정·타 지점 거부를 검사한다.
기존 고객 화면 테스트는 실서버 상품 조회에 의존하지 않도록 테스트에서만 Mock 상품을 주입했다.
실제 앱 상품 저장소는 변경하지 않았다.

### 실제 Firebase·MySQL 읽기 전용 확인

기존 고객/직원 Firebase 계정 조회 성공. 실제 DB 권한은 아래 3개다.

- `inventory.branches.read`
- `inventory.headquarters.read`
- `orders.dispatch.read`

실제 DB 연결 검사에서는 테스트 프로세스 안에서 `verified_uid`만 기존 UID로 대체했다.
토큰 검증부터 포함한 모바일 전체 검사와 구분한다.

| 검사 | 결과 |
|---|---|
| 직원 세션 | 200 |
| 본사 재고 | 200 |
| 지점 1 재고 | 200 |
| 최신 C 출고 조회 | 200 |
| 고객 세션 | 200 |
| 고객 본인 결제 완료 주문 | 200 |
| 고객 구매 내역 | 200 |
| 고객의 직원 출고 조회 | 403 |

실제 POST/PATCH/PUT 업무 요청은 실행하지 않았다. 자동 테스트의 변경은 Mock/메모리 데이터에만 적용된다.

## 실제 DB와 팀 문서의 차이

최신 팀원 코드는 아래 권한을 사용하지만 현재 로컬 설정의 실제 DB에는 없다.

| 팀 코드에서 요구하는 권한 | 용도 |
|---|---|
| `PROCUREMENT_REQUISITION_CREATE` | 품의 작성·수정·작성 선택지 |
| `PROCUREMENT_REQUISITION_SUBMIT` | 본인 품의 상신 |
| `PROCUREMENT_APPROVE_TEAM_LEAD` | 팀장 결재 |
| `PROCUREMENT_APPROVE_DIRECTOR` | 이사 결재 |

팀 코드에는 감사 조회 등 `AUDIT_LOG_READ`, `ROLE_MANAGE` 확인도 있다.
이 코드들은 현재 DB에 등록·배정돼 있다는 뜻이 아니다.
일부 팀 문서의 과거 테스트 직원 ID/배정 기록도 현재 DB 상태와 다를 수 있다.
해당 권한이 없는 상태에서 품의·결재가 403을 반환하는 것은 인증 연결 오류가 아니다.
팀이 사용한 DB와 현재 연결 DB 및 승인된 역할별 배정표를 확인한 뒤 별도로 반영해야 한다.
이번에는 권한·직원·지점·워크플로·스키마를 변경하지 않았다.

## 변경 파일

| 파일 | 변경 이유 |
|---|---|
| `backend/features/order.py` | 고객 HTTP 조회 보호, 내부 A/C 조회 계약 유지 |
| `backend/features/order_history.py` | 기존 공통 범위에 DB 출고 조회 권한 연결 |
| `backend/features/inventory.py` | 재고 조회 권한·지점 검사 |
| `backend/auth_policy.py` | 기존 B 조회 권한 상수·정책 helper 재사용. seed 미실행 |
| `backend/tests/test_inventory.py`, `test_order_history.py` | 기존 업무 테스트에 인증된 주체 명시 |
| `backend/tests/test_order_auth_boundary.py`, `test_staff_authorization.py` | 소유권·권한 경계 회귀 검사 |
| 두 앱 `lib/vm/auth_api.dart` | 최신 업무 요청 계약을 유지하며 인증 처리 보완 |
| 고객 `lib/vm/firebase_account.dart`, `lib/domain/repositories.dart`, `lib/app/store_controller.dart` | 세션 종료와 개인 상태 정리 |
| 직원 `lib/vm/firebase_staff_auth.dart`, `lib/vm/staff_session.dart`, `lib/view/staff_app.dart` | 로그인·세션 종료 UI 연결, 토큰 출력 제거 |
| 직원 `lib/model/staff_session.dart` | 서버 권한 목록 보존 |
| 직원 `lib/vm/firebase_http_client.dart`, `branch_inventory_api.dart`, `headquarters_inventory_api.dart` | 실제 재고 요청에 토큰 전달 |
| 두 앱 인증/세션 테스트, 직원 `auth_api_post_test.dart`, 고객 `widget_test.dart` | 새 인증 경계와 최신 업무 호출 계약 검증 |

## 다음 실행

VS Code에서 **새 폴더 `shoepick_b_auth_integration`**를 열어야 이번 연결본을 실행한다.
기존 폴더의 실행 서버와 앱은 자동으로 바뀌지 않는다.

```powershell
# 새 작업 폴더 루트
python -m pytest backend/tests -q
python -m uvicorn backend.main:app --host 127.0.0.1 --port 5556
```

기존 5555 서버와 혼동하지 않도록 모바일 재검증에는 별도 포트 5556을 권장한다.
USB Android 사용 시 SDK의 adb로 `reverse tcp:5556 tcp:5556`을 설정하고 각 앱 폴더에서 실행한다.

```powershell
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:5556
```

기존 로컬 `.env`를 Git 제외된 새 `.env`에 재사용했고 서비스 계정 경로는 기존 로컬 파일을 참조한다.
내용은 출력·커밋하지 않는다. 모바일 새 로그인·출고 화면 조회는 이번 연결본 기준으로 별도 확인이 필요하다.
