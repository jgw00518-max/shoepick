from datetime import datetime
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from pymysql import OperationalError

from backend.main import app
from backend.features import purchase_requisitions as feature
from backend.features.authentication import current_employee


BODY = {'manufacturer_id': 1, 'title': ' 제조사 구매 ', 'reason': ' 부족 재고 보충 ',
        'items': [{'product_variant_id': 12, 'requested_quantity': 100},
                  {'product_variant_id': 13, 'requested_quantity': 20}]}


@pytest.fixture
def client():
    db = MagicMock()
    cursor = db.cursor.return_value.__enter__.return_value
    cursor.lastrowid = 0
    state = {'manufacturer': {'manufacturer_id': 1, 'manufacturer_name': '제조사'},
             'workflow': {'approval_workflow_id': 1}, 'total_count': 21}
    rows = [dict(product_variant_id=i, product_code=f'SKU-{i}', product_name='운동화',
                 color_name='검정', size_mm=250, variant_active=1, product_active=1,
                 manufacturer_id=1) for i in (12, 13)]
    cursor.fetchall.return_value = rows

    def execute(query, params=()):
        if query.startswith('INSERT'):
            cursor.lastrowid += 1

    def fetchone():
        query = cursor.execute.call_args.args[0]
        if query.startswith('SELECT COUNT(*)'):
            return {'total_count': state['total_count']}
        if 'FROM manufacturers' in query:
            return state['manufacturer']
        if 'FROM approval_workflows' in query:
            return state['workflow']
        return {'created_at': datetime(2026, 10, 10, 12)}

    cursor.execute.side_effect = execute
    cursor.fetchone.side_effect = fetchone
    app.dependency_overrides[feature.get_db] = lambda: db
    employee = {'employee_id': 15, 'permissions': ['PROCUREMENT_REQUISITION_CREATE'],
                'branches': [{'branch_id': 2}]}
    app.dependency_overrides[current_employee] = lambda: employee
    try:
        with TestClient(app) as c:
            yield c, db, cursor, state, rows, employee
    finally:
        app.dependency_overrides.clear()


def test_create_draft_with_items_and_authenticated_author(client):
    c, db, cursor, *_ = client
    r = c.post('/api/v1/purchase-requisitions', json=BODY)
    assert r.status_code == 201
    data = r.json()['data']
    assert data['requisition_status'] == 'DRAFT'
    assert data['requested_by_employee_id'] == 15
    assert data['title'] == '제조사 구매'
    assert data['submitted_at'] is None
    assert [i['requested_quantity'] for i in data['items']] == [100, 20]
    inserts = [call.args for call in cursor.execute.call_args_list if call.args[0].startswith('INSERT')]
    assert inserts[0][1] == (15, None, 1, '제조사 구매', '부족 재고 보충')
    assert inserts[1][1] == (1, 12, 100)
    assert inserts[2][1] == (1, 13, 20)
    db.commit.assert_called_once()
    db.rollback.assert_not_called()


@pytest.mark.parametrize('change', [
    {'title': ' '}, {'title': 'x'*151}, {'reason': ''}, {'items': []},
    {'items': [BODY['items'][0], BODY['items'][0]]},
    {'items': [{'product_variant_id': 12, 'requested_quantity': 0}]},
    {'items': [{'product_variant_id': 12, 'requested_quantity': -1}]},
    {'items': [{'product_variant_id': 12, 'requested_quantity': True}]},
    {'items': [{'product_variant_id': 12, 'requested_quantity': 1.5}]},
    {'requested_by_employee_id': 999}, {'requisition_status': 'APPROVED'},
])
def test_invalid_input_has_no_writes(client, change):
    c, db, cursor, *_ = client
    r = c.post('/api/v1/purchase-requisitions', json=BODY | change)
    assert r.status_code == 400
    assert r.json()['error']['code'] == 'INVALID_INPUT'
    assert not any(call.args[0].startswith('INSERT') for call in cursor.execute.call_args_list)
    db.commit.assert_not_called()


@pytest.mark.parametrize('kind,status', [('manufacturer', 404), ('workflow', 409),
                                       ('missing_variant', 404), ('inactive', 409), ('wrong_manufacturer', 400)])
def test_business_validation_before_inserting(client, kind, status):
    c, db, cursor, state, rows, _ = client
    if kind in state:
        state[kind] = None
    elif kind == 'missing_variant':
        rows.pop()
    elif kind == 'inactive':
        rows[0]['variant_active'] = 0
    else:
        rows[0]['manufacturer_id'] = 2
    r = c.post('/api/v1/purchase-requisitions', json=BODY)
    assert r.status_code == status
    assert not any(call.args[0].startswith('INSERT') for call in cursor.execute.call_args_list)
    db.commit.assert_not_called()
    db.rollback.assert_called()


def test_item_failure_rolls_back_entire_draft(client):
    c, db, cursor, *_ = client
    original = cursor.execute.side_effect

    def fail_second_item(query, params):
        if query.startswith('INSERT INTO purchase_requisition_items') and params[1] == 13:
            raise OperationalError(2000, 'private SQL connection')
        return original(query, params)

    cursor.execute.side_effect = fail_second_item
    r = c.post('/api/v1/purchase-requisitions', json=BODY)
    assert r.status_code == 500
    assert 'private' not in r.text
    db.commit.assert_not_called()
    db.rollback.assert_called()


