"""기존 audit_logs에 제조사 발주를 등록한다. 외부 전송은 수행하지 않는다."""

import json
from datetime import datetime
from typing import Annotated, Literal
from fastapi import APIRouter, HTTPException, Depends, Query, Path
from pydantic import BaseModel, ConfigDict, StringConstraints
from pymysql.connections import Connection
from pymysql.cursors import DictCursor
from .authentication import AuthRoute, AuthError, current_employee
from .goods_receipts import GoodsReceiptResult, receive_full_order, read_receipt

if __package__ == 'backend.features':
    from ..dependencies import get_db
else:
    from dependencies import get_db

router = APIRouter(prefix="/manufacturer-orders", tags=["제조사 발주"], route_class=AuthRoute)

ORDER_ACTION = 'PROCUREMENT_ORDER_PLACED'
ORDER_ENTITY = 'PURCHASE_REQUISITION'
RECEPTION_ACTION = 'PROCUREMENT_ORDER_RECEPTION'


class ReceptionRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    decision: Literal['ACCEPTED', 'REJECTED']
    confirmation_method: Literal['PHONE', 'EMAIL', 'OTHER']
    comment: Annotated[str, StringConstraints(strip_whitespace=True, max_length=2000)] = ''
    request_id: Annotated[str, StringConstraints(pattern=r'^[A-Za-z0-9_-]{16,100}$')]


class ReceptionResult(BaseModel):
    audit_log_id: int
    order_audit_log_id: int
    decision: Literal['ACCEPTED', 'REJECTED']
    confirmation_method: Literal['PHONE', 'EMAIL', 'OTHER']
    comment: str
    recorded_by_employee_id: int
    recorded_by_name: str | None = None
    recorded_at: datetime
    goods_receipt: GoodsReceiptResult | None = None


class ReceptionResponse(BaseModel):
    data: ReceptionResult


class OrderItem(BaseModel):
    purchase_requisition_item_id: int
    product_variant_id: int
    product_code: str
    product_name: str
    color_name: str
    size_mm: int
    requested_quantity: int


class OrderSnapshot(BaseModel):
    order_number: str
    purchase_requisition_id: int
    title: str
    reason: str
    manufacturer_id: int
    manufacturer_name: str
    total_requested_quantity: int
    items: list[OrderItem]
    transmission_status: Literal['NOT_SENT']


class OrderSummary(BaseModel):
    audit_log_id: int
    purchase_requisition_id: int
    order_number: str
    title: str
    manufacturer_id: int
    manufacturer_name: str
    total_requested_quantity: int
    item_count: int
    transmission_status: str
    registered_at: datetime
    registered_by_employee_id: int | None
    registered_by_name: str | None
    requested_by_employee_id: int
    requested_by_name: str
    requisition_status: str
    reception_status: Literal['PENDING', 'ACCEPTED', 'REJECTED'] = 'PENDING'
    reception: ReceptionResult | None = None
    can_record_reception: bool = False
    goods_receipt: GoodsReceiptResult | None = None


class OrderDetail(OrderSummary):
    reason: str
    items: list[OrderItem]


class OrderPagination(BaseModel):
    page: int
    page_size: int
    total_count: int


class OrderListResponse(BaseModel):
    data: list[OrderSummary]
    pagination: OrderPagination


class OrderDetailResponse(BaseModel):
    data: OrderDetail


def _read_scope(employee):
    roles = {role['role_code'] for role in employee.get('roles', [])}
    if not roles & {'HQ_STAFF', 'TEAM_LEAD', 'DIRECTOR', 'EXECUTIVE', 'ADMIN'}:
        raise AuthError('FORBIDDEN')
    return bool(roles & {'TEAM_LEAD', 'DIRECTOR', 'EXECUTIVE', 'ADMIN'})


ORDER_JOIN = (' FROM audit_logs a JOIN purchase_requisitions pr ON pr.purchase_requisition_id=a.entity_id '
    'JOIN employees author ON author.employee_id=pr.requested_by_employee_id '
    'LEFT JOIN employees actor ON actor.employee_id=a.actor_employee_id ')
