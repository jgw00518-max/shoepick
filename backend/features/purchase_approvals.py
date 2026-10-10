"""구매 품의의 팀장·이사 결재와 승인·반려 이력.

기존 테이블: purchase_approvals, approval_workflows,
approval_workflow_steps, purchase_requisitions.
"""

from datetime import datetime, date, time
from typing import Annotated, Literal
from fastapi import APIRouter, Depends, Path, Query
from pydantic import BaseModel, ConfigDict, Field, StringConstraints
from pymysql.connections import Connection
from pymysql.cursors import DictCursor
from .authentication import AuthRoute, AuthError, current_employee
from .purchase_requisitions import RequisitionDetail, _read_requisition_detail, _error
from .manufacturer_orders import ManufacturerOrderRegistered, register_approved_order

if __package__ == 'backend.features':
    from ..dependencies import get_db
else:
    from dependencies import get_db

router = APIRouter(prefix="/purchase-approvals", tags=["구매 결재"], route_class=AuthRoute)

ApprovalStage = Literal['TEAM_LEAD', 'DIRECTOR']
STAGES = {
    'TEAM_LEAD': ('PROCUREMENT_APPROVE_TEAM_LEAD', 'PENDING_TEAM_LEAD', 1),
    'DIRECTOR': ('PROCUREMENT_APPROVE_DIRECTOR', 'PENDING_DIRECTOR', 2),
}


class ApprovalSummary(BaseModel):
    purchase_approval_id: int
    purchase_requisition_id: int
    approval_sequence: int
    title: str
    employee_name: str
    branch_name: str | None
    requisition_status: str
    approval_status: str
    submitted_at: datetime | None
    decided_at: datetime | None
    approval_comment: str | None
    item_count: int
    total_requested_quantity: int


class ApprovalPagination(BaseModel):
    page: int
    page_size: int
    total_count: int


class ApprovalListResponse(BaseModel):
    data: list[ApprovalSummary]
    pagination: ApprovalPagination


class ApprovalStep(BaseModel):
    approval_sequence: int
    role_code: str
    role_name: str
    approval_status: str
    approver_name: str | None
    approval_comment: str | None
    decided_at: datetime | None


class ApprovalDetail(BaseModel):
    approval: ApprovalSummary
    requisition: RequisitionDetail
    steps: list[ApprovalStep]


class ApprovalDetailResponse(BaseModel):
    data: ApprovalDetail


class ApprovalDecisionRequest(BaseModel):
    model_config=ConfigDict(extra='forbid')
    revision: Annotated[str,Field(pattern=r'^[0-9a-f]{64}$')]
    comment: Annotated[str,StringConstraints(strip_whitespace=True,max_length=2000)]=''


class ApprovalDecisionResult(BaseModel):
    purchase_approval_id: int
    purchase_requisition_id: int
    approval_status: Literal['APPROVED','REJECTED']
    approver_employee_id: int
    approval_comment: str | None
    decided_at: datetime
    requisition_status: Literal['PENDING_DIRECTOR','APPROVED','REJECTED','ORDERED']
    manufacturer_order: ManufacturerOrderRegistered | None = None


class ApprovalDecisionResponse(BaseModel):
    data: ApprovalDecisionResult


