const branchHoldingStatusLabels = {
  'AWAITING_ARRIVAL': '입고 대기',
  'INSPECTING': '검수 중',
  'READY_FOR_PICKUP': '고객 수령 대기',
  'PICKED_UP': '고객 수령 완료',
  'RECALLING': '본사 회수 진행',
  'RETURNED_TO_HQ': '본사 반송 완료',
  'DAMAGED': '손상 상품',
  'CANCELED': '취소',
};

class BranchInventoryPage {
  const BranchInventoryPage({
    required this.rows,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });

  final List<Map<String, dynamic>> rows;
  final int page;
  final int pageSize;
  final int totalCount;

  factory BranchInventoryPage.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>;
    return BranchInventoryPage(
      rows: (json['data'] as List<dynamic>).cast<Map<String, dynamic>>(),
      page: pagination['page'] as int,
      pageSize: pagination['page_size'] as int,
      totalCount: pagination['total_count'] as int,
    );
  }
}
