/// C 반품 조회 응답만 읽고 기존 업무 상태값을 유지한다.
class StaffReturn {
  StaffReturn(this.data);
  final Map<String, dynamic> data;
  int get id => data['return_request_id'] as int;
  String get number => data['order_number'] as String;
  String get branch => data['branch_name'] as String? ?? '대리점 정보 없음';
  String get statusLabel =>
      const {
        'REQUESTED': '반품 접수',
        'APPROVED': '반품 최종 승인 · 환불 대기',
        'REJECTED': '거절',
        'COLLECTING': '회수 중',
        'INSPECTING': '검수 중',
        'RETURNED': '반환 완료',
        'COMPLETED': '반품 처리 완료',
        'CANCELED': '반품 취소',
      }[data['request_status']] ??
      '확인되지 않은 상태';
}