def decide_purchase_approval(db: Connection,*,approval_id: int,employee: dict,
    request: ApprovalDecisionRequest,decision: Literal['APPROVED','REJECTED'],
    stage: ApprovalStage='TEAM_LEAD') -> ApprovalDecisionResponse:
    permission, pending_status, sequence = STAGES[stage]
    if permission not in employee['permissions']:
        raise AuthError('FORBIDDEN')
    if decision=='REJECTED' and not request.comment:
        _error(400,'INVALID_INPUT','반려 사유를 입력해주세요.')
    try:
        with db.cursor(DictCursor) as cursor:
            cursor.execute('SELECT purchase_requisition_id FROM purchase_approvals WHERE purchase_approval_id=%s',(approval_id,))
            ref=cursor.fetchone()
            if ref is None:_error(404,'NOT_FOUND','결재 기록을 찾을 수 없습니다.')
            requisition_id=ref['purchase_requisition_id']
            # 상신·수정과 같은 순서(품의 → 결재)로 잠근다.
            document=_read_requisition_detail(cursor,requisition_id,employee,lock=True).data
            cursor.execute('SELECT pa.purchase_approval_id,pa.approval_sequence,pa.approval_status,r.role_code,r.is_active '
                'FROM purchase_approvals pa JOIN roles r ON r.role_id=pa.required_role_id '
                'WHERE pa.purchase_approval_id=%s AND pa.purchase_requisition_id=%s FOR UPDATE',(approval_id,requisition_id))
            approval=cursor.fetchone()
            if approval is None:_error(404,'NOT_FOUND','결재 기록을 찾을 수 없습니다.')
            if approval['role_code']!=stage or approval['approval_sequence']!=sequence or not approval['is_active']:
                raise AuthError('FORBIDDEN')
            if approval['approval_status']!='PENDING' or document.requisition_status!=pending_status:
                _error(409,'INVALID_STATE','현재 해당 직책의 결재 대기 상태가 아닙니다. 이미 처리되었는지 확인해주세요.')
            if document.revision!=request.revision:
                _error(409,'CONFLICT','품의 내용이 변경되었습니다. 상세 내용을 다시 확인해주세요.')
            cursor.execute('SELECT pa.purchase_approval_id,pa.approval_status FROM purchase_approvals pa '
                'JOIN roles r ON r.role_id=pa.required_role_id AND r.is_active=1 '
                'JOIN approval_workflow_steps s ON s.approval_workflow_id=%s AND s.step_order=pa.approval_sequence '
                'AND s.required_role_id=pa.required_role_id '
                'WHERE pa.purchase_requisition_id=%s AND pa.approval_sequence=%s AND r.role_code=%s FOR UPDATE',
                (document.approval_workflow_id,requisition_id,2 if stage=='TEAM_LEAD' else 1,
                 'DIRECTOR' if stage=='TEAM_LEAD' else 'TEAM_LEAD'))
            related_step=cursor.fetchone()
            required_status='PENDING' if stage=='TEAM_LEAD' else 'APPROVED'
            if related_step is None or related_step['approval_status']!=required_status:
                _error(409,'INVALID_STATE','팀장 승인 및 결재 단계 기록을 확인해주세요.')
            cursor.execute('UPDATE purchase_approvals SET approval_status=%s,approver_employee_id=%s,'
                'approval_comment=%s,decided_at=CURRENT_TIMESTAMP WHERE purchase_approval_id=%s',
                (decision,employee['employee_id'],request.comment or None,approval_id))
            next_status=('PENDING_DIRECTOR' if stage=='TEAM_LEAD' else 'APPROVED') if decision=='APPROVED' else 'REJECTED'
            manufacturer_order = None
            if stage == 'DIRECTOR' and decision == 'APPROVED':
                manufacturer_order = register_approved_order(cursor, document=document, employee_id=employee['employee_id'])
                next_status = 'ORDERED'
            if decision=='REJECTED' and stage=='TEAM_LEAD':
                cursor.execute("UPDATE purchase_approvals SET approval_status='WAIVED',approver_employee_id=NULL,"
                    'approval_comment=%s,decided_at=CURRENT_TIMESTAMP WHERE purchase_approval_id=%s',
                    ('팀장 반려로 이사 결재 미진행',related_step['purchase_approval_id']))
            cursor.execute('UPDATE purchase_requisitions SET requisition_status=%s WHERE purchase_requisition_id=%s',
                (next_status,requisition_id))
            cursor.execute('SELECT purchase_approval_id,purchase_requisition_id,approval_status,approver_employee_id,'
                'approval_comment,decided_at FROM purchase_approvals WHERE purchase_approval_id=%s',(approval_id,))
            response=ApprovalDecisionResponse(data=ApprovalDecisionResult(**cursor.fetchone(),requisition_status=next_status,
                manufacturer_order=manufacturer_order))
        db.commit()
        return response
    except Exception:
        db.rollback();raise


@router.post('/{purchase_approval_id}/approve',response_model=ApprovalDecisionResponse,summary='팀장·이사 결재 승인')
def approve_purchase(purchase_approval_id: Annotated[int,Path(gt=0)],request: ApprovalDecisionRequest,
    employee: Annotated[dict,Depends(current_employee)],
    db: Annotated[Connection,Depends(get_db)],stage: ApprovalStage='TEAM_LEAD'):
    return decide_purchase_approval(db,approval_id=purchase_approval_id,employee=employee,request=request,decision='APPROVED',stage=stage)


@router.post('/{purchase_approval_id}/reject',response_model=ApprovalDecisionResponse,summary='팀장·이사 결재 반려')
def reject_purchase(purchase_approval_id: Annotated[int,Path(gt=0)],request: ApprovalDecisionRequest,
    employee: Annotated[dict,Depends(current_employee)],
    db: Annotated[Connection,Depends(get_db)],stage: ApprovalStage='TEAM_LEAD'):
    return decide_purchase_approval(db,approval_id=purchase_approval_id,employee=employee,request=request,decision='REJECTED',stage=stage)


