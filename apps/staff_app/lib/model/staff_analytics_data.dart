import 'package:shupick_staff_mockup/model/staff_session.dart';

/// SQL aggregate values may arrive as JSON numbers or decimal strings.
Map<String, dynamic> normalizeStaffAnalytics(Map<String, dynamic> source) {
  int integer(dynamic value) {
    if (value == null) return 0;
    final number = value is num ? value : num.tryParse(value.toString());
    if (number == null || !number.isFinite || number.remainder(1) != 0) {
      throw const StaffAuthException('판매 분석의 숫자 데이터 형식이 올바르지 않습니다.');
    }
    return number.toInt();
  }

  List<Map<String, dynamic>> rows(String key, String numericField) => [
    for (final raw in source[key] as List<dynamic>? ?? [])
      {
        ...raw as Map<String, dynamic>,
        numericField: integer(raw[numericField]),
      },
  ];

  return {
    ...source,
    'quantity': integer(source['quantity']),
    'revenue': integer(source['revenue']),
    'orderCount': integer(source['orderCount']),
    'byDay': rows('byDay', 'quantity'),
    'byProduct': rows('byProduct', 'quantity'),
    'products': rows('products', 'id'),
    'branches': rows('branches', 'id'),
  };
}
