from unittest.mock import MagicMock
import pytest
from fastapi import HTTPException
from backend.features.inventory import consume_order_inventory

def setup(consumed=False):
    db=MagicMock();db.get_autocommit.return_value=False
    c=db.cursor.return_value.__enter__.return_value;c.rowcount=1
    order={'order_id':1,'order_status':'PAID'}
    reservation=dict(inventory_reservation_id=3,order_id=1,order_item_id=2,product_variant_id=4,
                     reserved_quantity=2,reservation_status='CONSUMED' if consumed else 'RESERVED',consumed_at='time' if consumed else None)
    balance=dict(product_variant_id=4,on_hand_quantity=10,reserved_quantity=2,defective_quantity=0,available_quantity=8)
    c.fetchone.side_effect=[order,{'payment_id':1},{'inventory_movement_id':9}] if consumed else [order,{'payment_id':1},None,balance]
    c.fetchall.side_effect=[[dict(order_item_id=2,product_variant_id=4,quantity=2)],[reservation],[]]
    return db,c,order,reservation,balance

def run(db):return consume_order_inventory(db,order_id=1,employee_id=4)

def test_full_consumption_changes_physical_and_reserved_and_records_actor():
    db,c,_,_,balance=setup()
    assert run(db).changed
    assert balance['on_hand_quantity']==8 and balance['reserved_quantity']==0
    movement=next(call for call in c.execute.call_args_list if call.args[0].startswith('INSERT INTO inventory_movements'))
    assert movement.args[1][1:3]==(-2,-2)
    assert movement.args[1][-1]==4
    db.commit.assert_not_called();db.rollback.assert_not_called()

def test_replay_with_matching_history_does_not_change_inventory_again():
    db,c,*_=setup(True)
    assert not run(db).changed
    assert not any(call.args[0].startswith(('UPDATE','INSERT')) for call in c.execute.call_args_list)

@pytest.mark.parametrize('status',['CANCELED','COMPLETED','PENDING_PAYMENT'])
def test_wrong_order_state(status):
    db,c,order,*_=setup();order['order_status']=status
    with pytest.raises(HTTPException):run(db)
    assert not any(call.args[0].startswith('UPDATE') for call in c.execute.call_args_list)

@pytest.mark.parametrize('changes',[dict(reserved_quantity=1),dict(reservation_status='RELEASED'),dict(consumed_at='old')])
def test_invalid_reservation_blocks_all_writes(changes):
    db,c,_,r,_=setup();r.update(changes)
    with pytest.raises(HTTPException):run(db)
    assert not any(call.args[0].startswith(('UPDATE','INSERT')) for call in c.execute.call_args_list)

def test_insufficient_reserved_quantity():
    db,c,_,_,b=setup();b['reserved_quantity']=1
    with pytest.raises(HTTPException):run(db)
    assert not any(call.args[0].startswith('UPDATE') for call in c.execute.call_args_list)

def test_failed_movement_rolls_back_to_savepoint_not_whole_transaction():
    db,c,*_=setup()
    def execute(sql,args=None):
        if sql.startswith('INSERT INTO inventory_movements'):raise RuntimeError('failure')
    c.execute.side_effect=execute
    with pytest.raises(RuntimeError):run(db)
    assert any(call.args[0].startswith('ROLLBACK TO SAVEPOINT') for call in c.execute.call_args_list)
    db.commit.assert_not_called();db.rollback.assert_not_called()

def test_autocommit_is_rejected():
    db,c,*_=setup();db.get_autocommit.return_value=True
    with pytest.raises(HTTPException):run(db)
    c.execute.assert_not_called()