MonitorStatus = Literal['SUBMITTED','PENDING_TEAM_LEAD','PENDING_DIRECTOR','APPROVED','REJECTED','ORDERED','CANCELED']


def require_approval_monitor(employee: Annotated[dict,Depends(current_employee)]) -> dict:
    # 임원 직책은 기존 DB에서 조회한 활성 직책만 사용한다. 화면 직책이나 이메일은 사용하지 않는다.
    roles={r['role_code'] for r in employee.get('roles',[])}
    if not roles & {'EXECUTIVE','ADMIN'} and 'AUDIT_LOG_READ' not in employee['permissions']:
        raise AuthError('FORBIDDEN')
    return employee


class MonitorSummary(BaseModel):
    purchase_requisition_id: int
    title: str
    employee_name: str
    branch_name: str | None
    requisition_status: MonitorStatus
    submitted_at: datetime
    team_approval_status: str | None
    team_approver_name: str | None
    director_approval_status: str | None
    director_approver_name: str | None
    item_count: int
    total_requested_quantity: int


class MonitorListResponse(BaseModel):
    data: list[MonitorSummary]
    pagination: ApprovalPagination


class MonitorDetail(BaseModel):
    requisition: RequisitionDetail
    steps: list[ApprovalStep]


class MonitorDetailResponse(BaseModel):
    data: MonitorDetail


def list_approval_monitor(db: Connection, *, page: int,page_size: int,status: MonitorStatus | None,
    keyword: str | None,submitted_from: date | None,submitted_to: date | None,order: Literal['asc','desc']='desc') -> MonitorListResponse:
    direction={'asc':'ASC','desc':'DESC'}[order]
    if submitted_from and submitted_to and submitted_from>submitted_to:
        _error(400,'INVALID_INPUT','조회 시작일은 종료일보다 늦을 수 없습니다.')
    conditions=["pr.requisition_status<>'DRAFT'",'pr.submitted_at IS NOT NULL']
    params=[]
    if status:
        conditions.append('pr.requisition_status=%s');params.append(status)
    if keyword and keyword.strip():
        escaped=keyword.strip().replace('!','!!').replace('%','!%').replace('_','!_')
        conditions.append("(pr.title LIKE %s ESCAPE '!' OR e.employee_name LIKE %s ESCAPE '!')")
        params.extend([f'%{escaped}%']*2)
    if submitted_from:
        conditions.append('pr.submitted_at>=%s');params.append(datetime.combine(submitted_from,time.min))
    if submitted_to:
        conditions.append('pr.submitted_at<=%s');params.append(datetime.combine(submitted_to,time.max))
    base=(' FROM purchase_requisitions pr JOIN employees e ON e.employee_id=pr.requested_by_employee_id '
        'LEFT JOIN branches b ON b.branch_id=pr.branch_id ')
    where=' WHERE '+' AND '.join(conditions)
    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT COUNT(*) AS total_count'+base+where,tuple(params))
        count=cursor.fetchone()['total_count']
        cursor.execute('SELECT pr.purchase_requisition_id,pr.title,e.employee_name,b.branch_name,'
            'pr.requisition_status,pr.submitted_at,'
            "CASE WHEN tr.role_code='TEAM_LEAD' THEN ta.approval_status END AS team_approval_status,"
            "CASE WHEN tr.role_code='TEAM_LEAD' THEN te.employee_name END AS team_approver_name,"
            "CASE WHEN dr.role_code='DIRECTOR' THEN da.approval_status END AS director_approval_status,"
            "CASE WHEN dr.role_code='DIRECTOR' THEN de.employee_name END AS director_approver_name,"
            '(SELECT COUNT(*) FROM purchase_requisition_items i WHERE i.purchase_requisition_id=pr.purchase_requisition_id) AS item_count,'
            '(SELECT COALESCE(SUM(i.requested_quantity),0) FROM purchase_requisition_items i '
            'WHERE i.purchase_requisition_id=pr.purchase_requisition_id) AS total_requested_quantity'+base+
            'LEFT JOIN purchase_approvals ta ON ta.purchase_requisition_id=pr.purchase_requisition_id AND ta.approval_sequence=1 '
            'LEFT JOIN roles tr ON tr.role_id=ta.required_role_id LEFT JOIN employees te ON te.employee_id=ta.approver_employee_id '
            'LEFT JOIN purchase_approvals da ON da.purchase_requisition_id=pr.purchase_requisition_id AND da.approval_sequence=2 '
            'LEFT JOIN roles dr ON dr.role_id=da.required_role_id LEFT JOIN employees de ON de.employee_id=da.approver_employee_id '+where+
            f' ORDER BY pr.submitted_at {direction},pr.purchase_requisition_id {direction} LIMIT %s OFFSET %s',
            tuple(params)+(page_size,(page-1)*page_size))
        return MonitorListResponse(data=cursor.fetchall(),pagination=ApprovalPagination(page=page,page_size=page_size,total_count=count))


