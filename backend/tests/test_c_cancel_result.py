from unittest.mock import MagicMock

import pytest

from backend.features.order_history import CustomerScope, OrderReadError, read_customer_cancel_mock_result


def setup_db():
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.fetchone.return_value = dict(order_id=1, order_status='CANCELED', canceled_at='raw server time')
    cursor.fetchall.return_value = []
    return db, cursor


def read(db, **changes):
    args = dict(order_id=1, customer=CustomerScope(8))
    args.update(changes)
    return read_customer_cancel_mock_result(db, **args)


def test_empty_records_do_not_authorize_retry_or_confirm_completion():
    db, cursor = setup_db()
    result = read(db)
    assert result['refunds'] == []
    assert result['completion_confirmed'] is False
    assert cursor.execute.call_args_list[0].args[1] == (1, 8)
    assert all(call.args[0].startswith('SELECT') for call in cursor.execute.call_args_list)
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


@pytest.mark.parametrize('status', ['SUCCEEDED', 'PROCESSING', 'FAILED', 'CANCELED', 'UNKNOWN'])
def test_financial_status_is_preserved_without_claiming_full_completion(status):
    db, cursor = setup_db()
    record = dict(refund_id=9,refund_status=status,refund_amount=59000,requested_at='raw time',
                  completed_at=None,failed_at=None,provider_refund_key='private',idempotency_key='private')
    cursor.fetchall.return_value = [record]
    result = read(db)
    assert result['refunds'][0]['refund_status'] == status
    assert result['refunds'][0]['requested_at'] == 'raw time'
    assert 'provider_refund_key' not in result['refunds'][0]
    assert 'idempotency_key' not in result['refunds'][0]
    assert result['completion_confirmed'] is False


def test_owned_scope_and_mock_cancel_filter_with_stable_sort():
    db, cursor = setup_db()
    read(db)
    sql = cursor.execute.call_args_list[1].args[0]
    assert "r.refund_type='ORDER_CANCEL'" in sql
    assert "p.payment_method='MOCK'" in sql
    assert 'r.return_request_id IS NULL' in sql
    assert 'r.requested_at DESC, r.refund_id DESC' in sql


def test_foreign_or_missing_order_does_not_read_refunds():
    db, cursor = setup_db()
    cursor.fetchone.return_value = None
    with pytest.raises(OrderReadError) as error:
        read(db)
    assert error.value.status == 404
    assert cursor.execute.call_count == 1


@pytest.mark.parametrize('changes', [dict(customer={'customer_id':8}),dict(customer=CustomerScope(True)),dict(order_id=0)])
def test_invalid_scope_or_order(changes):
    db, cursor = setup_db()
    with pytest.raises(OrderReadError):
        read(db, **changes)
    cursor.execute.assert_not_called()


def test_read_failure_propagates_instead_of_becoming_empty_result():
    db, cursor = setup_db()
    cursor.fetchall.side_effect = RuntimeError('simulated read failure')
    with pytest.raises(RuntimeError):
        read(db)
