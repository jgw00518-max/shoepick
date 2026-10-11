from unittest.mock import MagicMock
import pytest
from fastapi import HTTPException
from backend.features.inventory import prepare_pickup_holdings

@pytest.fixture
def context():
    db=MagicMock();db.get_autocommit.return_value=False
    cur=db.cursor.return_value.__enter__.return_value
    cur.fetchone.side_effect=[{'order_id':1,'order_status':'SHIPPING'},
        {'order_id':1,'destination_branch_id':3,'fulfillment_status':'INSPECTING','shipped_at':'raw','arrived_at':'raw','inspected_at':'raw','completed_at':None},
        {'pickup_branch_id':3},None]
    cur.fetchall.side_effect=[[{'order_item_id':2,'quantity':1}],
        [{'fulfillment_item_id':9,'order_item_id':2,'order_id':1,'quantity':1}]]
    return db,cur

def test_create_customer_holding_without_sales_stock_or_commit(context):
    db,cur=context
    assert prepare_pickup_holdings(db,order_id=1,fulfillment_id=7,branch_id=3)['changed']
    sql=[x.args[0] for x in cur.execute.call_args_list]
    assert any(x.startswith('INSERT INTO pickup_holdings') for x in sql)
    assert not any('inventory_balances' in x or 'inventory_movements' in x for x in sql)
    db.commit.assert_not_called();db.rollback.assert_not_called()

def test_existing_ready_holding_is_not_written_twice(context):
    db,cur=context
    rows=list(cur.fetchone.side_effect)
    rows[-1]={'branch_id':3,'quantity':1,'holding_status':'READY_FOR_PICKUP','received_at':'raw','ready_at':'raw','picked_up_at':None}
    cur.fetchone.side_effect=rows
    assert not prepare_pickup_holdings(db,order_id=1,fulfillment_id=7,branch_id=3)['changed']
    assert not any(x.args[0].startswith(('INSERT','UPDATE')) for x in cur.execute.call_args_list)

def test_conflicting_holding_uses_savepoint_rollback(context):
    db,cur=context
    rows=list(cur.fetchone.side_effect)
    rows[-1]={'branch_id':9,'quantity':1,'holding_status':'INSPECTING','received_at':None,'ready_at':None,'picked_up_at':None}
    cur.fetchone.side_effect=rows
    with pytest.raises(HTTPException):prepare_pickup_holdings(db,order_id=1,fulfillment_id=7,branch_id=3)
    assert any(x.args[0].startswith('ROLLBACK TO SAVEPOINT') for x in cur.execute.call_args_list)
    db.commit.assert_not_called()
