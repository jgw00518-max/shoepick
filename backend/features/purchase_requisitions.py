"""구매 품의 작성·조회·수정·상신.

기존 테이블: purchase_requisitions, purchase_requisition_items.
직원 ID는 요청 본문 대신 검증된 로그인 정보에서 가져온다.
"""

from datetime import datetime
import hashlib
import json
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Path
from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator
from pymysql.connections import Connection
from pymysql.cursors import DictCursor

from .authentication import AuthRoute, AuthError, current_employee, check_branch, require_permission

if __package__ == 'backend.features':
    from ..dependencies import get_db
else:
    from dependencies import get_db

router = APIRouter(prefix="/purchase-requisitions", tags=["구매 품의"], route_class=AuthRoute)

# 1. 요청·응답 모델
PositiveId = Annotated[int, Field(strict=True, gt=0, le=18446744073709551615)]


class RequisitionItemRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    product_variant_id: PositiveId
    requested_quantity: Annotated[int, Field(strict=True, gt=0, le=4294967295)]


class RequisitionCreateRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    manufacturer_id: PositiveId
    branch_id: PositiveId | None = None
    title: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=150)]
    reason: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)]
    items: Annotated[list[RequisitionItemRequest], Field(min_length=1, max_length=100)]

    @model_validator(mode='after')
    def unique_variants(self):
        ids = [item.product_variant_id for item in self.items]
        if len(ids) != len(set(ids)):
            raise ValueError('중복 상품 옵션은 한 품목으로 합쳐주세요.')
        return self


class RequisitionCreatedItem(RequisitionItemRequest):
    purchase_requisition_item_id: int
    product_code: str
    product_name: str
    color_name: str
    size_mm: int


class RequisitionCreated(BaseModel):
    purchase_requisition_id: int
    requested_by_employee_id: int
    branch_id: int | None
    approval_workflow_id: int
    manufacturer_id: int
    manufacturer_name: str
    title: str
    reason: str
    requisition_status: Literal['DRAFT']
    submitted_at: None = None
    created_at: datetime
    items: list[RequisitionCreatedItem]


class RequisitionCreateResponse(BaseModel):
    data: RequisitionCreated


RequisitionStatus = Literal['DRAFT', 'SUBMITTED', 'PENDING_TEAM_LEAD',
    'PENDING_DIRECTOR', 'APPROVED', 'REJECTED', 'ORDERED', 'CANCELED']
REVIEW_PERMISSIONS = {'PROCUREMENT_APPROVE_TEAM_LEAD', 'PROCUREMENT_APPROVE_DIRECTOR',
                      'AUDIT_LOG_READ', 'ROLE_MANAGE'}


def require_requisition_read(employee: Annotated[dict, Depends(current_employee)]) -> dict:
    if not set(employee['permissions']) & (REVIEW_PERMISSIONS | {
        'PROCUREMENT_REQUISITION_CREATE', 'PROCUREMENT_REQUISITION_SUBMIT'}):
        raise AuthError('FORBIDDEN')
    return employee


class RequisitionSummary(BaseModel):
    purchase_requisition_id: int
    requested_by_employee_id: int
    employee_name: str
    branch_id: int | None
    branch_name: str | None
    title: str
    requisition_status: RequisitionStatus
    created_at: datetime
    submitted_at: datetime | None
    item_count: int
    total_requested_quantity: int
    can_edit: bool = False
    can_submit: bool = False


class RequisitionPagination(BaseModel):
    page: int
    page_size: int
    total_count: int


class RequisitionListResponse(BaseModel):
    data: list[RequisitionSummary]
    pagination: RequisitionPagination


class RequisitionUpdateRequest(RequisitionCreateRequest):
    revision: Annotated[str, Field(pattern=r'^[0-9a-f]{64}$')]


class RequisitionSubmitRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    revision: Annotated[str, Field(pattern=r'^[0-9a-f]{64}$')]


class RequisitionDetailItem(RequisitionCreatedItem):
    manufacturer_id: int | None
    manufacturer_name: str | None


