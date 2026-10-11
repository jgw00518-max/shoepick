from unittest.mock import MagicMock
import pytest
from fastapi import HTTPException
from backend.features.inventory import restore_return_inventory

@pytest.fixture
def context():
    db=MagicMock();db.get_autocommit.return_value=False
    cur=db.cursor.return_value.__enter__.return_value
    inspection={'inspection_decision':'ACCEPTED','has_wear_marks':0,'has_product_damage':0,'has_customer_fault':0,
                'components_complete':1,'packaging_intact':1,'has_product_defect':0,'is_wrong_item':0}
    rows=[{'order_status':'COMPLETED'},{'purchase_confirmed_at':None},{'order_id':1,'request_status':'APPROVED'},inspection,
          {'product_variant_id':3,'on_hand_quantity':10,'reserved_quantity':2,'defective_quantity':1},None]
    cur.fetchone.side_effect=rows
    cur.fetchall.side_effect=[[{'order_item_id':2,'product_variant_id':3,'quantity':2}],[{'order_item_id':2,'quantity':2}]]
    return db,cur,rows

def run(context,confirmed=True):
    return restore_return_inventory(context[0],order_id=1,return_request_id=7,employee_id=4,resale_confirmed=confirmed)

def test_restore_only_normal_on_hand_without_commit(context):
    db,cur,rows=context
    assert run(context)['changed'] is True
    update=[x for x in cur.execute.call_args_list if x.args[0].startswith('UPDATE')]
    assert len(update)==1 and update[0].args[1]==(2,3)
    db.commit.assert_not_called();db.rollback.assert_not_called()

@pytest.mark.parametrize('field,value',[('has_product_damage',1),('has_product_defect',1),('packaging_intact',0),('components_complete',0)])
def test_non_resalable_inspection_blocked(context,field,value):
    context[2][3][field]=value
    with pytest.raises(HTTPException):run(context)
    assert not any(x.args[0].startswith('UPDATE') for x in context[1].execute.call_args_list)

def test_explicit_confirmation_required(context):
    with pytest.raises(HTTPException):run(context,False)
    context[1].execute.assert_not_called()

def test_replay_does_not_restore_twice(context):
    context[2][-1]={'product_variant_id':3,'on_hand_delta':2,'reserved_delta':0,'defective_delta':0,'reference_type':'RETURN','reference_id':7}
    context[1].fetchone.side_effect=context[2]
    assert run(context)['changed'] is False
    assert not any(x.args[0].startswith(('INSERT','UPDATE')) for x in context[1].execute.call_args_list)

def test_movement_failure_rolls_back_savepoint(context):
    def execute(sql,args=None):
        if sql.startswith('INSERT INTO inventory_movements'):raise RuntimeError('failure')
    context[1].execute.side_effect=execute
    with pytest.raises(RuntimeError):run(context)
    assert any(x.args[0].startswith('ROLLBACK TO SAVEPOINT') for x in context[1].execute.call_args_list)
    context[0].commit.assert_not_called()
