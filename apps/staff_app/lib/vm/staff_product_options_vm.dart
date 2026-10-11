import 'package:get/get.dart';

import '../model/staff_product_option.dart';
import 'auth_api.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;

class StaffProductOptionsVm extends GetxController {
  StaffProductOptionsVm({required this.productId});

  final int productId;
  final AuthApi api = AuthApi();

  List<StaffProductOption> options = [];
  bool loading = true;
  String? error;
  int _request = 0;

  @override
  void onInit() {
    super.onInit();
    fetchOptions();
  }

  Future<void> fetchOptions() async {
    final request = ++_request;

    loading = true;
    error = null;
    update();

    try {
      final response = await api.getResponse(
        '/api/v1/staff/products/$productId/options',
      );

      final loaded = (response['data'] as List<dynamic>)
          .map(
            (row) => StaffProductOption.fromJson(
              row as Map<String, dynamic>,
            ),
          )
          .toList();

      if (isClosed || request != _request) return;
      options = loaded;
    } on StateError catch (exception) {
      if (isClosed || request != _request) return;
      error = exception.message.toString();
    } catch (_) {
      if (isClosed || request != _request) return;
      error = '옵션 목록을 불러오지 못했습니다. 서버 연결을 확인해주세요.';
    } finally {
      if (!isClosed && request == _request) {
        loading = false;
        update();
      }
    }
  }

     Future<void> saveOption(
    Map<String, dynamic> values, {
    int? optionId,
  }) async {
    final user = api.auth.currentUser;
    if (user == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final baseUrl = api.baseUrl.replaceFirst(RegExp(r'/$'), '');
    final path = optionId == null
        ? '/api/v1/staff/products/$productId/options'
        : '/api/v1/staff/products/$productId/options/$optionId';
    final client = http.Client();

    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final token = await user.getIdToken(attempt == 1);
        if (token == null || token.isEmpty) {
          throw StateError('로그인 정보를 확인하지 못했습니다.');
        }

        final uri = Uri.parse('$baseUrl$path');
        final headers = {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
        };
        final body = jsonEncode(values);

        final response = await (
          optionId == null
              ? client.post(uri, headers: headers, body: body)
              : client.put(uri, headers: headers, body: body)
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 401 && attempt == 0) {
          continue;
        }

        if (response.statusCode == 200 ||
            response.statusCode == 201) {
          return;
        }

        if (response.statusCode == 401) {
          throw StateError('로그인이 만료되었습니다. 다시 로그인해주세요.');
        }
        if (response.statusCode == 403) {
          throw StateError('본사 사원만 옵션을 변경할 수 있습니다.');
        }

        var message = '옵션 저장에 실패했습니다.';
        try {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is Map) {
            final error = decoded['error'] ?? decoded['detail'];
            if (error is Map && error['message'] is String) {
              message = error['message'] as String;
            }
          }
        } catch (_) {
          // JSON이 아닌 응답은 기본 오류 문구를 사용한다.
        }

        throw StateError(message);
      }
    } finally {
      client.close();
    }
  }
}