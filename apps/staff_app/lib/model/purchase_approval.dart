const approvalStatusLabels = {
  'PENDING': '대기',
  'APPROVED': '승인',
  'REJECTED': '반려',
  'WAIVED': '미진행',
};

class PurchaseApprovalPage {
  const PurchaseApprovalPage({required this.rows, required this.totalCount});
  final List<Map<String, dynamic>> rows;
  final int totalCount;
  factory PurchaseApprovalPage.fromJson(Map<String, dynamic> json) =>
      PurchaseApprovalPage(
        rows: (json['data'] as List<dynamic>).cast<Map<String, dynamic>>(),
        totalCount:
            (json['pagination'] as Map<String, dynamic>)['total_count'] as int,
      );
}
