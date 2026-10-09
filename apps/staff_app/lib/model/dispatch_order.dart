/// A의 결제 완료 주문을 C 조회 화면에 표시하는 읽기 모델이다.
class DispatchOrder {
  DispatchOrder.fromJson(Map<String, dynamic> json)
    : orderId = json['order_id'] as int,
      orderNumber = json['order_number'] as String,
      branchName = json['branch_name'] as String? ?? '대리점 미지정',
      paidTotal = json['paid_total'] as int;

  final int orderId;
  final String orderNumber;
  final String branchName;
  final int paidTotal;
}
