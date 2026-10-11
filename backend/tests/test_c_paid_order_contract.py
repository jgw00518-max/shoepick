"""A의 현재 조회 함수를 수정하지 않고 C가 받을 읽기 계약을 확인한다."""

from datetime import datetime
from unittest.mock import MagicMock

from backend.features.order import get_paid_orders, PaidOrderListResponse


def test_paid_order_function_accepts_explicit_connection():
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.fetchall.return_value = [{
        'order_id': 1, 'order_number': 'C-CONTRACT', 'order_status': 'PAID',
        'pickup_branch_id': 3, 'branch_name': '테스트 지점', 'paid_total': 1000,
        'ordered_at': datetime(2026, 10, 11, 12), 'paid_at': datetime(2026, 10, 11, 12),
    }]
    response = get_paid_orders(db=db)
    assert isinstance(response, PaidOrderListResponse)
    assert response.data[0].order_id == 1
    assert response.data[0].pickup_branch_id == 3
    assert response.data[0].paid_total == 1000
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


def test_paid_order_contract_returns_empty_list():
    db = MagicMock()
    db.cursor.return_value.__enter__.return_value.fetchall.return_value = []
    assert get_paid_orders(db=db).data == []
