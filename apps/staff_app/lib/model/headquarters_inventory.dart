class HeadquartersInventoryPage {
  const HeadquartersInventoryPage({
    required this.rows,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });

  final List<Map<String, dynamic>> rows;
  final int page;
  final int pageSize;
  final int totalCount;

  factory HeadquartersInventoryPage.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>;
    return HeadquartersInventoryPage(
      rows: [
        for (final raw in json['data'] as List<dynamic>)
          {
            ...raw as Map<String, dynamic>,
            // 기존 재고 표가 사용하는 표시 필드에 실물 수량을 연결한다.
            'quantity': raw['on_hand_quantity'],
          },
      ],
      page: pagination['page'] as int,
      pageSize: pagination['page_size'] as int,
      totalCount: pagination['total_count'] as int,
    );
  }
}
