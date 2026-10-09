# FastAPI 파일 구성

담당 D의 기능을 `features/` 아래에 업무별 Python 파일 하나로 구성한다.

| 파일 | 역할 |
| --- | --- |
| `main.py` | 앱 생성과 기능별 라우터 등록 |
| `database.py` | 기존 PyMySQL 연결 |
| `dependencies.py` | 요청별 DB 연결 생성·종료 |
| `features/inventory.py` | 재고 조회·예약·해제·이동·이력 |
| `features/purchase_requisitions.py` | 구매 품의 |
| `features/purchase_approvals.py` | 팀장·이사 결재 |
| `features/manufacturer_orders.py` | 제조사 발주 |
| `features/goods_receipts.py` | 제조사 입고 |
| `features/dashboard.py` | 운영 현황 |

각 기능 파일 안에 요청·응답 모델, 업무 처리 함수, API 함수를 순서대로 작성한다.
현재는 파일 구성과 라우터 등록까지 준비했으며 실제 업무 엔드포인트와 SQL은 미구현이다.
파일의 API 경로 주석은 제안이며 기존 API 확인 후 확정한다.

## 실행

FastAPI, Uvicorn, PyMySQL이 설치된 개발 환경에서 프로젝트 루트 기준:

먼저 `python -m pip install -r backend/requirements.txt`로 의존성을 설치하고,
`backend/.env.example`을 `backend/.env`로 복사해 본인의 DB 연결 정보를 입력한다.
`.env`는 Git에서 제외하며 DB 비밀번호를 Python 파일에 직접 작성하지 않는다.

```powershell
python -m uvicorn backend.main:app --reload
```

`backend/` 폴더에서 실행할 경우:

```powershell
python -m uvicorn main:app --reload
```

기존 방식인 `python main.py`도 `backend/`에서 사용할 수 있다.
API 문서는 `http://127.0.0.1:8000/docs`에서 확인한다.
현재 업무 API가 없으므로 문서에는 업무 엔드포인트가 표시되지 않는다.

## DB 연결과 담당 간 호출

패키지 실행 시 `from ..dependencies import get_db`로 가져와 `Depends(get_db)`에 연결한다.
다른 기능의 업무 함수를 호출할 때는 동일한 DB 연결을 전달한다.
예를 들어 제조사 입고 문서 저장과 재고 증가는 하나의 트랜잭션으로 처리하고,
최상위 업무 함수가 성공 시 한 번 commit한다. 예외가 나면 `get_db`가 rollback한다.

성공 응답은 `data`, 실패 응답은 `error.code`와 `error.message`를 사용한다.
FastAPI 기본 오류 응답도 팀 형식으로 통일하는 처리가 추후 필요하다.
인증·권한 검사는 담당 B의 공통 기능을 연결한 후 업무 API에 적용한다.
