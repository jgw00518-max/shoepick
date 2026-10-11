from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from backend.main import app
from backend.features.order_history import (
    CustomerScope, authenticated_customer, get_db,
)


@pytest.fixture
def context():
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    previous = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[authenticated_customer] = lambda: CustomerScope(8)
    try:
        with TestClient(app) as client:
            yield client, db, cursor
    finally:
        app.dependency_overrides.clear()
        app.dependency_overrides.update(previous)


def test_existing_records_are_not_payment_success(context):
    client, db, cursor = context
    cursor.fetchone.return_value = {
        'order_id': 1, 'order_status': 'CANCELED', 'canceled_at': 'DB-TIME',
    }
    cursor.fetchall.side_effect = [
        [{'return_request_id': 3, 'request_status': 'REQUESTED'}],
        [{'refund_id': 4, 'refund_status': 'PROCESSING', 'refund_amount': 59000}],
    ]
    response = client.get('/api/v1/order-history/customer/1/after-sales')
    assert response.status_code == 200
    assert response.json()['data']['refunds'][0]['refund_status'] == 'PROCESSING'
    calls = cursor.execute.call_args_list
    assert calls[0].args[1] == (1, 8)
    assert calls[1].args[1] == (1, 8)
    assert 'requested_at DESC, return_request_id DESC' in calls[1].args[0]
    assert 'requested_at DESC, refund_id DESC' in calls[2].args[0]
    assert 'provider_refund_key' not in calls[2].args[0]
    assert 'failure_message' not in calls[2].args[0]
    db.commit.assert_not_called()
    db.rollback.assert_not_called()


def test_no_records_returns_empty_lists(context):
    client, _, cursor = context
    cursor.fetchone.return_value = {'order_id': 1, 'order_status': 'PAID', 'canceled_at': None}
    cursor.fetchall.side_effect = [[], []]
    data = client.get('/api/v1/order-history/customer/1/after-sales').json()['data']
    assert data['return_requests'] == []
    assert data['refunds'] == []


def test_other_customer_order_does_not_read_child_records(context):
    client, _, cursor = context
    cursor.fetchone.return_value = None
    response = client.get('/api/v1/order-history/customer/1/after-sales')
    assert response.status_code == 404
    assert response.json()['error']['code'] == 'NOT_FOUND'
    cursor.fetchall.assert_not_called()
    assert cursor.execute.call_count == 1


@pytest.mark.parametrize('order_id', ['0', '-1', 'invalid'])
def test_invalid_id_does_not_query(context, order_id):
    client, _, cursor = context
    response = client.get(f'/api/v1/order-history/customer/{order_id}/after-sales')
    assert response.status_code == 400
    cursor.execute.assert_not_called()


def test_missing_authentication_does_not_query(context):
    client, _, cursor = context
    app.dependency_overrides.pop(authenticated_customer)
    response = client.get('/api/v1/order-history/customer/1/after-sales')
    assert response.status_code == 401
    assert response.json()['error']['code'] == 'UNAUTHENTICATED'
    cursor.execute.assert_not_called()
