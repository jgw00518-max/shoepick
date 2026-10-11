/// 처리 기록을 읽으며 원본 상태와 서버 시각을 그대로 유지한다.
class OrderAfterSales {
  OrderAfterSales.fromJson(Map<String, dynamic> json)
    : returns = _records(json['return_requests']),
      refunds = _records(json['refunds']);

  final List<Map<String, dynamic>> returns;
  final List<Map<String, dynamic>> refunds;
  bool get isEmpty => returns.isEmpty && refunds.isEmpty;

  static List<Map<String, dynamic>> _records(dynamic value) => (value as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();

  static String returnLabel(dynamic status) =>
      const {
        'REQUESTED': '반품 접수',
        'APPROVED': '반품 최종 승인 · 환불 대기',
        'REJECTED': '거절',
        'COLLECTING': '회수 중',
        'INSPECTING': '검수 중',
        'RETURNED': '반환 완료',
        'COMPLETED': '반품 처리 완료',
        'CANCELED': '반품 취소',
      }[status] ??
      '확인되지 않은 상태';

  static String refundLabel(dynamic status) =>
      const {
        'REQUESTED': '환불 요청',
        'PROCESSING': '환불 진행 중',
        'SUCCEEDED': '환불 완료',
        'FAILED': '환불 실패',
        'CANCELED': '환불 취소',
      }[status] ??
      '확인되지 않은 상태';
}