class RequisitionDetail(BaseModel):
    purchase_requisition_id: int
    requested_by_employee_id: int
    branch_id: int | None
    approval_workflow_id: int
    title: str
    reason: str
    requisition_status: RequisitionStatus
    submitted_at: datetime | None
    created_at: datetime
    items: list[RequisitionDetailItem]
    revision: str


class RequisitionDetailResponse(BaseModel):
    data: RequisitionDetail


def _read_requisition_detail(cursor, requisition_id: int, employee: dict, *, lock=False, allow_monitor=False):
    cursor.execute('SELECT purchase_requisition_id, requested_by_employee_id, branch_id, '
        'approval_workflow_id, title, reason, requisition_status, submitted_at, created_at '
        'FROM purchase_requisitions WHERE purchase_requisition_id=%s' + (' FOR UPDATE' if lock else ''),
        (requisition_id,))
    row = cursor.fetchone()
    if row is None:
        _error(404, 'NOT_FOUND', '구매 품의를 찾을 수 없습니다.')
    if row['requested_by_employee_id'] != employee['employee_id'] and not allow_monitor and not set(employee['permissions']) & REVIEW_PERMISSIONS:
        raise AuthError('FORBIDDEN')
    cursor.execute('SELECT i.purchase_requisition_item_id, i.product_variant_id, i.requested_quantity, '
        'pv.product_code, pv.color_name, pv.size_mm, p.product_name, p.manufacturer_id, m.manufacturer_name '
        'FROM purchase_requisition_items i JOIN product_variants pv ON pv.product_variant_id=i.product_variant_id '
        'JOIN products p ON p.product_id=pv.product_id LEFT JOIN manufacturers m ON m.manufacturer_id=p.manufacturer_id '
        'WHERE i.purchase_requisition_id=%s ORDER BY i.product_variant_id' + (' FOR UPDATE' if lock else ''),
        (requisition_id,))
    items = cursor.fetchall()
    revision = hashlib.sha256(json.dumps({
        'header': row,
        'items': [(i['purchase_requisition_item_id'], i['product_variant_id'], i['requested_quantity']) for i in items],
    }, sort_keys=True, default=str).encode('utf-8')).hexdigest()
    return RequisitionDetailResponse(data=RequisitionDetail(**row, items=items, revision=revision))


def list_purchase_requisitions(db: Connection, *, employee: dict, page: int,
    page_size: int, status: RequisitionStatus | None, order: Literal['asc','desc']='desc') -> RequisitionListResponse:
    direction={'asc':'ASC','desc':'DESC'}[order]
    conditions, params = [], []
    if not set(employee['permissions']) & REVIEW_PERMISSIONS:
        conditions.append('pr.requested_by_employee_id=%s')
        params.append(employee['employee_id'])
    if status is not None:
        conditions.append('pr.requisition_status=%s')
        params.append(status)
    where = ' WHERE ' + ' AND '.join(conditions) if conditions else ''
    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT COUNT(*) AS total_count FROM purchase_requisitions pr' + where, tuple(params))
        total_count = cursor.fetchone()['total_count']
        cursor.execute(
            'SELECT pr.purchase_requisition_id, pr.requested_by_employee_id, e.employee_name, '
            'pr.branch_id, b.branch_name, pr.title, pr.requisition_status, pr.created_at, pr.submitted_at, '
            '(SELECT COUNT(*) FROM purchase_requisition_items i '
            ' WHERE i.purchase_requisition_id=pr.purchase_requisition_id) AS item_count, '
            '(SELECT COALESCE(SUM(i.requested_quantity),0) FROM purchase_requisition_items i '
            ' WHERE i.purchase_requisition_id=pr.purchase_requisition_id) AS total_requested_quantity '
            'FROM purchase_requisitions pr JOIN employees e ON e.employee_id=pr.requested_by_employee_id '
            'LEFT JOIN branches b ON b.branch_id=pr.branch_id' + where +
            f' ORDER BY pr.created_at {direction}, pr.purchase_requisition_id {direction} LIMIT %s OFFSET %s',
            tuple(params) + (page_size, (page - 1) * page_size),
        )
        rows = cursor.fetchall()
        for row in rows:
            row['can_submit'] = (row['requested_by_employee_id'] == employee['employee_id']
                and row['requisition_status'] == 'DRAFT'
                and 'PROCUREMENT_REQUISITION_SUBMIT' in employee['permissions'])
            row['can_edit'] = (row['requested_by_employee_id'] == employee['employee_id']
                and row['requisition_status'] == 'DRAFT'
                and 'PROCUREMENT_REQUISITION_CREATE' in employee['permissions'])
        return RequisitionListResponse(data=rows, pagination=RequisitionPagination(
            page=page, page_size=page_size, total_count=total_count))


