from unittest.mock import MagicMock, patch
import pytest
from fastapi import HTTPException
from backend.features.order import mark_order_ready_for_pickup, mark_order_received
from backend.features.order_history import transition_pickup_order, OrderReadError

def setup(completed=False, **changes):
    after='COMPLETED' if completed else 'READY_FOR_PICKUP'
    rows={
        'order': {'order_status':'READY_FOR_PICKUP' if completed else 'SHIPPING','pickup_branch_id':3},
        'delivery': {'order_id':1,'destination_branch_id':3,'fulfillment_status':after,'shipped_at':'TIME','arrived_at':'TIME','inspected_at':'TIME','completed_at':'TIME' if completed else None},
        'pickup': {'order_id':1,'branch_id':3,'pickup_status':after,'ready_at':'TIME','picked_up_at':'TIME' if completed else None},
        **changes,
    }
    db=MagicMock();c=db.cursor.return_value.__enter__.return_value;c.fetchone.side_effect=list(rows.values());c.rowcount=1
    return db,c,rows

def invoke(db,completed=False):
    return (mark_order_received if completed else mark_order_ready_for_pickup)(db,order_id=1,fulfillment_id=7,pickup_id=9,branch_id=3,employee_id=4)

@pytest.mark.parametrize('completed',[False,True])
def test_state_and_history_without_confirming_purchase(completed):
    db,c,_=setup(completed); result=invoke(db,completed)
    assert result['order_status']==('COMPLETED' if completed else 'READY_FOR_PICKUP')
    assert result['replayed'] is False
    assert c.execute.call_args_list[3].args[0].startswith('UPDATE orders')
    assert 'purchase_confirmed_at' not in c.execute.call_args_list[3].args[0]
    assert c.execute.call_args_list[4].args[1][-1]==4
    db.commit.assert_not_called();db.rollback.assert_not_called()

@pytest.mark.parametrize('completed',[False,True])
def test_replay_does_not_repeat_history(completed):
    db,c,_=setup(completed,order={'order_status':'COMPLETED' if completed else 'READY_FOR_PICKUP','pickup_branch_id':3})
    assert invoke(db,completed)['replayed'] is True
    assert all(call.args[0].startswith('SELECT') for call in c.execute.call_args_list)

@pytest.mark.parametrize('completed',[False,True])
@pytest.mark.parametrize('field,value', [('order_id',99),('destination_branch_id',4),('fulfillment_status','IN_TRANSIT'),('arrived_at',None),('inspected_at',None),('shipped_at',None)])
def test_delivery_evidence(completed,field,value):
    db,c,rows=setup(completed);rows['delivery'][field]=value
    with pytest.raises(HTTPException) as error:invoke(db,completed)
    assert error.value.status_code==409
    assert not any(call.args[0].startswith('UPDATE') for call in c.execute.call_args_list)

@pytest.mark.parametrize('completed',[False,True])
@pytest.mark.parametrize('field,value',[('order_id',99),('branch_id',4),('pickup_status','PREPARING'),('ready_at',None)])
def test_pickup_evidence(completed,field,value):
    db,_,rows=setup(completed);rows['pickup'][field]=value
    with pytest.raises(HTTPException):invoke(db,completed)

@pytest.mark.parametrize('completed',[False,True])
def test_wrong_completion_evidence(completed):
    db,_,rows=setup(completed)
    rows['pickup']['picked_up_at']=None if completed else 'TIME'
    with pytest.raises(HTTPException):invoke(db,completed)

@pytest.mark.parametrize('state',['PAID','PENDING_PAYMENT','CANCELED','REFUNDED'])
def test_wrong_order_state(state):
    db,_,_=setup(order={'order_status':state,'pickup_branch_id':3})
    with pytest.raises(HTTPException):invoke(db)

def test_missing_order():
    db,_,_=setup(order=None)
    with pytest.raises(HTTPException) as error:invoke(db)
    assert error.value.status_code==404

def test_state_update_failure_and_caller_transaction():
    db,c,_=setup();c.rowcount=0
    with pytest.raises(HTTPException):invoke(db)
    db.commit.assert_not_called();db.rollback.assert_not_called()

@pytest.mark.parametrize('role,branch,allowed',[('BRANCH_STAFF',3,True),('BRANCH_MANAGER',3,True),('HQ_STAFF',3,False),('BRANCH_STAFF',4,False)])
def test_c_execution_authority(role,branch,allowed):
    employee={'employee_id':4,'roles':[{'role_code':role}],'branches':[{'branch_id':branch}]}
    with patch('backend.features.order_history.mark_order_ready_for_pickup',return_value={'order_status':'READY_FOR_PICKUP'}) as action:
        args=dict(order_id=1,fulfillment_id=7,pickup_id=9,branch_id=3,employee=employee,completed=False)
        if allowed:
            assert transition_pickup_order(MagicMock(),**args)['order_status']=='READY_FOR_PICKUP'
            assert action.call_args.kwargs['employee_id']==4
        else:
            with pytest.raises(OrderReadError) as error:transition_pickup_order(MagicMock(),**args)
            assert error.value.status==403;action.assert_not_called()

def test_c_translates_a_error():
    employee={'employee_id':4,'roles':[{'role_code':'BRANCH_STAFF'}],'branches':[{'branch_id':3}]}
    with patch('backend.features.order_history.mark_order_received',side_effect=HTTPException(409,detail={'code':'INVALID_STATE_TRANSITION','message':'test'})):
        with pytest.raises(OrderReadError) as error:transition_pickup_order(MagicMock(),order_id=1,fulfillment_id=7,pickup_id=9,branch_id=3,employee=employee,completed=True)
        assert error.value.code=='INVALID_STATE_TRANSITION'
