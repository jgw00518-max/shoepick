class ManufacturerOrderPage {
  const ManufacturerOrderPage(this.rows, this.totalCount);
  final List<Map<String, dynamic>> rows;
  final int totalCount;
  factory ManufacturerOrderPage.fromJson(Map<String, dynamic> json) =>
      ManufacturerOrderPage(
        (json['data'] as List<dynamic>).cast<Map<String, dynamic>>(),
        json['pagination']['total_count'] as int,
      );
}