@router.get('', response_model=RequisitionListResponse, summary='최근 구매 품의 목록 조회')
def get_purchase_requisitions(
    employee: Annotated[dict, Depends(require_requisition_read)],
    db: Annotated[Connection, Depends(get_db)],
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    status: RequisitionStatus | None = None,
    order: Literal['asc','desc'] = 'desc',
) -> RequisitionListResponse:
    return list_purchase_requisitions(db, employee=employee, page=page, page_size=page_size, status=status,order=order)


class RequisitionOption(BaseModel):
    manufacturer_id: int
    manufacturer_name: str
    product_variant_id: int
    product_code: str
    product_name: str
    color_name: str
    size_mm: int
    quantity: int
    target_quantity: int = 100


class RequisitionOptionsResponse(BaseModel):
    data: list[RequisitionOption]


@router.get('/creation-options', response_model=RequisitionOptionsResponse,
            summary='구매 품의 작성용 제조사·상품 옵션 조회')
def get_requisition_options(
    employee: Annotated[dict, Depends(require_permission('PROCUREMENT_REQUISITION_CREATE'))],
    db: Annotated[Connection, Depends(get_db)],
) -> RequisitionOptionsResponse:
    with db.cursor(DictCursor) as cursor:
        cursor.execute(
            'SELECT m.manufacturer_id, m.manufacturer_name, pv.product_variant_id, '
            'pv.product_code, p.product_name, pv.color_name, pv.size_mm, '
            'COALESCE(hi.on_hand_quantity,0) AS quantity '
            'FROM product_variants pv JOIN products p ON p.product_id=pv.product_id '
            'JOIN manufacturers m ON m.manufacturer_id=p.manufacturer_id '
            'LEFT JOIN headquarters_inventory hi ON hi.product_variant_id=pv.product_variant_id '
            'WHERE pv.is_active=1 AND p.is_active=1 '
            'ORDER BY m.manufacturer_id, p.product_name, pv.product_code'
        )
        return RequisitionOptionsResponse(data=cursor.fetchall())


def _error(status: int, code: str, message: str):
    raise HTTPException(status_code=status, detail={'code': code, 'message': message})