@router.get('/overview',response_model=MonitorListResponse,summary='임원 전체 결재 현황 조회')
def get_approval_monitor(employee: Annotated[dict,Depends(require_approval_monitor)],
    db: Annotated[Connection,Depends(get_db)],page: Annotated[int,Query(ge=1)]=1,
    page_size: Annotated[int,Query(ge=1,le=100)]=20,status: MonitorStatus | None=None,
    keyword: Annotated[str | None,Query(max_length=150)]=None,
    submitted_from: date | None=None,submitted_to: date | None=None,order: Literal['asc','desc']='desc'):
    return list_approval_monitor(db,page=page,page_size=page_size,status=status,keyword=keyword,
        submitted_from=submitted_from,submitted_to=submitted_to,order=order)


@router.get('/overview/{purchase_requisition_id}',response_model=MonitorDetailResponse,summary='임원 결재 품의 상세 조회')
def get_monitor_detail(purchase_requisition_id: Annotated[int,Path(gt=0)],
    employee: Annotated[dict,Depends(require_approval_monitor)],db: Annotated[Connection,Depends(get_db)]):
    with db.cursor(DictCursor) as cursor:
        detail=_read_requisition_detail(cursor,purchase_requisition_id,employee,allow_monitor=True).data
        if detail.requisition_status=='DRAFT' or detail.submitted_at is None:
            _error(404,'NOT_FOUND','상신된 구매 품의를 찾을 수 없습니다.')
        cursor.execute('SELECT pa.approval_sequence,r.role_code,r.role_name,pa.approval_status,'
            'e.employee_name AS approver_name,pa.approval_comment,pa.decided_at FROM purchase_approvals pa '
            'JOIN roles r ON r.role_id=pa.required_role_id LEFT JOIN employees e ON e.employee_id=pa.approver_employee_id '
            'WHERE pa.purchase_requisition_id=%s ORDER BY pa.approval_sequence',(purchase_requisition_id,))
        return MonitorDetailResponse(data=MonitorDetail(requisition=detail,steps=cursor.fetchall()))


TABLES = (' FROM purchase_approvals pa '
    'JOIN purchase_requisitions pr ON pr.purchase_requisition_id=pa.purchase_requisition_id '
    'JOIN roles r ON r.role_id=pa.required_role_id '
    'JOIN employees e ON e.employee_id=pr.requested_by_employee_id '
    'LEFT JOIN branches b ON b.branch_id=pr.branch_id ')
FIELDS = ('pa.purchase_approval_id,pa.purchase_requisition_id,pa.approval_sequence,pr.title,e.employee_name,'
    'b.branch_name,pr.requisition_status,pa.approval_status,pr.submitted_at,pa.decided_at,pa.approval_comment,'
    '(SELECT COUNT(*) FROM purchase_requisition_items i WHERE i.purchase_requisition_id=pr.purchase_requisition_id) AS item_count,'
    '(SELECT COALESCE(SUM(i.requested_quantity),0) FROM purchase_requisition_items i '
    'WHERE i.purchase_requisition_id=pr.purchase_requisition_id) AS total_requested_quantity')


def _scope(employee: dict, stage: ApprovalStage):
    permission, status, sequence = STAGES[stage]
    if permission not in employee['permissions']:
        raise AuthError('FORBIDDEN')
    base = "r.role_code=%s AND r.is_active=1 AND pa.approval_sequence=%s AND pr.requisition_status<>'DRAFT'"
    pending = "(pa.approval_status='PENDING' AND pr.requisition_status=%s"
    if stage == 'DIRECTOR':
        pending += (" AND EXISTS (SELECT 1 FROM purchase_approvals prior JOIN roles prior_role "
            "ON prior_role.role_id=prior.required_role_id WHERE prior.purchase_requisition_id=pr.purchase_requisition_id "
            "AND prior_role.role_code='TEAM_LEAD' AND prior.approval_sequence<pa.approval_sequence "
            "AND prior.approval_status='APPROVED')")
    pending += ')'
    history = "(pa.approval_status IN ('APPROVED','REJECTED') AND pa.approver_employee_id=%s)"
    return base, pending, history, [stage, sequence], status


