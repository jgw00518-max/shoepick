from unittest.mock import MagicMock
import pytest
from backend.features.order_history import prepare_staff_pickup_ready, OrderReadError


@pytest.fixture
def context():
    db = MagicMock()
    db.get_autocommit.return_value = False
    cursor = db.cursor.return_value.__enter__.return_value
    order = {'order_status': 'SHIPPING', 'pickup_branch_id': 3}
    delivery = {'order_id': 1, 'destination_branch_id': 3, 'fulfillment_status': 'INSPECTING',
                'shipped_at': 'raw', 'arrived_at': 'raw', 'inspected_at': 'raw', 'completed_at': None}
    cursor.fetchone.side_effect = [{'order_id': 1}, order, delivery]
    items = [{'order_item_id': 2, 'quantity': 1}]
    shipped = [{'fulfillment_item_id': 9, 'order_item_id': 2, 'order_id': 1, 'quantity': 1}]
    holdings = [{'fulfillment_item_id': 9, 'branch_id': 3, 'quantity': 1,
                 'holding_status': 'READY_FOR_PICKUP', 'received_at': 'raw', 'ready_at': 'raw', 'picked_up_at': None}]
    cursor.fetchall.side_effect = [items, shipped, holdings]
    employee = {'employee_id': 4, 'roles': [{'role_code': 'BRANCH_MANAGER'}], 'branches': [{'branch_id': 3}]}
    return db, cursor, employee, order, delivery, items, shipped, holdings


def run(context):
    return prepare_staff_pickup_ready(context[0], fulfillment_id=7, employee=context[2])


def test_ready_preparation_never_changes_or_ends_transaction(context):
    db, cursor, *_ = context
    assert run(context) == {'order_id': 1, 'fulfillment_id': 7, 'branch_id': 3, 'employee_id': 4}
    assert all(call.args[0].startswith('SELECT') for call in cursor.execute.call_args_list)
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


@pytest.mark.parametrize('field,value', [('holding_status', 'INSPECTING'), ('branch_id', 8),
                                       ('quantity', 2), ('received_at', None), ('ready_at', None), ('picked_up_at', 'raw')])
def test_invalid_d_holding_is_blocked(context, field, value):
    context[7][0][field] = value
    with pytest.raises(OrderReadError) as error:
        run(context)
    assert error.value.code == 'INVALID_STATE_TRANSITION'


def test_missing_holding_is_blocked(context):
    context[7].clear()
    with pytest.raises(OrderReadError):
        run(context)


@pytest.mark.parametrize('field,value', [('inspected_at', None), ('completed_at', 'raw'), ('fulfillment_status', 'ARRIVED')])
def test_uninspected_or_completed_delivery_is_blocked(context, field, value):
    context[4][field] = value
    with pytest.raises(OrderReadError):
        run(context)


def test_foreign_branch_and_hq_execution_are_blocked(context):
    context[2]['roles'] = [{'role_code': 'HQ_STAFF'}]
    with pytest.raises(OrderReadError):
        run(context)
    context[1].execute.assert_not_called()


def test_quantity_mismatch_is_blocked(context):
    context[6][0]['quantity'] = 2
    with pytest.raises(OrderReadError):
        run(context)
