"""제조사 접수 확인 시 발주 전량을 본사에 입고한다. 기존 DB 구조를 사용한다."""

import json
from datetime import datetime
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/goods-receipts", tags=["제조사 입고"])

RECEIPT_ACTION = 'PROCUREMENT_GOODS_RECEIVED'
ENTITY = 'PURCHASE_REQUISITION'


class ReceivedItem(BaseModel):
    product_variant_id: int
    received_quantity: int
    on_hand_after: int


class GoodsReceiptResult(BaseModel):
    audit_log_id: int
    order_audit_log_id: int
    received_at: datetime
    total_received_quantity: int
    items: list[ReceivedItem]


def _conflict(message):
    raise HTTPException(409, detail={'code':'INVALID_STATE','message':message})


def read_receipt(cursor, requisition_id):
    cursor.execute('SELECT audit_log_id,after_data,created_at FROM audit_logs '
        'WHERE entity_type=%s AND entity_id=%s AND action_code=%s ORDER BY audit_log_id DESC LIMIT 1 FOR UPDATE',
        (ENTITY,requisition_id,RECEIPT_ACTION))
    row=cursor.fetchone()
    if row is None:return None
    payload=json.loads(row['after_data']) if isinstance(row['after_data'],(str,bytes)) else row['after_data']
    return GoodsReceiptResult(audit_log_id=row['audit_log_id'], received_at=row['created_at'],
        **{key:payload[key] for key in ('order_audit_log_id','total_received_quantity','items')})


def receive_full_order(cursor, *, requisition_id, order_audit_log_id, items, employee_id, request_id):
    """호출자가 부모 품의를 잠근다. commit 없이 접수 기록과 함께 저장한다."""
    if read_receipt(cursor,requisition_id) is not None:
        _conflict('이미 입고 기록이 있는 발주입니다.')
    ids=[item.product_variant_id for item in items]
    if not items or len(ids)!=len(set(ids)):
        _conflict('입고할 발주 품목을 확인해주세요.')
    if any(not 0<item.requested_quantity<=2147483647 for item in items):
        _conflict('입고 수량이 재고 이력에 저장 가능한 범위를 벗어났습니다.')
    received=[]
    for item in sorted(items,key=lambda item:item.product_variant_id):
        variant_id=item.product_variant_id
        # 기존 품목은 판매 중지돼도 입고 가능하다. 삭제된 옵션은 FK와 별도로 검사한다.
        cursor.execute('SELECT product_variant_id FROM product_variants WHERE product_variant_id=%s FOR SHARE',(variant_id,))
        if cursor.fetchone() is None:_conflict('발주 제품 옵션이 존재하지 않습니다.')
        cursor.execute('SELECT inventory_movement_id FROM inventory_movements WHERE reference_type=%s AND reference_id=%s '
            'AND product_variant_id=%s AND movement_type=%s LIMIT 1 FOR UPDATE',
            (ENTITY,requisition_id,variant_id,'PROCUREMENT_RECEIPT'))
        if cursor.fetchone() is not None:_conflict('기존 입고 이력이 있는 발주입니다.')
        cursor.execute('INSERT INTO headquarters_inventory (product_variant_id,on_hand_quantity,reserved_quantity,defective_quantity) '
            'VALUES (%s,0,0,0) ON DUPLICATE KEY UPDATE product_variant_id=VALUES(product_variant_id)',(variant_id,))
        cursor.execute('SELECT on_hand_quantity,reserved_quantity,defective_quantity FROM headquarters_inventory '
            'WHERE product_variant_id=%s FOR UPDATE',(variant_id,))
        balance=cursor.fetchone()
        after=balance['on_hand_quantity']+item.requested_quantity
        if after>4294967295:_conflict('본사 재고 수량이 저장 가능한 범위를 초과합니다.')
        cursor.execute('UPDATE headquarters_inventory SET on_hand_quantity=%s WHERE product_variant_id=%s',(after,variant_id))
        cursor.execute('INSERT INTO inventory_movements (product_variant_id,movement_type,on_hand_delta,reserved_delta,'
            'defective_delta,on_hand_after,reserved_after,defective_after,reference_type,reference_id,idempotency_key,'
            'reason,created_by_employee_id) VALUES (%s,%s,%s,0,0,%s,%s,%s,%s,%s,%s,%s,%s)',
            (variant_id,'PROCUREMENT_RECEIPT',item.requested_quantity,after,balance['reserved_quantity'],
             balance['defective_quantity'],ENTITY,requisition_id,f'procurement-receipt:{order_audit_log_id}:{variant_id}',
             '제조사 접수 확인에 따른 발주 전량 자동 입고',employee_id))
        received.append(ReceivedItem(product_variant_id=variant_id,received_quantity=item.requested_quantity,on_hand_after=after))
    payload={'schema_version':1,'order_audit_log_id':order_audit_log_id,
        'total_received_quantity':sum(item.received_quantity for item in received),
        'items':[item.model_dump() for item in received],'receipt_method':'AUTO_ON_ACCEPTANCE'}
    cursor.execute("INSERT INTO audit_logs (actor_type,actor_employee_id,action_code,entity_type,entity_id,after_data,request_id) "
        "VALUES ('EMPLOYEE',%s,%s,%s,%s,%s,%s)",(employee_id,RECEIPT_ACTION,ENTITY,requisition_id,json.dumps(payload,ensure_ascii=False),request_id))
    receipt_id=cursor.lastrowid
    cursor.execute('SELECT created_at FROM audit_logs WHERE audit_log_id=%s',(receipt_id,))
    return GoodsReceiptResult(audit_log_id=receipt_id,order_audit_log_id=order_audit_log_id,
        received_at=cursor.fetchone()['created_at'],total_received_quantity=payload['total_received_quantity'],items=received)
