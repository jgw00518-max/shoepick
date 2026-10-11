"""C 검사와 A 금융 함수를 같은 대체 연결에서 검증한다. 실행 API는 아니다."""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from backend.features.order import cancel_paid_order_mock, refund_return_order_mock
from backend.features.order_history import (
    OrderReadError, prepare_customer_order_cancel, prepare_approved_return_refund,
    CustomerScope, stage_customer_order_cancel_mock,
)


def database(one, many):
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.fetchone.side_effect = one
    cursor.fetchall.side_effect = many
    cursor.rowcount = 1
    cursor.lastrowid = 9
    return db, cursor


def cancel_connection(db):
    prepared = prepare_customer_order_cancel(db, order_id=1, customer_id=8, request_id='KEY', reason='test')
    return cancel_paid_order_mock(db, **prepared)


def return_connection(db, employee):
    prepared = prepare_approved_return_refund(db, return_request_id=7, request_id='KEY', employee=employee)
    return refund_return_order_mock(db, **prepared)


def cancel_db():
    result = dict(refund_id=9, order_id=1, return_request_id=None, refund_type='ORDER_CANCEL',
                  refund_status='SUCCEEDED', refund_amount=59000, completed_at='server time')
    return database([
        {'order_status': 'PAID'}, {'payment_id': 3}, None,
        {'order_status': 'PAID', 'paid_total': 59000}, None, None, result,
    ], [[], [], [], [dict(payment_id=3, payment_status='PAID', payment_method='MOCK', payment_amount=59000)]])


def return_db():
    result = dict(refund_id=9, order_id=1, return_request_id=7, refund_type='RETURN',
                  refund_status='SUCCEEDED', refund_amount=59000, completed_at='server time')
    items = [{'order_item_id': 2, 'quantity': 3}]
    return database([
        {'order_id': 1}, {'order_status': 'COMPLETED', 'purchase_confirmed_at': None, 'pickup_branch_id': 3},
        {'order_id': 1, 'request_status': 'APPROVED'}, {'after_sales_inspection_id': 2}, {'pickup_id': 3},
        {'order_status': 'COMPLETED', 'purchase_confirmed_at': None, 'paid_total': 59000},
        {'order_id': 1, 'request_status': 'APPROVED'}, None, result,
    ], [items, items, [], [dict(payment_id=3, payment_status='PAID', payment_method='MOCK', payment_amount=59000)]])


EMPLOYEE = {'employee_id': 4, 'roles': [{'role_code': 'HQ_STAFF'}]}


@pytest.mark.parametrize('kind', ['cancel', 'return'])
def test_real_c_and_a_functions_share_connection_without_final_completion(kind):
    db, cursor = cancel_db() if kind == 'cancel' else return_db()
    result = cancel_connection(db) if kind == 'cancel' else return_connection(db, EMPLOYEE)
    assert result['refund_status'] == 'SUCCEEDED' and result['is_mock']
    assert result['refund_amount'] == 59000
    assert 'order_status' not in result
    assert not any(call.args[0].startswith(('UPDATE orders', 'UPDATE return_requests', 'UPDATE inventory'))
                   for call in cursor.execute.call_args_list)
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


def test_customer_scope_failure_never_calls_a():
    db, _ = database([None], [])
    with patch(__name__ + '.cancel_paid_order_mock') as financial:
        with pytest.raises(OrderReadError) as error:
            cancel_connection(db)
        assert error.value.status == 404
        financial.assert_not_called()


def test_staff_role_failure_never_calls_a():
    db, cursor = database([], [])
    with patch(__name__ + '.refund_return_order_mock') as financial:
        with pytest.raises(OrderReadError) as error:
            return_connection(db, {'employee_id': 4, 'roles': [{'role_code': 'BRANCH_MANAGER'}]})
        assert error.value.status == 403
        cursor.execute.assert_not_called()
        financial.assert_not_called()


def test_a_revalidates_payment_after_c_accepts_paid_evidence():
    db, cursor = cancel_db()
    cursor.fetchall.side_effect = [[], [], [], [dict(payment_id=3, payment_status='PAID', payment_method='CARD', payment_amount=59000)]]
    with pytest.raises(HTTPException):
        cancel_connection(db)
    assert not any(call.args[0].startswith(('INSERT', 'UPDATE')) for call in cursor.execute.call_args_list)


