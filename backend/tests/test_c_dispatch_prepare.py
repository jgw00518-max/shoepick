from unittest.mock import MagicMock
import pytest
from backend.features.c_dispatch import prepare_order_fulfillment
from backend.features.order_history import OrderReadError
EMPLOYEE={'employee_id':4,'roles':[{'role_code':'HQ_STAFF'}]}

def setup(deliveries=None,linked=None):
    db=MagicMock();cursor=db.cursor.return_value.__enter__.return_value
    cursor.fetchone.side_effect=[{'order_status':'PAID','pickup_branch_id':3},{'payment_id':2}]
    cursor.fetchall.side_effect=[[{'order_item_id':2,'quantity':2}],deliveries or [],linked or []]
    cursor.lastrowid=7
    return db,cursor

def run(db):return prepare_order_fulfillment(db,order_id=1,employee=EMPLOYEE)

def delivery(**changes):return {'fulfillment_id':7,'fulfillment_number':'original','destination_branch_id':3,'fulfillment_status':'PREPARING','shipped_at':None,**changes}

def test_create_and_no_transaction_completion():
    from uuid import UUID
    db,cursor=setup();result=run(db);assert result['created']
    assert len(result['fulfillment_number']) == 32
    assert UUID(hex=result['fulfillment_number']).version == 4
    assert cursor.executemany.call_args.args[1]==[(7,1,2,2)]
    assert 'FOR UPDATE' in cursor.execute.call_args_list[0].args[0]
    db.commit.assert_not_called();db.rollback.assert_not_called()

def test_reuse_preserves_number_and_no_insert():
    db,cursor=setup([delivery()],[{'order_id':1,'order_item_id':2,'quantity':2}])
    assert run(db)=={'fulfillment_id':7,'fulfillment_number':'original','created':False}
    assert not any('INSERT' in call.args[0] for call in cursor.execute.call_args_list)

@pytest.mark.parametrize('records',[[delivery(),delivery()],[delivery(fulfillment_status='CANCELED')],[delivery(fulfillment_status='IN_TRANSIT')],[delivery(shipped_at='server')],[delivery(destination_branch_id=4)],[delivery(arrived_at='server')]])
def test_unsafe_existing_delivery_blocked(records):
    db,cursor=setup(records)
    with pytest.raises(OrderReadError):run(db)
    cursor.executemany.assert_not_called()

@pytest.mark.parametrize('linked',[[],[{'order_id':1,'order_item_id':2,'quantity':1}],[{'order_id':2,'order_item_id':2,'quantity':2}]])
def test_partial_or_mismatched_items_blocked(linked):
    db,cursor=setup([delivery()],linked)
    with pytest.raises(OrderReadError):run(db)

def test_role_and_failed_write_do_not_commit():
    db,cursor=setup()
    with pytest.raises(OrderReadError) as exc:
        prepare_order_fulfillment(db,order_id=1,employee={'employee_id':4,'roles':[]})
    assert exc.value.status==403;cursor.execute.assert_not_called()
    cursor.executemany.side_effect=RuntimeError('failure')
    with pytest.raises(RuntimeError):run(db)
    db.commit.assert_not_called();db.rollback.assert_not_called()

@pytest.mark.parametrize('order',[None,{'order_status':'PREPARING','pickup_branch_id':3},{'order_status':'PAID','pickup_branch_id':None}])
def test_missing_or_invalid_order(order):
    db,cursor=setup();cursor.fetchone.side_effect=[order]
    with pytest.raises(OrderReadError):run(db)
    cursor.executemany.assert_not_called()

def test_missing_paid_record():
    db,cursor=setup();cursor.fetchone.side_effect=[{'order_status':'PAID','pickup_branch_id':3},None]
    with pytest.raises(OrderReadError):run(db)
    cursor.executemany.assert_not_called()