ORDER_FIELDS = ('a.audit_log_id,a.after_data,a.created_at AS registered_at,'
    'a.actor_employee_id AS registered_by_employee_id,actor.employee_name AS registered_by_name,'
    'pr.requested_by_employee_id,author.employee_name AS requested_by_name,pr.requisition_status,'
    "(SELECT JSON_OBJECT('audit_log_id',r.audit_log_id,'payload',r.after_data,"
    "'recorded_at',CAST(r.created_at AS CHAR),"
    "'recorded_by_employee_id',r.actor_employee_id,'recorded_by_name',re.employee_name) "
    'FROM audit_logs r LEFT JOIN employees re ON re.employee_id=r.actor_employee_id '
    "WHERE r.entity_type='PURCHASE_REQUISITION' AND r.entity_id=a.entity_id "
    "AND r.action_code='PROCUREMENT_ORDER_RECEPTION' ORDER BY r.audit_log_id DESC LIMIT 1) AS reception_data,"
    "(SELECT JSON_OBJECT('audit_log_id',g.audit_log_id,'payload',g.after_data,"
    "'received_at',CAST(g.created_at AS CHAR)) FROM audit_logs g "
    "WHERE g.entity_type='PURCHASE_REQUISITION' AND g.entity_id=a.entity_id "
    "AND g.action_code='PROCUREMENT_GOODS_RECEIVED' ORDER BY g.audit_log_id DESC LIMIT 1) AS goods_receipt_data")


def _conditions(employee):
    all_orders = _read_scope(employee)
    conditions = ['a.entity_type=%s', 'a.action_code=%s']
    params = [ORDER_ENTITY, ORDER_ACTION]
    if not all_orders:
        conditions.append('pr.requested_by_employee_id=%s')
        params.append(employee['employee_id'])
    return conditions, params


def _can_record(employee, author_id):
    roles = {role['role_code'] for role in employee.get('roles', [])}
    return bool(roles & {'TEAM_LEAD', 'DIRECTOR', 'ADMIN'} or
                ('HQ_STAFF' in roles and employee['employee_id'] == author_id))


def _reception_from_json(raw):
    data = json.loads(raw) if isinstance(raw, (str, bytes)) else raw
    payload = data['payload']
    if isinstance(payload, str):
        payload = json.loads(payload)
    return ReceptionResult(**{key: value for key, value in data.items() if key != 'payload'},
        **{key: payload[key] for key in ('order_audit_log_id', 'decision', 'confirmation_method', 'comment')})


def _order_from_row(row, employee):
    raw = row['after_data']
    snapshot = OrderSnapshot.model_validate(json.loads(raw) if isinstance(raw, (str, bytes)) else raw)
    if snapshot.purchase_requisition_id <= 0:
        raise ValueError('Invalid order snapshot')
    reception = _reception_from_json(row['reception_data']) if row.get('reception_data') else None
    receipt = None
    if row.get('goods_receipt_data'):
        raw_receipt = row['goods_receipt_data']
        receipt_data = json.loads(raw_receipt) if isinstance(raw_receipt,(str,bytes)) else raw_receipt
        payload = receipt_data['payload']
        if isinstance(payload,str):payload=json.loads(payload)
        receipt = GoodsReceiptResult(audit_log_id=receipt_data['audit_log_id'],received_at=receipt_data['received_at'],
            **{key:payload[key] for key in ('order_audit_log_id','total_received_quantity','items')})
    if reception:reception.goods_receipt=receipt
    return OrderDetail(**snapshot.model_dump(), item_count=len(snapshot.items), reception=reception,
        goods_receipt=receipt,
        reception_status=reception.decision if reception else 'PENDING',
        can_record_reception=reception is None and row['requisition_status']=='ORDERED' and
            _can_record(employee, row['requested_by_employee_id']),
        **{key: value for key, value in row.items() if key not in ('after_data', 'reception_data','goods_receipt_data')})