def test_permission_required(client):
    c, db, cursor, _, _, employee = client
    employee['permissions'] = []
    assert c.post('/api/v1/purchase-requisitions', json=BODY).status_code == 403
    cursor.execute.assert_not_called()
    db.commit.assert_not_called()


def test_login_required(client):
    c, db, cursor, *_ = client
    del app.dependency_overrides[current_employee]
    assert c.post('/api/v1/purchase-requisitions', json=BODY).status_code == 401
    cursor.execute.assert_not_called()


def test_optional_branch_must_be_assigned(client):
    c, db, cursor, *_ = client
    assert c.post('/api/v1/purchase-requisitions', json=BODY | {'branch_id': 1}).status_code == 403
    cursor.execute.assert_not_called()
    assert c.post('/api/v1/purchase-requisitions', json=BODY | {'branch_id': 2}).status_code == 201


def test_creation_options_uses_active_products_and_manufacturer_relation(client):
    c, db, cursor, _, rows, _ = client
    for row in rows:
        row.update(manufacturer_name='제조사', quantity=29)
    response = c.get('/api/v1/purchase-requisitions/creation-options')
    assert response.status_code == 200
    assert response.json()['data'][0]['manufacturer_id'] == 1
    assert response.json()['data'][0]['target_quantity'] == 100
    query = cursor.execute.call_args.args[0]
    assert 'pv.is_active=1 AND p.is_active=1' in query
    assert 'm.manufacturer_id=p.manufacturer_id' in query
    db.commit.assert_not_called()


def test_creation_options_require_permission(client):
    c, _, cursor, _, _, employee = client
    employee['permissions'] = []
    assert c.get('/api/v1/purchase-requisitions/creation-options').status_code == 403
    cursor.execute.assert_not_called()


def summary():
    return dict(purchase_requisition_id=19, requested_by_employee_id=15,
        employee_name='작성 직원', branch_id=None, branch_name=None, title='기존 구매 품의',
        requisition_status='DRAFT', created_at=datetime(2026,10,10,12),
        submitted_at=None, item_count=2, total_requested_quantity=120)


def test_recent_list_is_paginated_latest_first_and_scoped_to_author(client):
    c, db, cursor, _, rows, _ = client
    cursor.fetchall.return_value = [summary()]
    r = c.get('/api/v1/purchase-requisitions?page=2&status=DRAFT')
    assert r.status_code == 200
    assert r.json()['pagination'] == {'page': 2, 'page_size': 20, 'total_count': 21}
    assert r.json()['data'][0]['item_count'] == 2
    count, listing = cursor.execute.call_args_list
    assert count.args[1] == (15, 'DRAFT')
    assert listing.args[1] == (15, 'DRAFT', 20, 20)
    assert 'pr.requested_by_employee_id=%s' in listing.args[0]
    assert 'pr.created_at DESC, pr.purchase_requisition_id DESC' in listing.args[0]
    assert 'COUNT(*) FROM purchase_requisition_items' in listing.args[0]
    db.commit.assert_not_called()


def test_reviewer_lists_all_requisitions_without_author_filter(client):
    c, _, cursor, _, _, employee = client
    employee['permissions'] = ['PROCUREMENT_APPROVE_DIRECTOR']
    cursor.fetchall.return_value = [summary()]
    r = c.get('/api/v1/purchase-requisitions?employee_id=999')
    assert r.status_code == 200
    assert 'pr.requested_by_employee_id=%s' not in cursor.execute.call_args.args[0]
    assert cursor.execute.call_args.args[1] == (20, 0)


def test_empty_recent_list(client):
    c, _, cursor, state, *_ = client
    state['total_count'] = 0
    cursor.fetchall.return_value = []
    r = c.get('/api/v1/purchase-requisitions')
    assert r.status_code == 200
    assert r.json()['data'] == []
    assert r.json()['pagination']['total_count'] == 0


@pytest.mark.parametrize('query', ['page=0','page_size=101','status=NOT_A_STATUS'])
def test_recent_list_invalid_query(client, query):
    c, _, cursor, *_ = client
    assert c.get('/api/v1/purchase-requisitions?'+query).status_code == 400
    cursor.execute.assert_not_called()


def test_recent_list_requires_auth_and_permission(client):
    c, _, cursor, _, _, employee = client
    employee['permissions'] = []
    assert c.get('/api/v1/purchase-requisitions').status_code == 403
    del app.dependency_overrides[current_employee]
    assert c.get('/api/v1/purchase-requisitions').status_code == 401
    cursor.execute.assert_not_called()


def test_recent_list_ascending_order_and_invalid_direction(client):
    c,_,cursor,*_=client
    cursor.fetchall.return_value=[summary()]
    assert c.get('/api/v1/purchase-requisitions?order=asc').status_code==200
    assert 'ORDER BY pr.created_at ASC, pr.purchase_requisition_id ASC' in cursor.execute.call_args.args[0]
    cursor.execute.reset_mock()
    assert c.get('/api/v1/purchase-requisitions?order=asc;DROP TABLE').status_code==400
    cursor.execute.assert_not_called()
