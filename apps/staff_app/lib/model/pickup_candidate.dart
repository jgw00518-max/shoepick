/// 기존 배송·수령 조회 응답만 표시하며 인증 코드나 처리 성공을 만들지 않는다.
class PickupCandidate {
  PickupCandidate(this.data);
  final Map<String, dynamic> data;
  int get id => (data['fulfillment_id'] ?? data['pickup_id']) as int;
  String get number => data['order_number'] as String;
  String get branch => data['branch_name'] as String? ?? '대리점 정보 없음';
  String get time =>
      (data['arrived_at'] ?? data['shipped_at'] ?? data['ready_at'] ?? '')
          .toString();
}