@router.get('', response_model=OrderListResponse, summary='권한별 제조사 발주 목록 조회')
def get_orders(employee: Annotated[dict, Depends(current_employee)], db: Annotated[Connection, Depends(get_db)],
    page: Annotated[int, Query(ge=1)]=1, page_size: Annotated[int, Query(ge=1, le=100)]=20,
    order: Literal['asc', 'desc']='desc', keyword: Annotated[str | None, Query(max_length=150)]=None):
    conditions, params = _conditions(employee)
    if keyword and keyword.strip():
        escaped = keyword.strip().replace('!', '!!').replace('%', '!%').replace('_', '!_')
        conditions.append("(JSON_UNQUOTE(JSON_EXTRACT(a.after_data,'$.manufacturer_name')) LIKE %s ESCAPE '!' "
            "OR JSON_UNQUOTE(JSON_EXTRACT(a.after_data,'$.title')) LIKE %s ESCAPE '!' "
            "OR JSON_UNQUOTE(JSON_EXTRACT(a.after_data,'$.order_number')) LIKE %s ESCAPE '!')")
        params.extend([f'%{escaped}%'] * 3)
    where = ' WHERE ' + ' AND '.join(conditions)
    direction = {'asc':'ASC', 'desc':'DESC'}[order]
    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT COUNT(*) AS total_count'+ORDER_JOIN+where, tuple(params))
        total_count = cursor.fetchone()['total_count']
        cursor.execute('SELECT '+ORDER_FIELDS+ORDER_JOIN+where+
            f' ORDER BY a.created_at {direction},a.audit_log_id {direction} LIMIT %s OFFSET %s',
            tuple(params)+(page_size,(page-1)*page_size))
        rows = [OrderSummary.model_validate(_order_from_row(row, employee).model_dump()) for row in cursor.fetchall()]
    return OrderListResponse(data=rows, pagination=OrderPagination(page=page,page_size=page_size,total_count=total_count))


@router.get('/{audit_log_id}', response_model=OrderDetailResponse, summary='제조사 발주 당시 상세 조회')
def get_order(audit_log_id: Annotated[int, Path(gt=0)], employee: Annotated[dict, Depends(current_employee)],
    db: Annotated[Connection, Depends(get_db)]):
    conditions, params = _conditions(employee)
    conditions.append('a.audit_log_id=%s'); params.append(audit_log_id)
    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT '+ORDER_FIELDS+ORDER_JOIN+' WHERE '+' AND '.join(conditions), tuple(params))
        row = cursor.fetchone()
        if row is None:
            raise HTTPException(404, detail={'code':'NOT_FOUND','message':'조회 가능한 발주 내역을 찾을 수 없습니다.'})
        return OrderDetailResponse(data=_order_from_row(row, employee))


