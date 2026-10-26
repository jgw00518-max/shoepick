"""현재 구현된 직원 API에 적용하는 초기 권한표. 미구현 업무는 포함하지 않는다."""

HQ_INVENTORY_READ = 'inventory.headquarters.read'
BRANCH_INVENTORY_READ = 'inventory.branches.read'
DISPATCH_READ = 'orders.dispatch.read'

PERMISSIONS = {
    HQ_INVENTORY_READ: '본사 재고 조회',
    BRANCH_INVENTORY_READ: '소속 대리점 보관 현황 조회',
    DISPATCH_READ: '출고 대상 조회',
}

ROLE_PERMISSIONS = {
    'BRANCH_STAFF': (BRANCH_INVENTORY_READ, DISPATCH_READ),
    'BRANCH_MANAGER': (BRANCH_INVENTORY_READ, DISPATCH_READ),
    'HQ_STAFF': (HQ_INVENTORY_READ, DISPATCH_READ),
    'TEAM_LEAD': (HQ_INVENTORY_READ,),
    'DIRECTOR': (HQ_INVENTORY_READ,),
    'EXECUTIVE': (HQ_INVENTORY_READ,),
}


def seed_policy(cursor):
    """기존 배정은 보존하며 호출자의 트랜잭션에 초기 권한표를 추가한다."""
    for code, name in PERMISSIONS.items():
        cursor.execute('INSERT INTO permissions(permission_code,permission_name) '
                       'SELECT %s,%s WHERE NOT EXISTS '
                       '(SELECT 1 FROM permissions WHERE permission_code=%s)',
                       (code, name, code))
    for role, permissions in ROLE_PERMISSIONS.items():
        for permission in permissions:
            cursor.execute('INSERT INTO role_permissions(role_id,permission_id) '
                           'SELECT r.role_id,p.permission_id FROM roles r '
                           'JOIN permissions p ON p.permission_code=%s '
                           'WHERE r.role_code=%s AND r.is_active=1 AND NOT EXISTS '
                           '(SELECT 1 FROM role_permissions rp '
                           'WHERE rp.role_id=r.role_id AND rp.permission_id=p.permission_id)',
                           (permission, role))
