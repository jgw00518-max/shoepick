class StaffOrder {
  const StaffOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.customerName,
    required this.branchName,
    required this.products,
    this.fulfillmentId,
    this.fulfillmentStatus,
    this.orderedAt,
  });

  final int id;
  final String number;
  final String status;
  final String customerName;
  final String branchName;
  final List<String> products;
  final int? fulfillmentId;
  final String? fulfillmentStatus;
  final DateTime? orderedAt;

  String get productSummary =>
      products.isEmpty ? '상품 정보 없음' : products.join(', ');

  factory StaffOrder.fromJson(Map<String, dynamic> json) => StaffOrder(
    id: json['orderId'] as int,
    number: json['orderNumber'] as String,
    status: json['orderStatus'] as String,
    customerName: json['customerName'] as String,
    branchName: json['branchName'] as String,
    products: (json['products'] as List<dynamic>).cast<String>(),
    fulfillmentId: json['fulfillmentId'] as int?,
    fulfillmentStatus: json['fulfillmentStatus'] as String?,
    orderedAt: json['orderedAt'] == null
        ? null
        : DateTime.tryParse(json['orderedAt'] as String),
  );
}
