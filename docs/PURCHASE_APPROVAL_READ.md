# 팀장·이사 결재 조회

| API | 용도 |
|---|---|
| GET /api/v1/purchase-approvals/pending | 해당 직책의 결재 대기 목록 |
| GET /api/v1/purchase-approvals/history | 로그인 직원 본인의 승인·반려 이력 |
| GET /api/v1/purchase-approvals/{purchase_approval_id} | 결재 품의 상세와 단계별 이력 |

모든 요청은 Firebase Bearer 토큰과 stage=TEAM_LEAD 또는 stage=DIRECTOR가 필요하다.
서버는 활성 직원의 PROCUREMENT_APPROVE_TEAM_LEAD 또는 PROCUREMENT_APPROVE_DIRECTOR 권한을 확인한다.
직책 선택이나 요청의 직원 ID는 권한 근거가 아니다. 테스트 계정은 기존 두 결재 권한으로 두 화면을 조회한다.

목록은 page(1 이상), page_size(1~100, 기본 20)와 data/pagination 응답을 사용한다.
팀장 대기는 1차 PENDING 결재 기록 + PENDING_TEAM_LEAD 품의이다.
이사 대기는 2차 PENDING 기록 + PENDING_DIRECTOR 품의 + 이전 팀장 APPROVED 기록을 모두 확인한다.
DRAFT는 두 결재함에서 제외한다. 준비된 이사 PENDING 기록만으로 팀장 승인 전 품의를 보여주지 않는다.
대기는 상신일 최신순, 이력은 결정일 최신순이며 결재 ID로 정렬 순서를 고정한다.

처리 이력은 해당 직책 기록 중 approver_employee_id가 현재 직원이고 결과가 APPROVED/REJECTED인 건만 조회한다.
본인의 승인·반려 결과와 품의의 현재 상태를 별도 표시한다.
상세는 해당 직책의 현재 대기 대상 또는 본인 처리 이력에 포함된 결재 기록만 조회한다.
조회할 수 없거나 존재하지 않는 상세는 404, 직책 권한이 없으면 403, 미인증은 401이다.
전체 품목·사유·단계별 결재자·의견·결정 시간을 읽기 전용으로 제공한다.

직원 앱 일반 로그인 → 본사 팀장/본사 이사 → 결재함에서 실제 API를 사용한다.
결재 대기/내 처리 이력 전환, 새로고침, 20건씩 페이지 이동, 상세 보기와 오류 재시도를 지원한다.
목업 바로 보기는 기존 시뮬레이션을 유지한다.
이번 작업은 조회 기능만 구현했으며 실제 승인·반려 버튼은 표시하지 않는다.

## 임원 결재 현황

- `GET /api/v1/purchase-approvals/overview`: 상신된 전체 품의 현황.
- `GET /api/v1/purchase-approvals/overview/{purchase_requisition_id}`: 전체 품목·단계별 결재자·의견·결정 시간.

DB에서 확인한 활성 EXECUTIVE/ADMIN 역할 또는 기존 AUDIT_LOG_READ 권한으로 접근한다.
임원 역할은 현재 DB에 전용 조회 권한이 없으므로 서버가 검증한 역할로 연결하며 DB 권한 행은 변경하지 않았다.
클라이언트 직책 선택·직원 ID·이메일로 접근을 허용하지 않는다.
상세 조회의 소유자 범위 확장은 이 권한 검사를 통과한 임원 현황 경로 안에서만 적용한다.

초안과 submitted_at이 없는 품의는 제외한다. 초안 취소처럼 상신하지 않은 CANCELED도 제외한다.
품의 한 건에 팀장·이사 결과를 붙이며 결재 단계 수나 품목 수로 목록이 중복되지 않는다.
상신일 최신순, 동일 시각이면 품의 ID 내림차순으로 정렬한다.
status(초안 제외), keyword(제목·작성자 이름), submitted_from/to(YYYY-MM-DD), page/page_size를 지원한다.
시작·종료일은 해당 날짜 전체를 포함하며 역전된 기간은 400을 반환한다.
팀장·이사 결과와 품의 현재 상태는 별도 필드이다. 아직 차례가 아닌 PENDING은 앱에서 미진행으로 표시한다.

일반 로그인 → 본사 임원 → 결재 현황에서 실제 API를 사용한다.
상태·기간·검색, 초기화, 새로고침, 20건씩 페이지 이동과 상세 보기를 지원한다.
조회 화면이며 승인·반려 버튼은 표시하지 않는다. 목업 모드는 기존 시뮬레이션을 유지한다.

## 목록 정렬

