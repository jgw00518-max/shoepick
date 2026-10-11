from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException

from backend.features.order import mark_order_canceled_mock


def setup_db(status='PAID'):
    db = MagicMock()
    c = db.cursor.return_value.__enter__.return_value
    order = dict(order_status=status, paid_total=59000, canceled_at='time' if status == 'CANCELED' else None)
    refund = dict(refund_type='ORDER_CANCEL', refund_status='SUCCEEDED', refund_amount=59000,
                  return_request_id=None, completed_at='time', payment_method='MOCK', payment_status='REFUNDED', payment_amount=59000)
    c.fetchone.side_effect = [order, refund, None, {'after_data': {'reason': 'test'}}, {'order_status_history_id': 1}]
    c.fetchall.return_value = []
    c.rowcount = 1
    return db, c, order, refund


def run(db, **changes):
    args = dict(order_id=1, customer_id=8, refund_id=9, reason='test')
    args.update(changes)
    return mark_order_canceled_mock(db, **args)


def no_writes(c):
    assert not any(call.args[0].startswith(('UPDATE', 'INSERT')) for call in c.execute.call_args_list)


def test_transition_records_history_but_never_commits_or_calls_inventory():
    db, c, *_ = setup_db()
    assert run(db) == dict(order_id=1, order_status='CANCELED', refund_id=9, replayed=False, is_mock=True)
    writes = [call for call in c.execute.call_args_list if call.args[0].startswith(('UPDATE', 'INSERT'))]
    assert len(writes) == 2
    assert 'CURRENT_TIMESTAMP' in writes[0].args[0]
    assert writes[1].args[1] == (1, 'test', 8)
    assert c.execute.call_args_list[0].args[1] == (1, 8)
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


def test_replay_requires_matching_cancel_history_and_does_not_duplicate_it():
    db, c, *_ = setup_db('CANCELED')
    assert run(db)['replayed']
    no_writes(c)


@pytest.mark.parametrize('status', ['SHIPPING', 'PREPARING', 'COMPLETED', 'REFUNDED'])
def test_wrong_order_state(status):
    db, c, *_ = setup_db(status)
    with pytest.raises(HTTPException):
        run(db)
    no_writes(c)


@pytest.mark.parametrize('field,value', [('refund_type','RETURN'), ('refund_status','PROCESSING'),
    ('refund_amount',1), ('return_request_id',7), ('completed_at',None), ('payment_method','CARD'),
    ('payment_status','PAID'), ('payment_amount',1)])
def test_financial_evidence_must_match(field, value):
    db, c, _, refund = setup_db()
    refund[field] = value
    with pytest.raises(HTTPException):
        run(db)
    no_writes(c)


def test_another_customer_cannot_change_order():
    db, c, *_ = setup_db()
    c.fetchone.side_effect = [None]
    with pytest.raises(HTTPException) as error:
        run(db)
    assert error.value.status_code == 404
    no_writes(c)


def test_shipped_order_is_blocked_even_if_still_paid():
    db, c, *_ = setup_db()
    c.fetchall.return_value = [dict(fulfillment_status='IN_TRANSIT',shipped_at='time')]
    with pytest.raises(HTTPException):
        run(db)
    no_writes(c)


def test_consumed_inventory_is_blocked():
    db, c, order, refund = setup_db()
    c.fetchone.side_effect = [order, refund, {'inventory_reservation_id':1}]
    with pytest.raises(HTTPException):
        run(db)
    no_writes(c)


def test_reason_must_match_original_financial_request():
    db, c, *_ = setup_db()
    with pytest.raises(HTTPException):
        run(db, reason='changed')
    no_writes(c)


@pytest.mark.parametrize('changes', [dict(customer_id=True),dict(refund_id=0),dict(reason='x'*256),dict(reason=' ')])
def test_invalid_parameters(changes):
    db, c, *_ = setup_db()
    with pytest.raises(HTTPException) as error:
        run(db, **changes)
    assert error.value.status_code == 400
    c.execute.assert_not_called()


def test_history_failure_propagates_for_caller_rollback():
    db, c, *_ = setup_db()
    def execute(sql, args):
        if sql.startswith('INSERT INTO order_status_history'):
            raise RuntimeError('simulated failure')
    c.execute.side_effect = execute
    with pytest.raises(RuntimeError):
        run(db)
    db.commit.assert_not_called()
    db.rollback.assert_not_called()
