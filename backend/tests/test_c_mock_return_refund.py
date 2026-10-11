from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException

from backend.features.order import refund_return_order_mock


def setup_db(**changes):
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    order = dict(order_status='COMPLETED', paid_total=59000, purchase_confirmed_at=None)
    order.update(changes)
    result = dict(refund_id=9, order_id=1, return_request_id=2, refund_type='RETURN',
                  refund_status='SUCCEEDED', refund_amount=59000, completed_at='2026-10-11')
    cursor.fetchone.side_effect = [order, dict(order_id=1, request_status='APPROVED'), None, result]
    cursor.fetchall.side_effect = [[], [dict(payment_id=3, payment_method='MOCK', payment_status='PAID', payment_amount=59000)]]
    cursor.rowcount = 1
    cursor.lastrowid = 9
    return db, cursor, result


def invoke(db, **changes):
    args = dict(order_id=1, return_request_id=2, employee_id=3, request_id='request-1')
    args.update(changes)
    return refund_return_order_mock(db, **args)


def test_full_mock_refund_keeps_transaction_and_completion_with_caller():
    db, cursor, result = setup_db()
    assert invoke(db) == {**result, 'replayed': False, 'is_mock': True}
    sql = '\n'.join(call.args[0] for call in cursor.execute.call_args_list)
    assert 'CURRENT_TIMESTAMP' in sql
    assert 'UPDATE orders' not in sql and 'UPDATE return_requests' not in sql
    assert 'inventory' not in sql
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


@pytest.mark.parametrize('changes', [dict(order_status='PAID'), dict(purchase_confirmed_at='time')])
def test_ineligible_order_does_not_write(changes):
    db, cursor, _ = setup_db(**changes)
    with pytest.raises(HTTPException):
        invoke(db)
    assert not any(call.args[0].startswith(('INSERT', 'UPDATE')) for call in cursor.execute.call_args_list)


@pytest.mark.parametrize('method,status,amount', [('CARD','PAID',59000), ('MOCK','REFUNDED',59000), ('MOCK','PAID',58000)])
def test_non_mock_or_mismatched_payment_is_blocked(method, status, amount):
    db, cursor, _ = setup_db()
    cursor.fetchall.side_effect = [[], [dict(payment_id=3,payment_method=method,payment_status=status,payment_amount=amount)]]
    with pytest.raises(HTTPException):
        invoke(db)
    assert not any(call.args[0].startswith(('INSERT', 'UPDATE')) for call in cursor.execute.call_args_list)


def test_same_business_replay_does_not_refund_again():
    db, cursor, result = setup_db()
    cursor.fetchall.side_effect = [[{**result, 'payment_method':'MOCK'}]]
    assert invoke(db, request_id='different-key')['replayed'] is True
    assert not any(call.args[0].startswith(('INSERT','UPDATE')) for call in cursor.execute.call_args_list)


@pytest.mark.parametrize('status', ['PROCESSING','FAILED'])
def test_unresolved_refund_is_not_recreated(status):
    db, cursor, result = setup_db()
    cursor.fetchall.side_effect = [[{**result,'refund_status':status,'payment_method':'MOCK'}]]
    with pytest.raises(HTTPException):
        invoke(db)


def test_request_key_reuse_for_other_order_is_blocked():
    db, cursor, result = setup_db()
    cursor.fetchone.side_effect = [dict(order_status='COMPLETED',paid_total=59000,purchase_confirmed_at=None),
                                  dict(order_id=1,request_status='APPROVED'), {**result,'order_id':8}]
    with pytest.raises(HTTPException):
        invoke(db)


def test_write_failure_propagates_without_partial_commit():
    db, cursor, _ = setup_db()
    original = cursor.execute
    def execute(sql, args):
        if sql.startswith('UPDATE payments'):
            raise RuntimeError('simulated database failure')
        return original.return_value
    cursor.execute.side_effect = execute
    with pytest.raises(RuntimeError):
        invoke(db)
    db.commit.assert_not_called()
    db.rollback.assert_not_called()