@router.post('/{audit_log_id}/reception', response_model=ReceptionResponse, summary='제조사 접수 확인 시 전체 자동 입고·거절 기록')
def record_reception(audit_log_id: Annotated[int, Path(gt=0)], request: ReceptionRequest,
    employee: Annotated[dict, Depends(current_employee)], db: Annotated[Connection, Depends(get_db)]):
    conditions, params = _conditions(employee)
    if request.decision == 'REJECTED' and not request.comment:
        raise HTTPException(400, detail={'code':'INVALID_INPUT','message':'접수 거절 사유를 입력해주세요.'})
    conditions.append('a.audit_log_id=%s'); params.append(audit_log_id)
    try:
        with db.cursor(DictCursor) as cursor:
            # 부모 품의를 먼저 잠가 승인·발주·접수 기록의 쓰기 순서를 통일한다.
            cursor.execute('SELECT a.entity_id'+ORDER_JOIN+' WHERE '+' AND '.join(conditions), tuple(params))
            ref = cursor.fetchone()
            if ref is None:
                raise HTTPException(404, detail={'code':'NOT_FOUND','message':'조회 가능한 발주 내역을 찾을 수 없습니다.'})
            cursor.execute('SELECT requisition_status,requested_by_employee_id FROM purchase_requisitions '
                'WHERE purchase_requisition_id=%s FOR UPDATE', (ref['entity_id'],))
            document = cursor.fetchone()
            if document is None:
                raise HTTPException(404, detail={'code':'NOT_FOUND','message':'발주 근거 품의를 찾을 수 없습니다.'})
            if not _can_record(employee, document['requested_by_employee_id']):
                raise AuthError('FORBIDDEN')
            if document['requisition_status'] != 'ORDERED':
                _invalid_order('발주 완료 상태에서만 제조사 접수 결과를 기록할 수 있습니다.')
            # locking read로 최신 접수 기록을 읽는다(동시 요청과 repeatable read 대응).
            cursor.execute('SELECT r.audit_log_id,r.after_data,r.request_id,r.created_at,r.actor_employee_id,'
                'e.employee_name FROM audit_logs r LEFT JOIN employees e ON e.employee_id=r.actor_employee_id '
                'WHERE r.entity_type=%s AND r.entity_id=%s AND r.action_code=%s '
                'ORDER BY r.audit_log_id DESC LIMIT 1 FOR UPDATE', (ORDER_ENTITY, ref['entity_id'], RECEPTION_ACTION))
            previous = cursor.fetchone()
            payload = {'schema_version':1, 'order_audit_log_id':audit_log_id,
                'decision':request.decision,'confirmation_method':request.confirmation_method,'comment':request.comment}
            if previous:
                old = json.loads(previous['after_data']) if isinstance(previous['after_data'], (str, bytes)) else previous['after_data']
                if previous['request_id'] != request.request_id or old != payload or previous['actor_employee_id'] != employee['employee_id']:
                    _invalid_order('이미 제조사 접수 결과가 기록되었습니다. 상세 내용을 다시 확인해주세요.')
                result = ReceptionResult(audit_log_id=previous['audit_log_id'],
                    **{key:payload[key] for key in ('order_audit_log_id','decision','confirmation_method','comment')},
                    recorded_by_employee_id=previous['actor_employee_id'], recorded_by_name=previous['employee_name'],
                    recorded_at=previous['created_at'])
                if request.decision == 'ACCEPTED':
                    result.goods_receipt = read_receipt(cursor,ref['entity_id'])
            else:
                goods_receipt = None
                if request.decision == 'ACCEPTED':
                    cursor.execute('SELECT after_data FROM audit_logs WHERE audit_log_id=%s AND entity_type=%s '
                        'AND entity_id=%s AND action_code=%s FOR UPDATE',(audit_log_id,ORDER_ENTITY,ref['entity_id'],ORDER_ACTION))
                    order_row=cursor.fetchone()
                    if order_row is None:_invalid_order('발주 원본을 찾을 수 없습니다.')
                    raw=order_row['after_data']
                    order=OrderSnapshot.model_validate(json.loads(raw) if isinstance(raw,(str,bytes)) else raw)
                    if order.purchase_requisition_id!=ref['entity_id'] or sum(item.requested_quantity for item in order.items)!=order.total_requested_quantity:
                        _invalid_order('발주 원본의 품의와 수량을 확인해주세요.')
                    goods_receipt=receive_full_order(cursor,requisition_id=ref['entity_id'],order_audit_log_id=audit_log_id,
                        items=order.items,employee_id=employee['employee_id'],request_id=request.request_id)
                cursor.execute("INSERT INTO audit_logs (actor_type,actor_employee_id,action_code,entity_type,entity_id,after_data,request_id) "
                    "VALUES ('EMPLOYEE',%s,%s,%s,%s,%s,%s)", (employee['employee_id'],RECEPTION_ACTION,ORDER_ENTITY,
                    ref['entity_id'],json.dumps(payload,ensure_ascii=False),request.request_id))
                reception_id = cursor.lastrowid
                cursor.execute('SELECT a.created_at,e.employee_name FROM audit_logs a LEFT JOIN employees e '
                    'ON e.employee_id=a.actor_employee_id WHERE a.audit_log_id=%s', (reception_id,))
                saved = cursor.fetchone()
                result = ReceptionResult(audit_log_id=reception_id,
                    **{key:payload[key] for key in ('order_audit_log_id','decision','confirmation_method','comment')},
                    recorded_by_employee_id=employee['employee_id'],recorded_by_name=saved['employee_name'],recorded_at=saved['created_at'],
                    goods_receipt=goods_receipt)
        db.commit()
        return ReceptionResponse(data=result)
    except Exception:
        db.rollback()
        raise


class ManufacturerOrderRegistered(BaseModel):
    audit_log_id: int
    purchase_requisition_id: int
    order_number: str
    manufacturer_id: int
    manufacturer_name: str
    total_requested_quantity: int
    registered_at: datetime
    transmission_status: str = 'NOT_SENT'


def _invalid_order(message):
    raise HTTPException(409, detail={'code': 'INVALID_STATE', 'message': message})


