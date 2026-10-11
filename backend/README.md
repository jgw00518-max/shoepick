# FastAPI 파일 구성

## 고객 주문 생성과 30분 결제 대기 (2026-10-10)

`POST /api/v1/orders`에 Firebase ID 토큰을 `Authorization: Bearer <ID_TOKEN>`으로 전달한다.
고객 ID와 상품 가격은 서버에서 조회하며, 쿠폰·적립금 적용은 이번 API에 포함하지 않는다.

```json
{
  "branch_id": 1,
  "order_request_key": "새 주문마다 생성하는 고유 식별자",
  "items": [{"product_variant_id": 1, "quantity": 2}]
}
```

주문·항목·D의 재고 예약·생성 이력을 함께 저장한다. 실패하면 전체 rollback한다.
성공 응답 `data`는 `order_id`, `order_number`, `order_status`, `paid_total`, `expires_at`이다.
`expires_at`은 DB 시간 기준이며 기존 DB의 DATETIME처럼 시간대 표시가 없다.
같은 요청 식별자로 같은 고객·대리점·품목을 재전송하면 기존 주문을 반환하고
재고를 추가 예약하거나 만료 시각을 연장하지 않는다. 다른 내용은 HTTP 409다.

모의 결제 `POST /api/v1/orders/{order_id}/mock-payment`에도 고객 ID 토큰이 필요하다.
본인 주문과 유효한 재고 예약을 검사하며, 30분이 지난 미결제 주문은
`CANCELED`로 변경하고 재고를 해제한 뒤 HTTP 409/PAYMENT_EXPIRED를 반환한다.
결제 성공 후에는 결제 대기 만료 작업이 예약을 해제하지 않는다.

앱을 닫은 고객의 주문도 정리하려면 서버와 별도 터미널에서 다음 작업을 실행한다.

```powershell
python -m backend.expire_pending_orders
```

30초마다 최대 100건을 처리한다. 만료된 예약은 주기 작업 시점에 반환되며,
만료 직후부터 결제는 차단된다. 작업을 중단하면 주기 정리도 중단된다.
1회 실행은 `python -m backend.expire_pending_orders --once`다.
결제와 정리 작업은 같은 주문을 잠가 먼저 처리된 상태를 다시 검사한다.
공용 DB에서 실행하면 실제 만료 주문이 취소되므로 테스트 DB에서 먼저 검증한다.
기존 주문 조회 API의 인증·권한 적용과 직원 결제 확인은 별도 후속 작업이다.

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
본사 재고 조회를 구현했으며, 나머지 업무 엔드포인트와 SQL은 미구현이다.
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

직원 앱은 Android 에뮬레이터에서 `http://10.0.2.2:8000`으로 접속한다.
이는 에뮬레이터에서 PC의 loopback 서버에 접근하는 주소이므로,
FastAPI의 실행 주소와 MySQL의 DB_HOST는 `10.0.2.2`로 바꾸지 않는다.
브라우저용 CORS 미들웨어는 사용하지 않는다.

## 본사 재고 조회

`GET /api/v1/inventory/headquarters`

- `page`: 기본 1, 최소 1
- `page_size`: 기본 20, 최대 100
- `keyword`: 상품명 또는 상품 코드 검색
- `product_variant_id`: 특정 상품 옵션 조회
- `sort`: updated_at(기본), product_code, product_name, available_quantity
- `order`: desc(기본) 또는 asc

응답은 `data` 목록과 `pagination:{page,page_size,total_count}`로 구성한다.
실물·예약·불량·가용 수량과 상품명·색상·사이즈를 반환한다.
가용 수량은 기존 DB 생성 컬럼을 사용한다. 비활성 상품도 조회한다.
재고 행이 없는 옵션은 제외하고, 조회 결과가 없으면 HTTP 200과 빈 목록을 반환한다.
`updated_at`은 기존 DB의 DATETIME 값이며 시간대 변환은 하지 않는다.
현재 직원 인증·권한 연동은 미구현이며 담당 B의 공통 의존성을 연결해야 한다.

## 대리점 보관 현황 조회

`GET /api/v1/inventory/branches/{branch_id}`

`pickup_holdings`를 기준으로 주문 품목·출고·대리점 정보를 연결한다.
상품명·코드·색상·사이즈는 주문 당시 `order_items` 값을 사용한다.
응답은 `data`와 `pagination`이며 total_count는 상품 종류 수가 아니라 보관 기록 수다.

