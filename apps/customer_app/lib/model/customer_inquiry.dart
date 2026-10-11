/// 기존 문의 필드만 읽으며 날짜 문자열의 시간대를 변환하지 않는다.
class CustomerInquiry {
  CustomerInquiry(this.data);
  final Map<String, dynamic> data;
  int get id => data['inquiry_id'] as int;
  String get title => data['title'] as String;
  String get status => switch (data['inquiry_status']) {
    'OPEN' => '답변 대기',
    'ANSWERED' => '답변 완료',
    'CLOSED' => '종료',
    _ => '상태 확인 필요 (${data['inquiry_status']})',
  };
}