# 2. 업무 함수: 작성자 ID는 검증된 직원 정보에서만 가져온다.
def create_purchase_requisition(
    db: Connection, *, request: RequisitionCreateRequest, employee: dict,
) -> RequisitionCreateResponse:
    if request.branch_id is not None:
        check_branch(employee, request.branch_id)
    try:
        with db.cursor(DictCursor) as cursor:
            cursor.execute('SELECT manufacturer_id, manufacturer_name FROM manufacturers '
                           'WHERE manufacturer_id=%s FOR SHARE', (request.manufacturer_id,))
            manufacturer = cursor.fetchone()
            if manufacturer is None:
                _error(404, 'NOT_FOUND', '제조사를 찾을 수 없습니다.')

            cursor.execute('SELECT approval_workflow_id FROM approval_workflows '
                           'WHERE workflow_code=%s AND is_active=1 FOR SHARE', ('PROCUREMENT_STANDARD',))
            workflow = cursor.fetchone()
            if workflow is None:
                _error(409, 'INVALID_STATE', '활성 표준 구매 결재 경로가 없습니다.')

            ids = sorted(item.product_variant_id for item in request.items)
            placeholders = ','.join(['%s'] * len(ids))
            cursor.execute(
                'SELECT pv.product_variant_id, pv.product_code, pv.color_name, pv.size_mm, '
                'pv.is_active AS variant_active, p.product_name, p.manufacturer_id, '
                'p.is_active AS product_active FROM product_variants pv '
                'JOIN products p ON p.product_id=pv.product_id '
                f'WHERE pv.product_variant_id IN ({placeholders}) '
                'ORDER BY pv.product_variant_id FOR SHARE', tuple(ids),
            )
            variants = {row['product_variant_id']: row for row in cursor.fetchall()}
            if len(variants) != len(ids):
                _error(404, 'NOT_FOUND', '존재하지 않는 상품 옵션이 포함되어 있습니다.')
            for variant in variants.values():
                if not variant['variant_active'] or not variant['product_active']:
                    _error(409, 'INVALID_STATE', '비활성 상품 또는 옵션은 구매 품의에 사용할 수 없습니다.')
                if variant['manufacturer_id'] != request.manufacturer_id:
                    _error(400, 'INVALID_INPUT', '모든 품목은 선택한 제조사의 상품이어야 합니다.')

            cursor.execute(
                'INSERT INTO purchase_requisitions '
                '(requested_by_employee_id, branch_id, approval_workflow_id, title, reason, requisition_status) '
                "VALUES (%s,%s,%s,%s,%s,'DRAFT')",
                (employee['employee_id'], request.branch_id, workflow['approval_workflow_id'], request.title, request.reason),
            )
            requisition_id = cursor.lastrowid
            created_items = []
            for item in request.items:
                cursor.execute('INSERT INTO purchase_requisition_items '
                               '(purchase_requisition_id, product_variant_id, requested_quantity) '
                               'VALUES (%s,%s,%s)',
                               (requisition_id, item.product_variant_id, item.requested_quantity))
                variant = variants[item.product_variant_id]
                created_items.append(RequisitionCreatedItem(
                    **item.model_dump(), purchase_requisition_item_id=cursor.lastrowid,
                    product_code=variant['product_code'], product_name=variant['product_name'],
                    color_name=variant['color_name'], size_mm=variant['size_mm'],
                ))
            cursor.execute('SELECT created_at FROM purchase_requisitions '
                           'WHERE purchase_requisition_id=%s', (requisition_id,))
            created_at = cursor.fetchone()['created_at']
            response = RequisitionCreateResponse(data=RequisitionCreated(
                purchase_requisition_id=requisition_id, requested_by_employee_id=employee['employee_id'],
                approval_workflow_id=workflow['approval_workflow_id'],
                manufacturer_name=manufacturer['manufacturer_name'],
                **request.model_dump(exclude={'items'}), requisition_status='DRAFT',
                created_at=created_at, items=created_items,
            ))
        db.commit()
        return response
    except Exception:
        db.rollback()
        raise


# 3. API 함수: 작성은 초안 저장이며 상신·결재·발주는 별도 기능이다.
@router.post('', status_code=201, response_model=RequisitionCreateResponse,
             summary='제조사 구매 품의 초안 작성')
def post_purchase_requisition(
    request: RequisitionCreateRequest,
    employee: Annotated[dict, Depends(require_permission('PROCUREMENT_REQUISITION_CREATE'))],
    db: Annotated[Connection, Depends(get_db)],
) -> RequisitionCreateResponse:
    return create_purchase_requisition(db, request=request, employee=employee)


