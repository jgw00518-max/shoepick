from unittest.mock import MagicMock
import pytest
from backend.features import order_history as c


@pytest.fixture
def context(monkeypatch):
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.rowcount = 1
    cursor.lastrowid = 8
    cursor.fetchone.return_value = None
    employee = {'employee_id': 4}
    prepare = MagicMock(return_value={'order_id': 1, 'branch_id': 3})
    transition = MagicMock(return_value={'order_status': 'READY_FOR_PICKUP'})
    monkeypatch.setattr(c, 'prepare_staff_pickup_ready', prepare)
    monkeypatch.setattr(c, 'transition_pickup_order', transition)
    return db, cursor, employee, prepare, transition


@pytest.mark.parametrize('existing', [False, True])
def test_records_then_calls_a_without_commit(context, existing):
    db, cursor, employee, prepare, transition = context
    if existing:
        cursor.fetchone.return_value = {'pickup_id': 8, 'branch_id': 3, 'pickup_status': 'PREPARING',
                                       'ready_at': None, 'picked_up_at': None}
    result = c.record_staff_pickup_ready(db, fulfillment_id=7, employee=employee)
    assert result['order_status'] == 'READY_FOR_PICKUP'
    prepare.assert_called_once_with(db, fulfillment_id=7, employee=employee)
    transition.assert_called_once_with(db, order_id=1, fulfillment_id=7, pickup_id=8,
                                       branch_id=3, employee=employee, completed=False)
    sql = [x.args[0] for x in cursor.execute.call_args_list]
    assert any('INSERT INTO pickup_status_history' in x for x in sql)
    assert any('INSERT INTO fulfillment_status_history' in x for x in sql)
    assert not any('inventory' in x or 'pickup_holdings' in x or 'deadline' in x for x in sql)
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


def test_preparation_failure_prevents_writes(context):
    db, cursor, employee, prepare, transition = context
    prepare.side_effect = c.OrderReadError(409, 'INVALID_STATE_TRANSITION', 'not ready')
    with pytest.raises(c.OrderReadError):
        c.record_staff_pickup_ready(db, fulfillment_id=7, employee=employee)
    cursor.execute.assert_not_called()
    transition.assert_not_called()


@pytest.mark.parametrize('field,value', [('branch_id', 9), ('pickup_status', 'COMPLETED'),
                                       ('ready_at', 'raw'), ('picked_up_at', 'raw')])
def test_inconsistent_pickup_is_blocked(context, field, value):
    db, cursor, employee, prepare, transition = context
    pickup = {'pickup_id': 8, 'branch_id': 3, 'pickup_status': 'PREPARING', 'ready_at': None, 'picked_up_at': None}
    pickup[field] = value
    cursor.fetchone.return_value = pickup
    with pytest.raises(c.OrderReadError):
        c.record_staff_pickup_ready(db, fulfillment_id=7, employee=employee)
    transition.assert_not_called()
    assert cursor.execute.call_count == 1


def test_a_failure_propagates_to_transaction_owner(context):
    db, cursor, employee, prepare, transition = context
    transition.side_effect = c.OrderReadError(409, 'INVALID_STATE_TRANSITION', 'state changed')
    with pytest.raises(c.OrderReadError):
        c.record_staff_pickup_ready(db, fulfillment_id=7, employee=employee)
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


def test_zero_updated_rows_prevents_a_transition(context):
    db, cursor, employee, prepare, transition = context
    cursor.rowcount = 0
    with pytest.raises(c.OrderReadError):
        c.record_staff_pickup_ready(db, fulfillment_id=7, employee=employee)
    transition.assert_not_called()