사원·팀장·이사·임원 품의 목록에 최신순(desc, 기본)/오래된 순(asc) 드롭다운을 제공한다.
API 쿼리 order=asc 또는 order=desc로 전체 결과를 정렬한 뒤 페이지를 나눈다.
사원 목록은 작성일, 결재 대기는 상신일, 내 처리 이력은 결정일, 임원 현황은 상신일을 기준으로 한다.
같은 시각이면 ID도 같은 방향으로 정렬한다. 정렬 변경 시 첫 페이지로 돌아가며 검색·상태·기간 조건은 유지한다.
팀장·이사 대기/이력 전환에도 선택한 정렬을 유지한다. 목업 목록도 작성일·ID 기준으로 정렬한다.
# 팀장 승인·반려

- 팀장 결재 대기 목록의 `상세 보기`에서 전체 품의와 품목을 확인한 뒤 승인·반려합니다.
- `POST /api/v1/purchase-approvals/{purchase_approval_id}/approve`
- `POST /api/v1/purchase-approvals/{purchase_approval_id}/reject`
- Firebase Bearer 토큰과 `PROCUREMENT_APPROVE_TEAM_LEAD` 권한이 필요합니다.
- 요청: `{"revision": "상세 조회 응답의 64자리 revision", "comment": "결재 의견"}`
- 승인 의견은 선택이고, 반려 사유는 필수입니다(최대 2,000자).
- 팀장 1차 결재가 대기 중인 품의만 처리합니다. 승인 시 `PENDING_DIRECTOR`, 반려 시 `REJECTED`로 변경합니다. 반려된 품의의 이사 결재는 `WAIVED`(미진행)로 기록합니다.
- 처리자와 처리 시간은 서버가 저장합니다. 상태·내용이 변경되었거나 이미 처리된 경우 409 응답을 반환합니다. 결재와 품의 상태 변경은 하나의 트랜잭션으로 저장합니다.
- 앱은 완료 후 대기 목록을 갱신합니다. 처리 결과는 `내 처리 이력`에서 확인합니다.

# 이사 최종 승인·반려

- 이사 결재 대기의 `상세 보기`에서 승인·반려합니다. 승인 의견은 선택이고 반려 사유는 필수입니다.
- `POST /api/v1/purchase-approvals/{purchase_approval_id}/approve?stage=DIRECTOR`
- `POST /api/v1/purchase-approvals/{purchase_approval_id}/reject?stage=DIRECTOR`
- 요청 본문은 팀장 결재와 같습니다. 서버가 `PROCUREMENT_APPROVE_DIRECTOR` 권한, 활성 이사 2차 결재 기록, `PENDING_DIRECTOR` 상태, 팀장 1차 승인 기록, 최신 revision을 확인합니다.
- 승인 시 이사 결재를 `APPROVED`로 기록하고 제조사 발주를 자동 등록해 품의는 `ORDERED`로 변경합니다. 반려 시 품의와 이사 결재를 `REJECTED`로 변경합니다. 팀장 결재 결과는 유지합니다.
- 발주는 기존 `audit_logs`의 `PROCUREMENT_ORDER_PLACED` / `PURCHASE_REQUISITION` 기록에 저장합니다. 품의당 1건이며 발주번호는 `PO-{품의 ID 6자리}`입니다. 제조사·상품·옵션·승인 수량을 JSON 스냅샷으로 저장하고 별도 테이블·컬럼은 만들지 않습니다.
- 승인·발주 기록·품의 상태를 한 트랜잭션으로 저장합니다. 발주 실패 시 이사 승인도 롤백합니다. 품의를 잠근 뒤 중복 기록을 검사하므로 동일 품의의 동시 승인·재시도로 발주가 중복 생성되지 않습니다.
- 승인 응답의 `manufacturer_order`에 발주번호, 기록 ID, 제조사, 수량, 등록 시간을 반환합니다. 팀장 결재와 반려 응답에서는 null입니다. 앱에서 이사 승인 안내와 자동 발주 등록 완료 메시지를 표시합니다.
- 제조사 외부 전송 연결은 없습니다. `transmission_status=NOT_SENT`로 저장하며 이메일·제조사 API에 실제 전송한 것으로 표시하지 않습니다. 제조사 접수 확인·발주 목록·입고 등록은 후속 구현 대상입니다. 발주 시 본사 재고는 변경하지 않습니다.
- 감사 로그는 발주 원본이므로 삭제·정리 대상에서 제외해야 합니다. 이후 발주 관련 쓰기도 같은 품의 잠금을 사용해야 합니다(기존 감사 로그에는 발주 UNIQUE 제약이 없습니다).
- `stage`를 생략하면 기존 팀장 API와 동일하게 동작합니다. 화면에서 보내는 stage만으로 권한을 부여하지 않습니다.
