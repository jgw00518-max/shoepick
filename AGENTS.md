# 작업 지침

작업 전에 docs/CODING_GUIDELINES.md와 관련 기존 코드·DB 구조를 읽고 따른다.
미확정 업무 정책이나 기존 이름 변경은 담당자에게 확인한다.
요청 관련 코드부터 좁게 확인하고 기능과 무관한 변경을 하지 않는다.
관련 테스트를 먼저 실행하며 Flutter 변경 마지막에는 해당 앱에서
`dart format lib test`, `flutter analyze`, `flutter test`를 한 번 실행한다.
백엔드 변경은 `python -m pytest backend/tests`로 검증한다.