def list_purchase_approvals(db: Connection, *, employee: dict, stage: ApprovalStage,
    view: Literal['pending','history'], page: int, page_size: int,order: Literal['asc','desc']='desc') -> ApprovalListResponse:
    direction={'asc':'ASC','desc':'DESC'}[order]
    base, pending, history, params, status = _scope(employee, stage)
    where = ' WHERE '+base+' AND '+(pending if view=='pending' else history)
    params.append(status if view=='pending' else employee['employee_id'])
    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT COUNT(*) AS total_count'+TABLES+where, tuple(params))
        count = cursor.fetchone()['total_count']
        sort = 'pr.submitted_at' if view=='pending' else 'pa.decided_at'
        cursor.execute('SELECT '+FIELDS+TABLES+where+f' ORDER BY {sort} {direction},pa.purchase_approval_id {direction} LIMIT %s OFFSET %s',
            tuple(params)+(page_size,(page-1)*page_size))
        return ApprovalListResponse(data=cursor.fetchall(),
            pagination=ApprovalPagination(page=page,page_size=page_size,total_count=count))


@router.get('/pending', response_model=ApprovalListResponse, summary='직책별 결재 대기 조회')
def get_pending_approvals(stage: ApprovalStage,
    employee: Annotated[dict,Depends(current_employee)], db: Annotated[Connection,Depends(get_db)],
    page: Annotated[int,Query(ge=1)]=1, page_size: Annotated[int,Query(ge=1,le=100)]=20,order: Literal['asc','desc']='desc'):
    return list_purchase_approvals(db,employee=employee,stage=stage,view='pending',page=page,page_size=page_size,order=order)


@router.get('/history', response_model=ApprovalListResponse, summary='본인 결재 처리 이력 조회')
def get_approval_history(stage: ApprovalStage,
    employee: Annotated[dict,Depends(current_employee)], db: Annotated[Connection,Depends(get_db)],
    page: Annotated[int,Query(ge=1)]=1, page_size: Annotated[int,Query(ge=1,le=100)]=20,order: Literal['asc','desc']='desc'):
    return list_purchase_approvals(db,employee=employee,stage=stage,view='history',page=page,page_size=page_size,order=order)


@router.get('/{purchase_approval_id}', response_model=ApprovalDetailResponse, summary='결재 대상 품의 상세 조회')
def get_approval_detail(purchase_approval_id: Annotated[int,Path(gt=0)], stage: ApprovalStage,
    employee: Annotated[dict,Depends(current_employee)], db: Annotated[Connection,Depends(get_db)]):
    base,pending,history,params,status = _scope(employee,stage)
    with db.cursor(DictCursor) as cursor:
        cursor.execute('SELECT '+FIELDS+TABLES+' WHERE '+base+' AND ('+pending+' OR '+history+') AND pa.purchase_approval_id=%s',
            tuple(params)+(status,employee['employee_id'],purchase_approval_id))
        row = cursor.fetchone()
        if row is None:
            _error(404,'NOT_FOUND','조회 가능한 결재 품의를 찾을 수 없습니다.')
        detail = _read_requisition_detail(cursor,row['purchase_requisition_id'],employee).data
        cursor.execute('SELECT pa.approval_sequence,r.role_code,r.role_name,pa.approval_status,'
            'e.employee_name AS approver_name,pa.approval_comment,pa.decided_at '
            'FROM purchase_approvals pa JOIN roles r ON r.role_id=pa.required_role_id '
            'LEFT JOIN employees e ON e.employee_id=pa.approver_employee_id '
            'WHERE pa.purchase_requisition_id=%s ORDER BY pa.approval_sequence', (row['purchase_requisition_id'],))
        return ApprovalDetailResponse(data=ApprovalDetail(approval=row,requisition=detail,steps=cursor.fetchall()))

# 1. 요청·응답 모델: 결재 의견·반려 사유와 결재 결과를 정의한다.
# 2. 업무 함수: 결재자 권한·순서·현재 상태·중복 처리를 확인한다.
#    이사 최종 승인 시 발주 기록과 ORDERED 상태를 같은 트랜잭션으로 저장한다.
# 3. API 함수: 결재 대기 목록·승인·반려 요청을 연결한다.
#    예: GET /api/v1/purchase-approvals/pending
#        POST /api/v1/purchase-approvals/{purchase_approval_id}/approve
#        POST /api/v1/purchase-approvals/{purchase_approval_id}/reject