def update_purchase_requisition(db: Connection, *, requisition_id: int,
    request: RequisitionUpdateRequest, employee: dict) -> RequisitionDetailResponse:
    try:
        with db.cursor(DictCursor) as cursor:
            original = _read_requisition_detail(cursor, requisition_id, employee, lock=True).data
            if original.requested_by_employee_id != employee['employee_id']:
                raise AuthError('FORBIDDEN')
            if original.requisition_status != 'DRAFT':
                _error(409, 'INVALID_STATE', '초안 상태의 품의만 수정할 수 있습니다.')
            if original.revision != request.revision:
                _error(409, 'CONFLICT', '다른 곳에서 품의가 변경되었습니다. 다시 불러온 뒤 수정해주세요.')
            if original.branch_id != request.branch_id:
                _error(400, 'INVALID_INPUT', '수정 시 기존 품의의 소속 지점은 변경할 수 없습니다.')
            if request.branch_id is not None:
                check_branch(employee, request.branch_id)
            cursor.execute('SELECT manufacturer_id FROM manufacturers WHERE manufacturer_id=%s FOR SHARE',
                (request.manufacturer_id,))
            if cursor.fetchone() is None:
                _error(404, 'NOT_FOUND', '제조사를 찾을 수 없습니다.')
            ids = sorted(i.product_variant_id for i in request.items)
            cursor.execute('SELECT pv.product_variant_id, pv.is_active AS variant_active, '
                'p.is_active AS product_active, p.manufacturer_id FROM product_variants pv '
                'JOIN products p ON p.product_id=pv.product_id WHERE pv.product_variant_id IN (' +
                ','.join(['%s'] * len(ids)) + ') ORDER BY pv.product_variant_id FOR SHARE', tuple(ids))
            variants = cursor.fetchall()
            if len(variants) != len(ids):
                _error(404, 'NOT_FOUND', '존재하지 않는 상품 옵션이 포함되어 있습니다.')
            for v in variants:
                if not v['variant_active'] or not v['product_active']:
                    _error(409, 'INVALID_STATE', '비활성 상품 또는 옵션은 구매 품의에 사용할 수 없습니다.')
                if v['manufacturer_id'] != request.manufacturer_id:
                    _error(400, 'INVALID_INPUT', '모든 품목은 선택한 제조사의 상품이어야 합니다.')
            cursor.execute('UPDATE purchase_requisitions SET title=%s, reason=%s '
                'WHERE purchase_requisition_id=%s', (request.title, request.reason, requisition_id))
            cursor.execute('DELETE FROM purchase_requisition_items WHERE purchase_requisition_id=%s', (requisition_id,))
            for i in request.items:
                cursor.execute('INSERT INTO purchase_requisition_items '
                    '(purchase_requisition_id,product_variant_id,requested_quantity) VALUES (%s,%s,%s)',
                    (requisition_id, i.product_variant_id, i.requested_quantity))
            response = _read_requisition_detail(cursor, requisition_id, employee, lock=True)
        db.commit()
        return response
    except Exception:
        db.rollback()
        raise


@router.get('/{purchase_requisition_id}', response_model=RequisitionDetailResponse,
    summary='구매 품의 상세 조회')
def get_requisition_detail(
    purchase_requisition_id: Annotated[int, Path(gt=0)],
    employee: Annotated[dict, Depends(require_requisition_read)],
    db: Annotated[Connection, Depends(get_db)],
) -> RequisitionDetailResponse:
    with db.cursor(DictCursor) as cursor:
        return _read_requisition_detail(cursor, purchase_requisition_id, employee)


@router.patch('/{purchase_requisition_id}', response_model=RequisitionDetailResponse,
    summary='구매 품의 초안 수정')
def patch_requisition(
    purchase_requisition_id: Annotated[int, Path(gt=0)], request: RequisitionUpdateRequest,
    employee: Annotated[dict, Depends(require_permission('PROCUREMENT_REQUISITION_CREATE'))],
    db: Annotated[Connection, Depends(get_db)],
) -> RequisitionDetailResponse:
    return update_purchase_requisition(db, requisition_id=purchase_requisition_id,
        request=request, employee=employee)


