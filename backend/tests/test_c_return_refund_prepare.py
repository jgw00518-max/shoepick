from unittest.mock import MagicMock
import pytest
from backend.features.order_history import prepare_approved_return_refund, OrderReadError

EMPLOYEE = {'employee_id':4,'roles':[{'role_code':'HQ_STAFF'}]}

def setup(**changes):
    values = {
        'reference': {'order_id':1},
        'order': {'order_status':'COMPLETED','purchase_confirmed_at':None,'pickup_branch_id':3},
        'request': {'order_id':1,'request_status':'APPROVED'},
        'inspection': {'after_sales_inspection_id':9},
        'pickup': {'pickup_id':2},
        **changes,
    }
    db=MagicMock(); cursor=db.cursor.return_value.__enter__.return_value
    cursor.fetchone.side_effect=list(values.values())
    cursor.fetchall.side_effect=[[{'order_item_id':2,'quantity':3}],[{'order_item_id':2,'quantity':3}]]
    return db,cursor

def prepare(db,employee=EMPLOYEE,request_id='KEY'):
    return prepare_approved_return_refund(db,return_request_id=7,request_id=request_id,employee=employee)

def test_a_arguments_only_and_no_writes():
    db,c=setup();result=prepare(db)
    assert result=={'order_id':1,'return_request_id':7,'employee_id':4,'request_id':'KEY'}
    assert all(call.args[0].startswith('SELECT') for call in c.execute.call_args_list)
    assert 'orders' in c.execute.call_args_list[1].args[0]
    assert 'FOR UPDATE' in c.execute.call_args_list[1].args[0]
    assert 'refund_amount' not in result
    db.commit.assert_not_called();db.rollback.assert_not_called()

@pytest.mark.parametrize('changes',[
    {'request':{'order_id':1,'request_status':'INSPECTING'}},
    {'order':{'order_status':'COMPLETED','purchase_confirmed_at':'TIME'}},
    {'order':{'order_status':'READY_FOR_PICKUP','purchase_confirmed_at':None}},
    {'inspection':None}, {'pickup':None},
])
def test_unready_or_unconfirmed(changes):
    db,_=setup(**changes)
    with pytest.raises(OrderReadError) as error:prepare(db)
    assert error.value.code=='INVALID_STATE_TRANSITION'
    db.commit.assert_not_called()

def test_missing_return():
    db,_=setup(reference=None)
    with pytest.raises(OrderReadError) as error:prepare(db)
    assert error.value.status==404

@pytest.mark.parametrize('returned',[[],[{'order_item_id':2,'quantity':1}],[{'order_item_id':99,'quantity':3}]])
def test_partial_or_foreign_item(returned):
    db,c=setup();c.fetchall.side_effect=[[{'order_item_id':2,'quantity':3}],returned]
    with pytest.raises(OrderReadError) as error:prepare(db)
    assert error.value.status==409

@pytest.mark.parametrize('employee,key',[
    ({'roles':[{'role_code':'BRANCH_MANAGER'}]},'KEY'),(EMPLOYEE,' '),(EMPLOYEE,'x'*101),
])
def test_permission_or_input(employee,key):
    db,c=setup()
    with pytest.raises(OrderReadError):prepare(db,employee,key)
    c.execute.assert_not_called()
