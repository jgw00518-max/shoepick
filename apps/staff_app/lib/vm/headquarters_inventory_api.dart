import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shoepick_staff_app/model/headquarters_inventory.dart';
import 'package:shoepick_staff_app/model/staff_session.dart';

class HeadquartersInventoryApi {
  HeadquartersInventoryApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            // Android 에뮬레이터에서 개발 PC의 로컬 서버에 연결한다.
            defaultValue: 'http://10.0.2.2:8000',
          );

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<HeadquartersInventoryPage> fetch({
    int page = 1,
    int pageSize = 20,
    String keyword = '',
    String sort = 'updated_at',
  }) async {
    final base = _baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1/inventory/headquarters').replace(
      queryParameters: {
        'page': '$page',
        'page_size': '$pageSize',
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
        'sort': sort,
        'order': sort == 'updated_at' ? 'desc' : 'asc',
      },
    );
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        String? message;
        try {
          final body =
              jsonDecode(utf8.decode(response.bodyBytes))
                  as Map<String, dynamic>;
          message =
              (body['error'] as Map<String, dynamic>?)?['message'] as String?;
        } on FormatException {
          // JSON이 아닌 프록시 오류 등은 공통 안내로 표시한다.
        } on TypeError {
          // 공통 응답 형식이 아니면 서버 내부 내용을 표시하지 않는다.
        }
        throw StaffAuthException(message ?? '본사 재고를 조회하지 못했습니다. 다시 시도해주세요.');
      }
      return HeadquartersInventoryPage.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    } on TimeoutException {
      throw const StaffAuthException('서버 응답이 지연되고 있습니다. 다시 시도해주세요.');
    } on http.ClientException {
      throw const StaffAuthException(
        '재고 서버에 연결할 수 없습니다. 서버 실행과 연결 주소를 확인해주세요.',
      );
    } on FormatException {
      throw const StaffAuthException('재고 조회 응답 형식이 올바르지 않습니다.');
    } on TypeError {
      throw const StaffAuthException('재고 조회 응답 형식이 올바르지 않습니다.');
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
