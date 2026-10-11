from unittest.mock import MagicMock
import pytest
from backend.features.c_dispatch import record_dispatched_fulfillment
from backend.features.order_history import OrderReadError, transition_dispatched_order

EMPLOYEE = {'employee_id':4,'roles':[{'role_code':'HQ_STAFF'}]}

def setup():
    db=MagicMock(); c=db.cursor.return_value.__enter__.return_value
    c.fetchone.side_effect=[{'order_status':'PAID','pickup_branch_id':3},{'payment_id':2}]
    delivery=dict(fulfillment_id=7,destination_branch_id=3,fulfillment_status='PREPARING',shipped_at=None,arrived_at=None,inspected_at=None,completed_at=None)
    item=dict(order_item_id=2,product_variant_id=5,quantity=1)
    reservation=dict(order_item_id=2,product_variant_id=5,reserved_quantity=1,reservation_status='CONSUMED',consumed_at='server time')
    c.fetchall.side_effect=[[delivery],[item],[reservation],[dict(order_id=1,order_item_id=2,quantity=1)]]
    c.rowcount=1
    return db,c,delivery,item,reservation

def run(db,employee=EMPLOYEE):
    return record_dispatched_fulfillment(db,order_id=1,fulfillment_id=7,employee=employee)

def test_consumed_full_order_records_dispatch_without_inventory_writes_or_commit():
    db,c,*_=setup()
    assert run(db)['fulfillment_status']=='IN_TRANSIT'
    writes=[call.args[0] for call in c.execute.call_args_list if call.args[0].startswith(('INSERT','UPDATE'))]
    assert len(writes)==2 and 'CURRENT_TIMESTAMP' in writes[0]
    assert not any('UPDATE inventory' in sql or 'UPDATE orders' in sql for sql in writes)
    db.commit.assert_not_called();db.rollback.assert_not_called()


def connection_db():
    db,c,delivery,item,reservation=setup()
    c.fetchone.side_effect=[
        {'order_status':'PAID','pickup_branch_id':3},{'payment_id':2},
        {'order_status':'PAID','pickup_branch_id':3},{'payment_id':2},
        {'order_id':1,'destination_branch_id':3,'fulfillment_status':'IN_TRANSIT','shipped_at':'DB time'},
    ]
    return db,c,reservation


def connect_c_to_a(db):
    # D의 소비 함수 호출을 흉내 내지 않는다. 소비 기록 대체 응답 이후의 C/A만 검증한다.
    delivery=record_dispatched_fulfillment(db,order_id=1,fulfillment_id=7,employee=EMPLOYEE)
    return transition_dispatched_order(db,order_id=delivery['order_id'],
                                      fulfillment_id=delivery['fulfillment_id'],employee=EMPLOYEE)


def test_c_delivery_record_then_real_a_shipping_transition_on_same_connection():
    db,c,_=connection_db()
    assert connect_c_to_a(db)=={'order_id':1,'order_status':'SHIPPING','fulfillment_id':7}
    statements=[call.args[0] for call in c.execute.call_args_list]
    delivery_index=next(i for i,sql in enumerate(statements) if sql.startswith('UPDATE fulfillments'))
    order_index=next(i for i,sql in enumerate(statements) if sql.startswith('UPDATE orders'))
    assert delivery_index < order_index
    assert sum(sql.startswith('INSERT INTO fulfillment_status_history') for sql in statements)==1
    assert sum(sql.startswith('INSERT INTO order_status_history') for sql in statements)==1
    assert not any(sql.startswith('UPDATE inventory') for sql in statements)
    db.commit.assert_not_called();db.rollback.assert_not_called()


def test_missing_d_consumption_stops_before_a_order_transition():
    db,c,reservation=connection_db()
    reservation['reservation_status']='RESERVED'
    with pytest.raises(OrderReadError):connect_c_to_a(db)
    assert not any(call.args[0].startswith(('UPDATE','INSERT')) for call in c.execute.call_args_list)


def test_a_order_update_failure_reaches_top_level_rollback_after_c_delivery_write():
    db,c,_=connection_db()
    def execute(sql,args):
        if sql.startswith('UPDATE orders'):c.rowcount=0
    c.execute.side_effect=execute
    with pytest.raises(OrderReadError) as error:
        try:connect_c_to_a(db)
        except Exception:
            db.rollback()
            raise
    assert error.value.code=='INVALID_STATE_TRANSITION'
    db.rollback.assert_called_once();db.commit.assert_not_called()


def test_a_history_write_failure_is_not_reported_as_completed_dispatch():
    db,c,_=connection_db()
    def execute(sql,args):
        if sql.startswith('INSERT INTO order_status_history'):raise RuntimeError('simulated failure')
    c.execute.side_effect=execute
    with pytest.raises(RuntimeError):
        try:connect_c_to_a(db)
        except Exception:
            db.rollback()
            raise
    db.rollback.assert_called_once();db.commit.assert_not_called()

@pytest.mark.parametrize('field,value',[('reservation_status','RESERVED'),('consumed_at',None),('reserved_quantity',2),('product_variant_id',99)])
def test_missing_or_mismatched_d_consumption_blocks_writes(field,value):
    db,c,_,_,r=setup();r[field]=value
    with pytest.raises(OrderReadError):run(db)
    assert not any(call.args[0].startswith(('INSERT','UPDATE')) for call in c.execute.call_args_list)

@pytest.mark.parametrize('field,value',[('destination_branch_id',9),('fulfillment_status','IN_TRANSIT'),('shipped_at','time')])
def test_mismatched_or_already_dispatched_delivery_is_not_reprocessed(field,value):
    db,c,d,*_=setup();d[field]=value
    with pytest.raises(OrderReadError):run(db)
    db.commit.assert_not_called()

def test_branch_staff_cannot_execute():
    db,c,*_=setup()
    with pytest.raises(OrderReadError) as e:run(db,{'employee_id':4,'roles':[{'role_code':'BRANCH_STAFF'}]})
    assert e.value.status==403;c.execute.assert_not_called()

def test_history_failure_requires_caller_rollback():
    db,c,*_=setup()
    def execute(sql,args):
        if sql.startswith('INSERT INTO fulfillment_status_history'):raise RuntimeError('failure')
    c.execute.side_effect=execute
    with pytest.raises(RuntimeError):run(db)
    db.commit.assert_not_called();db.rollback.assert_not_called()
