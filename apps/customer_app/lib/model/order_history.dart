/// 기존 주문 생성 모델을 변경하지 않고 C 조회 응답만 읽는다.
class OrderHistory {
  OrderHistory(this.data);
  final Map<String, dynamic> data;
  int get id => data['order_id'] as int;
  String get number => data['order_number'] as String;
  String get status => data['order_status'] as String;
  int get paidTotal => data['paid_total'] as int;
  String get branch => data['branch_name'] as String? ?? '배송 주문';
  List<Map<String, dynamic>> get items =>
      (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
  factory OrderHistory.fromJson(Map<String, dynamic> json) =>
      OrderHistory(json);
}
