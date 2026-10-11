/// DB 제목 길이와 공백 입력을 확인한다. 미확정 문의 유형은 여기서 정의하지 않는다.
String? validateInquiryTitle(String? value) {
  final title = value?.trim() ?? '';
  if (title.isEmpty) return '문의 제목을 입력해주세요.';
  if (title.runes.length > 150) return '문의 제목은 150자 이하로 입력해주세요.';
  return null;
}

String? validateInquiryContent(String? value) =>
    (value?.trim().isEmpty ?? true) ? '문의 내용을 입력해주세요.' : null;
