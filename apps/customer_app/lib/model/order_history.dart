/// 기존 주문 생성 모델을 변경하지 않고 C 조회 응답만 읽는다.
class OrderHistory {
  OrderHistory(this.data);
  final Map<String, dynamic> data;
  int get id => data['order_id'] as int;
  String get number => data['order_number'] as String;
  String get status => data['order_status'] as String;
  String? get purchaseConfirmedAt => data['purchase_confirmed_at'] as String?;
  bool get isPurchaseConfirmed =>
      status == 'COMPLETED' && purchaseConfirmedAt != null;
  bool get canConfirmPurchase =>
      status == 'COMPLETED' && purchaseConfirmedAt == null;
  int get paidTotal => data['paid_total'] as int;
  String get branch => data['branch_name'] as String? ?? '수령 대리점 정보 없음';
  String get statusLabel => switch (status) {
    'PENDING_PAYMENT' => '결제 대기',
    'PAID' => '결제 완료',
    'PREPARING' => '준비 중',
    'SHIPPING' => '배송 중',
    'READY_FOR_PICKUP' => '수령 가능',
    'COMPLETED' => isPurchaseConfirmed ? '구매확정' : '수령 완료',
    'CANCELED' => '취소 완료',
    'REFUNDED' => '환불 완료',
    _ => '상태 확인 필요 ($status)',
  };
  List<Map<String, dynamic>> get fulfillments =>
      (data['fulfillments'] as List? ?? []).cast<Map<String, dynamic>>();

  /// DB에 존재하는 배송 상태만 표시하며 업무 정책이나 원본 값을 바꾸지 않는다.
  static String fulfillmentLabel(String? status) => switch (status) {
    'PREPARING' => '출고 준비 중',
    'IN_TRANSIT' => '배송 중',
    'ARRIVED' => '도착',
    'INSPECTING' => '검수 중',
    'READY_FOR_PICKUP' => '수령 가능',
    'RECALLING' => '회수 중',
    'RETURNED_TO_HQ' => '본사 회수 완료',
    'COMPLETED' => '배송·수령 처리 완료',
    'CANCELED' => '취소',
    _ => '상태 확인 필요 (${status ?? '정보 없음'})',
  };
  List<Map<String, dynamic>> get items =>
      (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
  factory OrderHistory.fromJson(Map<String, dynamic> json) =>
      OrderHistory(json);
}
