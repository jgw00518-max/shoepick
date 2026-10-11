from unittest.mock import MagicMock
import pytest
from backend.features.order_history import prepare_customer_order_cancel, OrderReadError

def setup(order=None,payment=True,deliveries=None,consumed=False):
    db=MagicMock(); c=db.cursor.return_value.__enter__.return_value
    c.fetchone.side_effect=[order if order is not None else {'order_status':'PAID'}, {'payment_id':2} if payment else None, {'inventory_reservation_id':3} if consumed else None]
    c.fetchall.return_value=deliveries or []
    return db,c

def prepare(db,**changes):
    args={'order_id':1,'customer_id':8,'request_id':'KEY','reason':'test',**changes}
    return prepare_customer_order_cancel(db,**args)

def test_owned_paid_order_readonly():
    db,c=setup(); assert prepare(db)=={'order_id':1,'customer_id':8,'request_id':'KEY','reason':'test'}
    assert c.execute.call_args_list[0].args[1]==(1,8)
    assert 'FOR UPDATE' in c.execute.call_args_list[0].args[0]
    assert all(call.args[0].startswith('SELECT') for call in c.execute.call_args_list)
    db.commit.assert_not_called(); db.rollback.assert_not_called()

def test_foreign_or_missing_order():
    db,c=setup();c.fetchone.side_effect=[None]
    with pytest.raises(OrderReadError) as error:prepare(db)
    assert error.value.status==404
    assert c.execute.call_count==1

@pytest.mark.parametrize('status',['PREPARING','SHIPPING','READY_FOR_PICKUP','COMPLETED','CANCELED','REFUNDED'])
def test_order_state(status):
    db,c=setup(order={'order_status':status})
    with pytest.raises(OrderReadError) as error:prepare(db)
    assert error.value.code=='INVALID_STATE_TRANSITION'
    assert c.execute.call_count==1

def delivery(**changes):
    return {'fulfillment_status':'PREPARING','shipped_at':None,'arrived_at':None,'inspected_at':None,'completed_at':None,**changes}

@pytest.mark.parametrize('rows',[[delivery(fulfillment_status='IN_TRANSIT')],[delivery(fulfillment_status='CANCELED')],[delivery(shipped_at='TIME')],[delivery(),delivery()]])
def test_actual_or_ambiguous_dispatch(rows):
    db,_=setup(deliveries=rows)
    with pytest.raises(OrderReadError):prepare(db)

def test_preparing_delivery_is_not_order_preparing():
    db,_=setup(deliveries=[delivery()]);assert prepare(db)['order_id']==1

@pytest.mark.parametrize('payment,consumed',[(False,False),(True,True)])
def test_payment_or_inventory_evidence(payment,consumed):
    db,_=setup(payment=payment,consumed=consumed)
    with pytest.raises(OrderReadError):prepare(db)

@pytest.mark.parametrize('changes',[{'order_id':0},{'customer_id':0},{'request_id':' '},{'request_id':'x'*101},{'reason':' '}])
def test_invalid_input(changes):
    db,c=setup()
    with pytest.raises(OrderReadError) as error:prepare(db,**changes)
    assert error.value.status==400;c.execute.assert_not_called()