def submit_purchase_requisition(db: Connection, *, requisition_id: int,
    request: RequisitionSubmitRequest, employee: dict) -> RequisitionDetailResponse:
    try:
        with db.cursor(DictCursor) as cursor:
            detail = _read_requisition_detail(cursor, requisition_id, employee, lock=True).data
            if detail.requested_by_employee_id != employee['employee_id']:
                raise AuthError('FORBIDDEN')
            if detail.requisition_status != 'DRAFT':
                _error(409, 'INVALID_STATE', '초안 상태의 품의만 상신할 수 있습니다. 이미 상신되었는지 확인해주세요.')
            if detail.revision != request.revision:
                _error(409, 'CONFLICT', '품의 내용이 변경되었습니다. 다시 확인한 뒤 상신해주세요.')
            if detail.branch_id is not None:
                check_branch(employee, detail.branch_id)
            manufacturers = {i.manufacturer_id for i in detail.items}
            if not detail.items or len(manufacturers) != 1 or None in manufacturers:
                _error(409, 'INVALID_STATE', '상신할 품의에는 한 제조사의 구매 품목이 있어야 합니다.')
            # 생성·수정과 같은 검증으로 이전 데이터의 빈 제목·사유·잘못된 수량도 거절한다.
            try:
                RequisitionCreateRequest(manufacturer_id=next(iter(manufacturers)), branch_id=detail.branch_id,
                    title=detail.title, reason=detail.reason,
                    items=[RequisitionItemRequest(product_variant_id=i.product_variant_id,
                        requested_quantity=i.requested_quantity) for i in detail.items])
            except ValueError:
                _error(409, 'INVALID_STATE', '품의 제목·사유·품목·수량을 수정한 뒤 상신해주세요.')
            ids = sorted(i.product_variant_id for i in detail.items)
            cursor.execute('SELECT pv.product_variant_id FROM product_variants pv '
                'JOIN products p ON p.product_id=pv.product_id '
                'WHERE pv.is_active=1 AND p.is_active=1 AND pv.product_variant_id IN (' +
                ','.join(['%s']*len(ids)) + ') ORDER BY pv.product_variant_id FOR SHARE', tuple(ids))
            if len(cursor.fetchall()) != len(ids):
                _error(409, 'INVALID_STATE', '비활성 상품 또는 옵션은 상신할 수 없습니다.')
            cursor.execute('SELECT approval_workflow_id FROM approval_workflows '
                'WHERE approval_workflow_id=%s AND is_active=1 FOR SHARE', (detail.approval_workflow_id,))
            if cursor.fetchone() is None:
                _error(409, 'INVALID_STATE', '활성 결재 경로가 없습니다.')
            cursor.execute('SELECT s.step_order,s.required_role_id,r.role_code,r.is_active '
                'FROM approval_workflow_steps s JOIN roles r ON r.role_id=s.required_role_id '
                'WHERE s.approval_workflow_id=%s ORDER BY s.step_order FOR SHARE', (detail.approval_workflow_id,))
            steps = cursor.fetchall()
            if [(s['step_order'],s['role_code']) for s in steps] != [(1,'TEAM_LEAD'),(2,'DIRECTOR')] or not all(s['is_active'] for s in steps):
                _error(409, 'INVALID_STATE', '팀장·이사 결재 경로 설정을 확인해주세요.')
            cursor.execute('SELECT purchase_approval_id FROM purchase_approvals '
                'WHERE purchase_requisition_id=%s FOR UPDATE', (requisition_id,))
            if cursor.fetchall():
                _error(409, 'INVALID_STATE', '초안에 이미 결재 기록이 있습니다. 기존 상태를 확인해주세요.')
            for step in steps:
                cursor.execute('INSERT INTO purchase_approvals '
                    '(purchase_requisition_id,approval_sequence,required_role_id,approval_status) '
                    "VALUES (%s,%s,%s,'PENDING')", (requisition_id,step['step_order'],step['required_role_id']))
            cursor.execute("UPDATE purchase_requisitions SET requisition_status='PENDING_TEAM_LEAD', "
                'submitted_at=CURRENT_TIMESTAMP WHERE purchase_requisition_id=%s', (requisition_id,))
            response = _read_requisition_detail(cursor, requisition_id, employee, lock=True)
        db.commit()
        return response
    except Exception:
        db.rollback()
        raise


@router.post('/{purchase_requisition_id}/submit', response_model=RequisitionDetailResponse,
    summary='구매 품의 초안 상신')
def post_requisition_submit(
    purchase_requisition_id: Annotated[int, Path(gt=0)], request: RequisitionSubmitRequest,
    employee: Annotated[dict, Depends(require_permission('PROCUREMENT_REQUISITION_SUBMIT'))],
    db: Annotated[Connection, Depends(get_db)],
) -> RequisitionDetailResponse:
    return submit_purchase_requisition(db,requisition_id=purchase_requisition_id,request=request,employee=employee)
