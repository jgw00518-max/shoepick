import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

/// 인증 요청과 토큰 갱신을 한곳에서 처리한다. 주소는 실행 설정으로 전달한다.
class AuthApi {
  AuthApi({FirebaseAuth? auth, String? baseUrl})
    : auth = auth ?? FirebaseAuth.instance,
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://10.0.2.2:8000',
          );

  final FirebaseAuth auth;
  final String baseUrl;

  Future<Map<String, dynamic>> get(String path) async {
    final response = await getResponse(path);
    return response['data'] as Map<String, dynamic>;
  }

  /// ??? ??? ??? ?? ?? ???? ????.
  Future<Map<String, dynamic>> getResponse(String path) async {
    return _request('GET', path);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    return (await _request('POST', path, body: body))['data']
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async =>
      (await _request('PATCH', path, body: body))['data']
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (baseUrl.isEmpty) throw StateError('API_BASE_URL을 설정해주세요.');
    final user = auth.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final token = await user.getIdToken(attempt == 1);
        final request = await client.openUrl(
          method,
          Uri.parse('${baseUrl.replaceFirst(RegExp(r"/$"), "")}$path'),
        );
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        final response = await request.close().timeout(
          const Duration(seconds: 15),
        );
        if (response.statusCode == 401 && attempt == 0) {
          await response.drain<void>();
          continue;
        }
        final responseBody = jsonDecode(
          await utf8.decoder.bind(response).join(),
        );
        if (response.statusCode == 401) {
          await auth.signOut();
          throw StateError('로그인이 만료되었습니다. 다시 로그인해주세요.');
        }
        if (response.statusCode != 200 && response.statusCode != 201) {
          final code = responseBody['error']?['code'];
          throw AuthApiException(
            code == 'FORBIDDEN'
                ? '등록된 활성 직원 계정인지 확인해주세요. (직원 권한 오류)'
                : response.statusCode == 503
                ? '출고 조회 연동을 준비 중입니다.'
                : method != 'GET' &&
                      {400, 404, 409}.contains(response.statusCode)
                ? (responseBody['error']?['message'] as String? ??
                      '구매 품의 입력값을 확인해주세요.')
                : '서버 요청을 처리하지 못했습니다. (HTTP ${response.statusCode})',
          );
        }
        return responseBody as Map<String, dynamic>;
      }
      throw StateError('로그인이 필요합니다.');
    } on SocketException {
      throw AuthApiException(
        'API 서버에 연결할 수 없습니다. $baseUrl 주소와 FastAPI 실행 상태를 확인해주세요.',
      );
    } on TimeoutException {
      throw const AuthApiException('API 서버 응답 시간이 초과되었습니다. 서버 실행 상태를 확인해주세요.');
    } on FormatException {
      throw const AuthApiException('API 서버 응답 형식이 올바르지 않습니다. 서버 주소를 확인해주세요.');
    } finally {
      client.close(force: true);
    }
  }
}

class AuthApiException implements Exception {
  const AuthApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
