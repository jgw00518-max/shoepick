"""확정된 C 소속 필터와 임시 미출고 기준을 A 응답 대체로 검증한다."""
from datetime import datetime
from unittest.mock import MagicMock

from backend.features import order_history as feature
from backend.features.order import PaidOrderListResponse


def paid(order_id, branch=3):
    return dict(order_id=order_id, order_number=f'C-{order_id}', order_status='PAID',
                pickup_branch_id=branch, branch_name='TEST', paid_total=1000,
                ordered_at=datetime(2026, 10, 11), paid_at=datetime(2026, 10, 11))


def test_filters_shipments_before_pagination(monkeypatch):
    query = MagicMock(return_value=PaidOrderListResponse(data=[paid(i) for i in range(8, 0, -1)]))
    monkeypatch.setattr(feature, 'get_paid_orders', query)
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.fetchall.return_value = [
        {'order_id': 8, 'fulfillment_status': 'IN_TRANSIT', 'shipped_at': None},
        {'order_id': 7, 'fulfillment_status': 'CANCELED', 'shipped_at': None},
        {'order_id': 6, 'fulfillment_status': 'PREPARING', 'shipped_at': datetime(2026, 10, 11)},
        {'order_id': 5, 'fulfillment_status': 'UNKNOWN', 'shipped_at': None},
        {'order_id': 4, 'fulfillment_status': 'PREPARING', 'shipped_at': None},
        {'order_id': 4, 'fulfillment_status': 'ARRIVED', 'shipped_at': None},
        {'order_id': 3, 'fulfillment_status': 'PREPARING', 'shipped_at': None},
    ]
    response = feature.read_dispatch_orders(db, feature.DispatchScope((3,), ('PAID',)), None, 2, 2)
    assert [r['order_id'] for r in response['data']] == [1]
    assert response['pagination']['total_count'] == 3
    query.assert_called_once_with(db=db)
    db.commit.assert_not_called()


def test_customer_pickup_branch_and_hq_filter(monkeypatch):
    monkeypatch.setattr(feature, 'get_paid_orders', lambda **kwargs:
                        PaidOrderListResponse(data=[paid(3, 4), paid(2, 3), paid(1, 5)]))
    db = MagicMock()
    db.cursor.return_value.__enter__.return_value.fetchall.return_value = []
    branch = feature.read_dispatch_orders(db, feature.DispatchScope((3,), ('PAID',)), None, 1, 20)
    assert [r['order_id'] for r in branch['data']] == [2]
    assert db.cursor.return_value.__enter__.return_value.execute.call_args.args[1] == (2,)
    hq = feature.read_dispatch_orders(db, feature.DispatchScope((), ('PAID',), True), 4, 1, 20)
    assert [r['order_id'] for r in hq['data']] == [3]
