class StaffPayment {
  const StaffPayment({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    required this.orderStatus,
    required this.method,
    required this.status,
    required this.amount,
    required this.paidAt,
    required this.branchName,
  });

  final int id;
  final int orderId;
  final String orderNumber;
  final String orderStatus;
  final String method;
  final String status;
  final int amount;
  final String? paidAt;
  final String? branchName;

  factory StaffPayment.fromJson(Map<String, dynamic> json) {
    return StaffPayment(
      id: (json['payment_id'] as num).toInt(),
      orderId: (json['order_id'] as num).toInt(),
      orderNumber: json['order_number'] as String,
      orderStatus: json['order_status'] as String,
      method: json['payment_method'] as String,
      status: json['payment_status'] as String,
      amount: (json['payment_amount'] as num).toInt(),
      paidAt: json['paid_at'] as String?,
      branchName: json['branch_name'] as String?,
    );
  }
}