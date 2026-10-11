from unittest.mock import MagicMock
import pytest
from fastapi import HTTPException
from backend.features.order import mark_order_shipping


def setup(status='PAID', payment=True, **changes):
    db=MagicMock()
    cursor=db.cursor.return_value.__enter__.return_value
    delivery={'order_id':1,'destination_branch_id':3,'fulfillment_status':'IN_TRANSIT','shipped_at':'server-time',**changes}
    cursor.fetchone.side_effect=[{'order_status':status,'pickup_branch_id':3},{'payment_id':2} if payment else None,delivery]
    cursor.rowcount=1
    return db,cursor


def test_shipping_transition_history_and_no_commit():
    db,cursor=setup()
    result=mark_order_shipping(db,order_id=1,fulfillment_id=7,employee_id=4)
    assert result['order_status']=='SHIPPING'
    assert cursor.execute.call_args.args[1]==(1,'출고 확인 fulfillment_id=7',4)
    assert 'FOR UPDATE' in cursor.execute.call_args_list[0].args[0]
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


@pytest.mark.parametrize('status',['PENDING_PAYMENT','PREPARING','SHIPPING','CANCELED','REFUNDED'])
def test_invalid_order_state(status):
    db,cursor=setup(status=status)
    with pytest.raises(HTTPException) as exc:
        mark_order_shipping(db,order_id=1,fulfillment_id=7,employee_id=4)
    assert exc.value.detail['code']=='INVALID_STATE_TRANSITION'
    assert len(cursor.execute.call_args_list)==1


@pytest.mark.parametrize('changes',[{'order_id':2},{'destination_branch_id':4},{'fulfillment_status':'PREPARING'},{'shipped_at':None}])
def test_invalid_delivery(changes):
    db,cursor=setup(**changes)
    with pytest.raises(HTTPException):
        mark_order_shipping(db,order_id=1,fulfillment_id=7,employee_id=4)
    assert not any('UPDATE orders' in call.args[0] for call in cursor.execute.call_args_list)


def test_missing_payment_and_missing_order():
    db,cursor=setup(payment=False)
    with pytest.raises(HTTPException):
        mark_order_shipping(db,order_id=1,fulfillment_id=7,employee_id=4)
    cursor.fetchone.side_effect=[None]
    with pytest.raises(HTTPException) as exc:
        mark_order_shipping(db,order_id=1,fulfillment_id=7,employee_id=4)
    assert exc.value.status_code==404

def test_c_connection_restricts_roles_and_passes_verified_employee(monkeypatch):
    from backend.features import order_history as c
    calls=[]
    monkeypatch.setattr(c,'mark_order_shipping',lambda *args,**kwargs:calls.append((args,kwargs)) or {'order_status':'SHIPPING'})
    with pytest.raises(c.OrderReadError) as exc:
        c.transition_dispatched_order('db',order_id=1,fulfillment_id=7,employee={'employee_id':4,'roles':[{'role_code':'BRANCH_STAFF'}]})
    assert exc.value.status==403 and not calls
    c.transition_dispatched_order('db',order_id=1,fulfillment_id=7,employee={'employee_id':4,'roles':[{'role_code':'HQ_STAFF'}]})
    assert calls[0][1]['employee_id']==4
