# SOLE / SELECT Flutter 목업

Higgsfield 목업의 화면 구조와 로컬에서 확인 가능한 상호작용을 Flutter로 옮긴 팀 작업본입니다.

## 실행

```sh
flutter pub get
flutter run
```

## 구현 범위

- 비회원 홈 탐색, 기획전, 성별·카테고리·하위 분류·정렬, 검색, 최근 본 상품, 찜
- 상품 상세, 색상별 이미지와 옵션, 복수 옵션 선택, 재입고 신청
- 장바구니 선택·수량·옵션 수정, 대리점 선택, 쿠폰·적립금·결제 수단 선택, 목업 주문 완료
- 로그인·회원가입 목업, 주문·배송·픽업 QR, 리뷰 작성·수정·삭제·사진, 쿠폰·포인트·고객센터
- 한국어·영어 화면 문구, 다크 화면, 푸시 설정

화면에 보이는 결제 수단, 소셜 로그인, 비밀번호 재설정 메일, 실제 푸시 발송, QR 검증, 주문 배송 정보는 실제 외부 서비스와 연동하지 않습니다. UI 전용 항목은 비활성 상태로 표시합니다.

## 구조와 추후 DB 연결

- `lib/main.dart`: 앱 진입점
- `lib/app`: 의존성 조립과 화면 상태
- `lib/domain/models.dart`: 상품·주문·리뷰·문의 모델
- `lib/domain/repositories.dart`: 저장·조회 인터페이스
- `lib/data/mock_repositories.dart`: 상품·주문·리뷰·문의 더미 데이터
- `lib/data/local_settings_repository.dart`, `lib/data/local_support_repository.dart`: 언어·화면 설정과 재입고 신청의 기기 저장
- `lib/presentation/screens`: 기능별 화면
- `lib/presentation/shared`: 공통 상품 위젯
- `lib/presentation/localization.dart`, `lib/presentation/locale_dictionary.dart`: 목업의 영어 문구 사전

현재 상품·주문·리뷰·문의·장바구니는 앱 실행 동안 유지되는 목업 저장소를 사용합니다. 실제 서비스로 전환할 때 `ProductRepository`, `OrderRepository`, `ReviewRepository`, `ShoppingRepository`, `SupportRepository`, `AccountRepository` 구현을 교체하면 화면 상태와 위젯을 유지할 수 있습니다. MySQL 트랜잭션 데이터는 백엔드 API를 통해 연결하고, SQLite는 기기 캐시나 임시 저장, Firebase는 알림 등 보조 기능에 연결하는 구조를 권장합니다.

## 검증

```sh
dart format lib test
flutter analyze
flutter test
```
