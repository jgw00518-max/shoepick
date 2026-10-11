import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/model/inquiry_input.dart';

void main() {
  test('제목은 공백을 제외하고 DB의 150자 한계를 검사한다', () {
    expect(validateInquiryTitle('   '), isNotNull);
    expect(validateInquiryTitle('가' * 150), isNull);
    expect(validateInquiryTitle('가' * 151), isNotNull);
    expect(validateInquiryTitle('🙂' * 150), isNull);
  });
  test('문의 내용은 공백만 입력할 수 없다', () {
    expect(validateInquiryContent(null), isNotNull);
    expect(validateInquiryContent(' \n '), isNotNull);
    expect(validateInquiryContent('내용'), isNull);
  });
}