@pytest.mark.parametrize('kind', ['cancel', 'return'])
def test_financial_write_failure_reaches_top_level_rollback_harness(kind):
    db, cursor = cancel_db() if kind == 'cancel' else return_db()
    def execute(sql, args):
        if sql.startswith('UPDATE payments'):
            raise RuntimeError('simulated failure after refund insert')
    cursor.execute.side_effect = execute
    # 테스트 호출자만 rollback을 담당한다. 실제 MySQL 복구 검증으로 간주하지 않는다.
    with pytest.raises(RuntimeError):
        try:
            cancel_connection(db) if kind == 'cancel' else return_connection(db, EMPLOYEE)
        except Exception:
            db.rollback()
            raise
    db.rollback.assert_called_once()
    db.commit.assert_not_called()


def test_cancel_preparation_cannot_be_used_as_result_lookup_after_financial_refund():
    db, _ = database([{'order_status': 'PAID'}, None], [])
    with patch(__name__ + '.cancel_paid_order_mock') as financial:
        with pytest.raises(OrderReadError):
            cancel_connection(db)
        financial.assert_not_called()
    # 향후 최상위 API는 재전송 시 기존 결과부터 확인해야 한다.


def staged_cancel_db():
    db, cursor = cancel_db()
    result = dict(refund_id=9, order_id=1, return_request_id=None, refund_type='ORDER_CANCEL',
                  refund_status='SUCCEEDED', refund_amount=59000, completed_at='server time')
    cursor.fetchone.side_effect = [
        {'order_status':'PAID'}, {'payment_id':3}, None,
        {'order_status':'PAID','paid_total':59000}, None, None, result,
        {'order_status':'PAID','paid_total':59000,'canceled_at':None},
        dict(refund_type='ORDER_CANCEL',refund_status='SUCCEEDED',refund_amount=59000,
             return_request_id=None,completed_at='server time',payment_method='MOCK',
             payment_status='REFUNDED',payment_amount=59000),
        None, {'after_data':{'reason':'test'}},
    ]
    cursor.fetchall.side_effect = [[], [], [], [dict(payment_id=3,payment_status='PAID',
                                                  payment_method='MOCK',payment_amount=59000)], []]
    return db, cursor


def stage(db, **changes):
    args = dict(order_id=1,customer=CustomerScope(8),request_id='KEY',reason='test')
    args.update(changes)
    return stage_customer_order_cancel_mock(db, **args)


def test_c_stage_calls_real_a_financial_and_transition_without_completing():
    db, cursor = staged_cancel_db()
    assert stage(db) == dict(order_id=1,refund_id=9,is_mock=True,requires_inventory_release=True,completed=False)
    statements = [call.args[0] for call in cursor.execute.call_args_list]
    assert next(i for i,sql in enumerate(statements) if sql.startswith('INSERT INTO refunds')) < next(
        i for i,sql in enumerate(statements) if sql.startswith('UPDATE orders'))
    assert not any(sql.startswith('UPDATE inventory') for sql in statements)
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


@pytest.mark.parametrize('changes', [dict(customer={'customer_id':8}),dict(reason='x'*256),dict(request_id=None)])
def test_stage_rejects_invalid_scope_or_input_before_any_writes(changes):
    db, cursor = staged_cancel_db()
    with pytest.raises(OrderReadError):
        stage(db, **changes)
    cursor.execute.assert_not_called()


def test_transition_failure_after_refund_is_translated_and_rolls_back_at_caller():
    db, cursor = staged_cancel_db()
    def execute(sql, args):
        if sql.startswith('UPDATE orders'):
            cursor.rowcount = 0
    cursor.execute.side_effect = execute
    with pytest.raises(OrderReadError) as error:
        try:
            stage(db)
        except Exception:
            db.rollback()
            raise
    assert error.value.code == 'INVALID_STATE_TRANSITION'
    db.rollback.assert_called_once()
    db.commit.assert_not_called()
