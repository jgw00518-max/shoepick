enum StaffRole {
  branchStaff('대리점 직원', '입고·픽업 결제 코드 확인·반품 현황', true),
  branchManager('대리점장', '지점 재고와 입고·픽업 업무', true),
  hqStaff('본사 사원', '주문·고객 문의·배송·구매 품의', false),
  teamLeader('본사 팀장', '구매 품의 결재와 재고 조회', false),
  director('본사 이사', '구매 품의 최종 결재', false),
  executive('본사 임원', '판매·재고·발주 분석', false);

  const StaffRole(this.label, this.description, this.isBranch);

  static StaffRole? fromCode(String code) => switch (code) {
    'BRANCH_STAFF' => StaffRole.branchStaff,
    'BRANCH_MANAGER' => StaffRole.branchManager,
    'HQ_STAFF' => StaffRole.hqStaff,
    'TEAM_LEAD' => StaffRole.teamLeader,
    'DIRECTOR' => StaffRole.director,
    'EXECUTIVE' => StaffRole.executive,
    _ => null,
  };
  final String label;
  final String description;
  final bool isBranch;
}
