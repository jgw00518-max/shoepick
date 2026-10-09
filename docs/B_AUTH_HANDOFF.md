# B 최소 인증 구현과 전달 사항

## 범위

두 앱 Firebase 초기화·로그인·로그아웃, 서버 ID 토큰 검증,
MySQL 고객·직원 연결 및 공통 업무 권한·대리점 검사만 구현한다.
회원가입/직원 관리/혜택/장바구니 업무는 이 단계에서 구현하지 않는다.
기존 목업 구현은 테스트용 주입을 위해 유지하며 실제 main은 Firebase 구현을 주입한다.
로그인은 서버 계정 확인까지 성공해야 완료된다. 고객 앱 회원가입은 미리 등록한 계정을 안내한다.

## 파일과 함수

| 위치 | 사용 방법 |
|---|---|
| backend/features/authentication.py | verified_uid, current_customer, current_employee |
| 같은 파일 | require_permission(기존 합의 코드), check_branch(employee, branch_id) |
| 두 앱 lib/vm/auth_api.dart | AuthApi.get(전체 API 경로), 토큰 포함·401 갱신1회 |
| 고객 lib/vm/firebase_account.dart | FirebaseAccount.signIn/signOut, customerId |
| 직원 lib/vm/firebase_staff_auth.dart | FirebaseStaffAuth.signIn/restoreSession/signOut |
| 두 앱 main.dart | Firebase 초기화와 실제 인증 주입 |

GET /api/v1/authentication/customer: data의 customer_id, firebase_uid, customer_name.
GET /api/v1/authentication/staff: employee_id/code/name, department, position,
roles(role_code/name), permissions(문자열 목록), branches(branch_id/code/name/district_code).
기존 DB 컬럼 이름을 변경하지 않는다. 직원 화면의 기존 camelCase 모델에는 B 어댑터가 변환한다.

다른 담당은 APIRouter(route_class=AuthRoute)와 Depends(current_customer)를 사용한다.
직원 업무는 Depends(require_permission(합의된 코드))와 대상 대리점 check_branch를 적용한다.
직급/업무 승인 조건은 반환된 실제 position/department와 해당 기능의 합의 정책으로 검사한다.
현재 기본 코드만으로 특정 직급에 모든 업무를 허용하지 않는다.
기존 C 라우터는 아직 B를 연결하지 않았다. 해당 변경은 C 담당이 별도로 진행한다.

## 실행 설정

backend/.env: FIREBASE_PROJECT_ID=shoepick-40a48,
FIREBASE_CREDENTIALS_PATH=secrets/서비스계정파일.json 또는 Google 기본 자격증명.
비밀 키는 backend/secrets에 두고 Git/채팅에 내용을 올리지 않는다.
Python 패키지 설치: python -m pip install -r backend/requirements.txt.
Flutter 실행: flutter run --dart-define=API_BASE_URL=http://실제백엔드주소:8000
주소에는 /api/v1을 붙이지 않는다. DB IP와 API 서버 주소는 구분한다.
Android 에뮬레이터에서 PC API는 환경에 맞는 주소를 사용한다.
이 구현은 Android/iOS 대상으로 dart:io를 사용한다. 웹·Windows Firebase 설정은 추가하지 않았다.

## 테스트 계정 등록 전 필요한 정보

고객 이메일·초기 비밀번호·표시 이름, 직원 이메일·비밀번호·이름·직원 코드·부서·직급,
기존 role_code와 branch_id를 담당자가 지정한다. 서비스 계정 권한도 필요하다.
2026-10-09 사용자 승인으로 고객 user@example.com(customer_id=40),
직원 staff@example.com(employee_id=15)을 Firebase와 공용 MySQL에 등록했다.
직원은 BRANCH_STAFF/BRANCH_MANAGER/HQ_STAFF/TEAM_LEAD/DIRECTOR/EXECUTIVE와
등록 당시 활성 대리점25개에 연결했다. ADMIN은 제외했고 신규 권한 코드는 만들지 않았다.
부서·직급 필드는 테스트 표시 TEST이며 실제 승인 업무의 직급 판별에 그대로 사용하면 안 된다.
비밀번호는 별도로 전달하고 문서·Git에 기록하지 않는다.
Firebase Authentication 이메일/비밀번호 로그인을 활성화한다.
Firebase에서 만든 UID를 customers.firebase_uid 또는 employees.firebase_uid에 연결하고,
직원 역할은 employee_roles, 소속은 employee_branch_assignments에 등록한다.
없는 권한 코드·직급·대리점을 임의로 만들지 않는다. 기존 계정을 덮어쓰거나 비밀번호를 변경하지 않는다.
키/계정 정보가 제공된 뒤 등록 결과의 UID와 DB ID만 공유하고 비밀번호는 Git에 기록하지 않는다.

## 협업 변경 범위

B 신규 파일과 인증 테스트, main.py 등록, 앱 main·pubspec·Firebase 설정이 대상이다.
고객 기존 계정 인터페이스에는 signOut을 추가하고 StoreBinding/ShupickApp에 인증 주입을 추가했다.
StoreController의 signOut은 Firebase 종료를 기다리도록 변경했다. A 주문 생성·C 조회·D 재고는 변경하지 않는다.
고객 로그아웃은 개인 목록을 비우고 로컬 장바구니 상태도 초기화한다.
다른 담당에서 추가하는 개인 상태 역시 로그아웃 시 초기화하도록 연결해야 한다.
Firebase 비밀번호 로그인 -> 실제 ID 토큰 -> 백엔드 사용자 조회를 두 계정 모두200으로 검증했다.
직원은 기존 역할에서 권한10개를 조회했다. 실제 모바일 UI와 각 업무의 권한 검증은 별도로 수행한다.

python -m pytest backend/tests/test_authentication.py
각 Flutter 앱에서 dart format lib test, flutter analyze, flutter test를 실행한다.
