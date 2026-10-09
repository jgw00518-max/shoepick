# 공통 백엔드 실행·협업 안내

Python 3.14에서 검증한다. MySQL 구조는 제공된 shupick_v2 기준이다.
저장소 루트에서 PowerShell로 실행한다.

```powershell
python -m venv backend/.venv
backend/.venv/Scripts/python -m pip install -r backend/requirements.txt
Copy-Item backend/.env.example backend/.env
backend/.venv/Scripts/python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

http://127.0.0.1:8000/api/v1/health 및 /docs를 확인한다.
health는 서버 실행만 확인한다. DB/Firebase 없이도 실행 가능하지만 업무 연결 성공은 아니다.
팀원 기기 접속 시 서버 담당이 합의한 주소·포트를 제공하고 필요하면 --host 0.0.0.0을 사용한다.
8000은 로컬 예시이며 공용 포트가 확정된 것은 아니다. 실제 서버 설정은 별도로 전달한다.

DB_HOST/PORT/NAME/USER/PASSWORD는 서버 담당에게 받는다. DB_USER는 업무용 계정을 사용한다.
현재 공용 DB는 192.168.219.224:3306, 스키마는 shupick_v2다.
Workbench 연결 이름 shoepick은 표시 이름이며 DB_NAME에는 사용하지 않는다.
코드의 기본 DB 주소는 비어 있다. 실제 접속 주소는 backend/.env의 DB_HOST 한곳에서 지정한다.
운영체제에 같은 이름의 환경변수가 있으면 .env보다 우선하므로 기존 DB_HOST도 확인한다.
Firebase 프로젝트와 자격증명은 B와 서버 담당에게 받는다.
키는 backend/secrets에 보관하고 FIREBASE_CREDENTIALS_PATH=secrets/파일명.json으로 설정한다.
절대 경로도 가능하며 비밀 파일은 Git에 올리지 않는다. 경로 미지정 시 기본 Google 자격증명을 사용한다.
Firebase 설정 부족은500, 잘못된 토큰은401, 미등록/비활성 DB 사용자는403이다.
인증을 우회하는 개발용 로그인은 없다. 역할/권한 초기 데이터는 B가 합의해 등록해야 한다.

기준 SQL은 빈 DB 초기화용으로 데이터가 없다. 기존 테이블이 있으면 그대로 실행하지 않는다.
이 작업은 실제 DB에 SQL을 적용하지 않았고 연결 정보도 저장하지 않는다.
DB 연결은 get_db를 Depends로 받아 사용한다. SQL은 %s와 별도 인자로 바인딩한다.
저장은 with transaction(db): 안에서 처리한다. 하위 공통 함수가 따로 commit하지 않게 한다.
중첩 transaction은 금지한다. 외부 결제 실패·재시도 및 중복 요청은 담당별 구현이 필요하다.
블로킹 PyMySQL/Firebase를 사용하는 라우터는 def로 작성한다.

## 각 담당의 라우터 추가

routes에 합의한 파일을 만들고 APIRouter로 작성한 뒤 main.py의 create_app에서 등록한다.
빈 A/B/C/D 라우터나 임의 업무 API는 미리 만들지 않았다.

```python
from fastapi import APIRouter, Depends
from backend.auth import current_customer
from backend.responses import success

router = APIRouter()
# 합의한 실제 경로로 작성한다.
# @router.get(...)
# def read_orders(customer=Depends(current_customer), db=Depends(get_db)):
#     ... WHERE customer_id=%s 에 customer['customer_id']를 전달
#     return success(rows)
```

main.py: app.include_router(담당모듈.router, prefix=get_settings().api_prefix).
동일 백엔드 내 담당 연결은 합의한 함수로 호출한다. 공통 파일 수정은 사전에 범위를 공유한다.
A 결제, B 인증·혜택, C 배송·지원, D 재고의 업무 규칙을 중복 구현하지 않는다.

```powershell
backend/.venv/Scripts/python -m pytest backend/tests
```

테스트는 외부 연결을 대체해 공통 계약을 검증한다. 실제 서버에서는 유효/만료 토큰,
삭제 고객·비활성 직원, 권한·대리점 차단, DB 연결 및 commit/rollback을 별도로 확인한다.
Package versions: backend/requirements.txt.
공통 오류/토큰 검증 방식은 FastAPI와 Firebase 공식 문서를 따른다:
https://fastapi.tiangolo.com/tutorial/handling-errors/
https://firebase.google.com/docs/auth/admin/verify-id-tokens

## 노트북 IP 변경 시

1. 서버 담당자가 새 IPv4 주소를 확인해 팀에 공유한다.
2. 해당 DB에 접속하는 각 백엔드의 backend/.env에서 DB_HOST만 변경하고 백엔드를 재시작한다.
   설정을 캐시하므로 실행 중 .env를 수정하는 것만으로는 반영되지 않는다.
   같은 노트북에서 MySQL과 백엔드를 실행하면 그 백엔드는 DB_HOST=127.0.0.1도 가능하다.
3. Workbench 연결의 Hostname도 새 주소로 변경한다. 스키마와 데이터는 IP 변경으로 바뀌지 않는다.
4. API도 그 노트북에서 실행한다면 Flutter의 공통 API 서버 주소를 새 주소로 변경한다.
   Flutter에는 MySQL 주소·계정·비밀번호를 넣지 않는다. DB만 다른 노트북으로 옮겼다면
   API 주소는 바꾸지 않는다. 현재 앱에는 연결할 공통 API 주소가 아직 구현되어 있지 않다.
5. 새 네트워크에서 포트 연결과 DB 로그인을 다시 확인한다. 노트북과 서버가 실행되어 있어야 한다.

같은 공유기를 계속 사용한다면 공유기 DHCP 주소 예약으로 노트북에 같은 IP를 할당할 수 있다.
다른 Wi-Fi에서는 예약이 유지되지 않으므로 다시 확인한다.
참고: https://www.tp-link.com/in/support/faq/182/