- `page`, `page_size`, `keyword`, `product_variant_id`: 본사 조회와 동일
- `holding_status`: AWAITING_ARRIVAL, INSPECTING, READY_FOR_PICKUP, PICKED_UP,
  RECALLING, RETURNED_TO_HQ, DAMAGED, CANCELED 중 하나
- `sort`: updated_at(기본), received_at, product_code, product_name, holding_status
- `order`: desc(기본), asc

상태 미지정 시 전체 보관 이력을 조회한다. quantity 합계가 현재 실물 재고를 의미하지 않는다.
고객 수령 대기 상품만 조회하려면 `?holding_status=READY_FOR_PICKUP`을 지정한다.
없는 대리점은 HTTP 404/NOT_FOUND, 있는 대리점의 결과 없음은 HTTP 200/data:[]를 반환한다.
조회만 제공하며 입고·수령 상태를 변경하지 않는다. 직원 인증·소속 지점 권한은 아직 미연동이다.

## 주문 재고 확보·해제

`features/inventory.py`의 공용 Python 함수다. 주문 담당 A가 인증·주문 소유 관계를
검증한 뒤 같은 DB 연결로 호출한다. 아직 외부 POST API나 주문 처리 자동 연결은 추가하지 않았다.

```python
from backend.features.inventory import reserve_order_inventory, release_order_inventory

# 확보 시점과 만료 시각은 주문 담당이 결정한다.
result = reserve_order_inventory(
    db, order_id=order_id, expires_at=reservation_expires_at,
)

# 결제 완료 주문은 주문 담당이 취소 상태를 반영한 뒤 같은 연결로 호출한다.
result = release_order_inventory(db, order_id=order_id, reason="주문 취소")
```

- 확보: PENDING_PAYMENT/PAID/PREPARING 주문의 DB 품목 수량을 예약한다.
- 해제: PENDING_PAYMENT/CANCELED 주문의 RESERVED 예약 전체를 해제한다.
- 두 기능 모두 실제 출고 이력이 있으면 차단한다. 출고에 소비한 예약은 해제하지 않는다.
- 실물 수량은 유지하고 headquarters_inventory.reserved_quantity만 증감한다.
- inventory_reservations와 inventory_movements를 함께 저장한다.
- 같은 주문의 반복 요청은 추가 증감·이력을 만들지 않고 changed=False를 반환한다.
- 이미 확보된 예약의 만료 시각은 변경하지 않으며, 해제·소비된 예약을 다시 확보하지 않는다.
- expires_at은 DB에서 필수다. DB 시간 기준의 timezone 없는 datetime을 전달한다.
  신규 예약은 DB 현재 시각보다 미래여야 한다. 임의의 유효 기간이나 자동 만료 작업은 추가하지 않았다.
- 주문·품목·예약·재고를 잠그고 SKU 잠금 순서를 통일한다.
- 함수 실패 시 savepoint로 함수 내부 변경을 되돌린다. 함수는 commit하지 않는다.
  호출자는 전체 업무 성공 후 commit, 실패 시 전체 rollback을 수행해야 한다.
  autocommit=True 연결은 허용하지 않는다. 출고 등 다른 담당의 변경도 같은 잠금 규칙을 따라야 한다.

결과는 order_id, changed, reservations다. API 응답에 사용할 때는
`{"data": result.model_dump(mode="json")}`으로 변환할 수 있다.

## DB 연결과 담당 간 호출

패키지 실행 시 `from ..dependencies import get_db`로 가져와 `Depends(get_db)`에 연결한다.
다른 기능의 업무 함수를 호출할 때는 동일한 DB 연결을 전달한다.
예를 들어 제조사 입고 문서 저장과 재고 증가는 하나의 트랜잭션으로 처리하고,
최상위 업무 함수가 성공 시 한 번 commit한다. 예외가 나면 `get_db`가 rollback한다.

성공 응답은 `data`, 실패 응답은 `error.code`와 `error.message`를 사용한다.
요청 검증 오류는 HTTP 400/INVALID_INPUT, MySQL 오류는 HTTP 500/INTERNAL_ERROR로 반환한다.
인증·권한 검사는 담당 B의 공통 기능을 연결한 후 업무 API에 적용한다.