def register_approved_order(cursor, *, document, employee_id: int) -> ManufacturerOrderRegistered:
    """호출자가 품의를 FOR UPDATE로 잠그고 이사 승인 직후 호출한다.

    commit하지 않는다. 승인·발주 기록·ORDERED 상태는 호출자가 함께 저장한다.
    모든 발주 작성은 같은 품의 잠금으로 직렬화해야 한다(audit_logs에는 UNIQUE가 없음).
    """
    if document.requisition_status != 'PENDING_DIRECTOR':
        _invalid_order('이사 최종 승인 대상 품의만 자동 발주할 수 있습니다.')
    cursor.execute(
        'SELECT audit_log_id FROM audit_logs WHERE entity_type=%s AND entity_id=%s '
        'AND action_code=%s LIMIT 1 FOR UPDATE',
        (ORDER_ENTITY, document.purchase_requisition_id, ORDER_ACTION),
    )
    if cursor.fetchone() is not None:
        _invalid_order('이미 발주 기록이 있는 품의입니다.')
    if not document.items or any(item.requested_quantity <= 0 for item in document.items):
        _invalid_order('발주할 품목과 수량을 확인해주세요.')
    manufacturers = {item.manufacturer_id for item in document.items}
    if None in manufacturers or len(manufacturers) != 1:
        _invalid_order('발주 품목은 하나의 제조사에 속해야 합니다.')
    manufacturer_id = next(iter(manufacturers))
    cursor.execute('SELECT manufacturer_id, manufacturer_name FROM manufacturers WHERE manufacturer_id=%s FOR SHARE',
                   (manufacturer_id,))
    manufacturer = cursor.fetchone()
    if manufacturer is None:
        _invalid_order('발주 제조사 정보를 확인해주세요.')
    ids = [item.product_variant_id for item in document.items]
    placeholders = ','.join(['%s'] * len(ids))
    cursor.execute(
        'SELECT pv.product_variant_id FROM product_variants pv JOIN products p ON p.product_id=pv.product_id '
        f'WHERE pv.product_variant_id IN ({placeholders}) AND pv.is_active=1 AND p.is_active=1 '
        'AND p.manufacturer_id=%s FOR SHARE', tuple(ids) + (manufacturer_id,),
    )
    if {row['product_variant_id'] for row in cursor.fetchall()} != set(ids):
        _invalid_order('발주할 제품의 판매 상태와 제조사를 확인해주세요.')
    order_number = f'PO-{document.purchase_requisition_id:06d}'
    snapshot = {
        'schema_version': 1,
        'order_number': order_number,
        'purchase_requisition_id': document.purchase_requisition_id,
        'title': document.title,
        'reason': document.reason,
        'branch_id': document.branch_id,
        'requested_by_employee_id': document.requested_by_employee_id,
        'manufacturer_id': manufacturer_id,
        'manufacturer_name': manufacturer['manufacturer_name'],
        'items': [item.model_dump(mode='json') for item in document.items],
        'total_requested_quantity': sum(item.requested_quantity for item in document.items),
        'registration_method': 'DIRECTOR_APPROVAL',
        'transmission_status': 'NOT_SENT',
    }
    cursor.execute(
        "INSERT INTO audit_logs (actor_type, actor_employee_id, action_code, entity_type, entity_id, "
        "before_data, after_data, request_id) VALUES ('EMPLOYEE',%s,%s,%s,%s,%s,%s,%s)",
        (employee_id, ORDER_ACTION, ORDER_ENTITY, document.purchase_requisition_id,
         json.dumps({'requisition_status': 'PENDING_DIRECTOR'}),
         json.dumps(snapshot, ensure_ascii=False), f'procurement-order:{document.purchase_requisition_id}'),
    )
    audit_log_id = cursor.lastrowid
    cursor.execute('SELECT created_at FROM audit_logs WHERE audit_log_id=%s', (audit_log_id,))
    registered_at = cursor.fetchone()['created_at']
    return ManufacturerOrderRegistered(audit_log_id=audit_log_id,
        purchase_requisition_id=document.purchase_requisition_id, order_number=order_number,
        manufacturer_id=manufacturer_id, manufacturer_name=manufacturer['manufacturer_name'],
        total_requested_quantity=snapshot['total_requested_quantity'], registered_at=registered_at)
