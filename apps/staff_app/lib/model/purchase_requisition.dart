const requisitionStatusLabels = {
  'DRAFT': '초안',
  'SUBMITTED': '상신',
  'PENDING_TEAM_LEAD': '팀장 결재 대기',
  'PENDING_DIRECTOR': '이사 결재 대기',
  'APPROVED': '승인',
  'REJECTED': '반려',
  'ORDERED': '발주 완료',
  'CANCELED': '취소',
};

class PurchaseRequisitionPage {
  const PurchaseRequisitionPage({
    required this.rows,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });
  final List<Map<String, dynamic>> rows;
  final int page;
  final int pageSize;
  final int totalCount;
  factory PurchaseRequisitionPage.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>;
    return PurchaseRequisitionPage(
      rows: [
        for (final raw in json['data'] as List<dynamic>)
          {
            ...raw as Map<String, dynamic>,
            'id': raw['purchase_requisition_id'],
            'status': raw['requisition_status'],
          },
      ],
      page: pagination['page'] as int,
      pageSize: pagination['page_size'] as int,
      totalCount: pagination['total_count'] as int,
    );
  }
}
