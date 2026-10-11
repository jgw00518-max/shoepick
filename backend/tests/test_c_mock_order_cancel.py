from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException

from backend.features.order import cancel_paid_order_mock


def setup_db():
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    order = {'order_status': 'PAID', 'paid_total': 59000}
    payment = dict(payment_id=3, payment_method='MOCK', payment_status='PAID', payment_amount=59000)
    result = dict(refund_id=9, order_id=1, return_request_id=None, refund_type='ORDER_CANCEL',
                  refund_status='SUCCEEDED', refund_amount=59000, completed_at='2026-10-11')
    cursor.fetchone.side_effect = [order, None, None, result]
    cursor.fetchall.side_effect = [[], [], [payment]]
    cursor.rowcount = 1
    cursor.lastrowid = 9
    return db, cursor, order, payment, result


def invoke(db, **changes):
    return cancel_paid_order_mock(db, **dict(order_id=1, customer_id=8,
                                          request_id='key-1', reason='change of mind', **changes))


def assert_no_write(cursor):
    assert not any(call.args[0].startswith(('INSERT', 'UPDATE')) for call in cursor.execute.call_args_list)


def test_full_mock_cancel_leaves_final_completion_and_transaction_to_caller():
    db, cursor, _, _, result = setup_db()
    assert invoke(db) == {**result, 'is_mock': True, 'replayed': False}
    assert cursor.execute.call_args_list[0].args[1] == (1, 8)
    writes = [call.args[0] for call in cursor.execute.call_args_list if call.args[0].startswith(('INSERT', 'UPDATE'))]
    assert len(writes) == 3
    assert not any('UPDATE orders' in sql or 'UPDATE inventory' in sql for sql in writes)
    assert 'CURRENT_TIMESTAMP' in writes[0]
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


def test_foreign_or_missing_order_returns_404():
    db, cursor, *_ = setup_db()
    cursor.fetchone.side_effect = [None]
    with pytest.raises(HTTPException) as error:
        invoke(db)
    assert error.value.status_code == 404
    assert_no_write(cursor)


@pytest.mark.parametrize('status', ['PREPARING', 'SHIPPING', 'READY_FOR_PICKUP', 'COMPLETED', 'CANCELED', 'REFUNDED'])
def test_non_paid_order_is_blocked(status):
    db, cursor, order, *_ = setup_db()
    order['order_status'] = status
    with pytest.raises(HTTPException):
        invoke(db)
    assert_no_write(cursor)


@pytest.mark.parametrize('field,value', [('fulfillment_status', 'IN_TRANSIT'), ('shipped_at', 'time'), ('arrived_at', 'time')])
def test_dispatch_evidence_blocks_cancel(field, value):
    db, cursor, _, payment, _ = setup_db()
    delivery = dict(fulfillment_status='PREPARING', shipped_at=None, arrived_at=None, inspected_at=None, completed_at=None)
    delivery[field] = value
    cursor.fetchall.side_effect = [[], [delivery], [payment]]
    with pytest.raises(HTTPException):
        invoke(db)
    assert_no_write(cursor)


def test_inventory_consumed_blocks_cancel():
    db, cursor, order, *_ = setup_db()
    cursor.fetchone.side_effect = [order, None, {'inventory_reservation_id': 5}]
    with pytest.raises(HTTPException):
        invoke(db)
    assert_no_write(cursor)


@pytest.mark.parametrize('changes', [dict(payment_method='CARD'), dict(payment_status='REFUNDED'), dict(payment_amount=1)])
def test_invalid_payment_blocks_cancel(changes):
    db, cursor, _, payment, _ = setup_db()
    payment.update(changes)
    with pytest.raises(HTTPException):
        invoke(db)
    assert_no_write(cursor)


@pytest.mark.parametrize('payments', [[], [1, 2]])
def test_missing_or_multiple_payments_blocked(payments):
    db, cursor, _, payment, _ = setup_db()
    cursor.fetchall.side_effect = [[], [], [payment for _ in payments]]
    with pytest.raises(HTTPException):
        invoke(db)
    assert_no_write(cursor)


def test_new_key_business_replay_returns_existing_result_without_writes():
    db, cursor, _, _, result = setup_db()
    cursor.fetchall.side_effect = [[{**result, 'payment_method': 'MOCK'}]]
    assert invoke(db)['replayed'] is True
    assert_no_write(cursor)


@pytest.mark.parametrize('reason', ['change of mind', 'different reason'])
def test_same_key_replay_checks_reason(reason):
    db, cursor, order, _, result = setup_db()
    cursor.fetchone.side_effect = [order, result, {'after_data': {'reason': 'change of mind'}}]
    cursor.fetchall.side_effect = [[{**result, 'payment_method': 'MOCK'}]]
    if reason == 'change of mind':
        assert cancel_paid_order_mock(db, order_id=1, customer_id=8, request_id='key-1', reason=reason)['replayed']
    else:
        with pytest.raises(HTTPException):
            cancel_paid_order_mock(db, order_id=1, customer_id=8, request_id='key-1', reason=reason)
    assert_no_write(cursor)


@pytest.mark.parametrize('status', ['PROCESSING', 'FAILED'])
def test_unresolved_refund_blocks_retry(status):
    db, cursor, _, _, result = setup_db()
    cursor.fetchall.side_effect = [[{**result, 'refund_status': status, 'payment_method': 'MOCK'}]]
    with pytest.raises(HTTPException):
        invoke(db)
    assert_no_write(cursor)


def test_request_key_cannot_be_used_for_another_order():
    db, cursor, order, _, result = setup_db()
    cursor.fetchone.side_effect = [order, {**result, 'order_id': 77}]
    with pytest.raises(HTTPException):
        invoke(db)
    assert_no_write(cursor)


def test_write_failure_never_commits_partial_result():
    db, cursor, *_ = setup_db()
    def execute(sql, args):
        if sql.startswith('INSERT INTO audit_logs'):
            raise RuntimeError('simulated failure')
    cursor.execute.side_effect = execute
    with pytest.raises(RuntimeError):
        invoke(db)
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


@pytest.mark.parametrize('changes', [dict(order_id=0), dict(customer_id=True), dict(request_id=' '),
                                    dict(request_id='x' * 101), dict(reason=' '), dict(reason=None)])
def test_invalid_input_does_not_query_database(changes):
    db, cursor, *_ = setup_db()
    args = dict(order_id=1, customer_id=8, request_id='key-1', reason='test')
    args.update(changes)
    with pytest.raises(HTTPException) as error:
        cancel_paid_order_mock(db, **args)
    assert error.value.status_code == 400
    cursor.execute.assert_not_called()


def test_multiple_preparing_shipments_are_not_assumed_cancelable():
    db, cursor, _, payment, _ = setup_db()
    delivery = dict(fulfillment_status='PREPARING', shipped_at=None, arrived_at=None, inspected_at=None, completed_at=None)
    cursor.fetchall.side_effect = [[], [delivery, delivery], [payment]]
    with pytest.raises(HTTPException):
        invoke(db)
    assert_no_write(cursor)


def test_guarded_payment_update_conflict_propagates_to_caller():
    db, cursor, *_ = setup_db()
    cursor.rowcount = 0
    with pytest.raises(HTTPException):
        invoke(db)
    db.commit.assert_not_called()
    db.rollback.assert_not_called()
