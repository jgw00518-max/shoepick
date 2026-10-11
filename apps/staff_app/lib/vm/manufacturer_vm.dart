import 'package:get/get.dart';

import '../model/manufacturer.dart';
import 'auth_api.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;

class ManufacturerVm extends GetxController {
  late final AuthApi api = AuthApi();
  List<Manufacturer> manufacturers = [];
  bool loading = true;
  String? error;
  int _request = 0;

  @override
  void onInit() {
    super.onInit();
    fetchManufacturers();
  }

  Future<void> fetchManufacturers() async {
    final request = ++_request;

    loading = true;
    error = null;
    update();

    try {
      // AuthApi가 현재 직원의 Firebase 토큰을 자동 전달한다.
      final response = await api.getResponse(
        '/api/v1/staff/manufacturers',
      );

      final rows = response['data'] as List<dynamic>;

      final loaded = rows
          .map(
            (row) => Manufacturer.fromJson(
              row as Map<String, dynamic>,
            ),
          )
          .toList();

      if (isClosed || request != _request) return;

      manufacturers = loaded;
    } on StateError catch (exception) {
      if (isClosed || request != _request) return;

      error = exception.message.toString();
    } catch (_) {
      if (isClosed || request != _request) return;

      error = '제조사 목록을 불러오지 못했습니다. 서버 연결을 확인해주세요.';
    } finally {
      if (!isClosed && request == _request) {
        loading = false;
        update();
      }
    }
  }

    Future<void> saveManufacturer({
    int? id,
    required String name,
    required String contactName,
    required String phone,
    required String email,
  }) async {
    final user = api.auth.currentUser;

    if (user == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final baseUrl = api.baseUrl.replaceFirst(RegExp(r'/$'), '');
    final path = id == null
        ? '/api/v1/staff/manufacturers'
        : '/api/v1/staff/manufacturers/$id';

    final body = jsonEncode({
      'manufacturer_name': name.trim(),
      'contact_name': contactName.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
    });

    final client = http.Client();

    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final token = await user.getIdToken(attempt == 1);

        if (token == null || token.isEmpty) {
          throw StateError('로그인 정보를 확인하지 못했습니다.');
        }

        final headers = {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
        };

        final response = await (
          id == null
              ? client.post(
                  Uri.parse('$baseUrl$path'),
                  headers: headers,
                  body: body,
                )
              : client.put(
                  Uri.parse('$baseUrl$path'),
                  headers: headers,
                  body: body,
                )
        ).timeout(const Duration(seconds: 15));

        // 인증 실패 때만 토큰을 갱신하여 한 번 재요청한다.
        if (response.statusCode == 401 && attempt == 0) {
          continue;
        }

        if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          return;
        }

        if (response.statusCode == 401) {
          throw StateError('로그인이 만료되었습니다. 다시 로그인해주세요.');
        }

        if (response.statusCode == 403) {
          throw StateError('본사 사원만 제조사를 변경할 수 있습니다.');
        }

        String message = '저장에 실패했습니다. HTTP ${response.statusCode}';

        try {
          final decoded = jsonDecode(
            utf8.decode(response.bodyBytes),
          );

          if (decoded is Map) {
            final detail = decoded['error'] ?? decoded['detail'];
            if (detail is Map && detail['message'] is String) {
              message = detail['message'] as String;
            }
          }
        } catch (_) {
          // JSON이 아닌 오류 응답은 공통 문구를 사용한다.
        }

        throw StateError(message);
      }

      throw StateError('로그인 정보를 확인해주세요.');
    } finally {
      client.close();
    }
  }
}