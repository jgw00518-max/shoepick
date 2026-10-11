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

  /// 목록 API도 같은 인증·재시도 규칙을 사용하도록 전체 응답을 제공한다.
  Future<Map<String, dynamic>> getResponse(String path) async {
    return _request(path);
  }

  /// 생성도 기존 인증 갱신 규칙을 사용하며 일반 실패는 자동 재전송하지 않는다.
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data) =>
      _request(path, data: data);

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? data,
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
          data == null ? 'GET' : 'POST',
          Uri.parse('${baseUrl.replaceFirst(RegExp(r"/$"), "")}$path'),
        );
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        if (data != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(data));
        }
        final response = await request.close().timeout(
          const Duration(seconds: 15),
        );
        if (response.statusCode == 401 && attempt == 0) {
          await response.drain<void>();
          continue;
        }
        final body = jsonDecode(await utf8.decoder.bind(response).join());
        if (response.statusCode == 401) {
          await auth.signOut();
          throw StateError('로그인이 만료되었습니다. 다시 로그인해주세요.');
        }
        if (response.statusCode != 200 && response.statusCode != 201) {
          final code = body['error']?['code'];
          throw StateError(
            code == 'FORBIDDEN' ? '접근 권한이 없습니다.' : '서버 연결을 확인해주세요.',
          );
        }
        return body as Map<String, dynamic>;
      }
      throw StateError('로그인이 필요합니다.');
    } finally {
      client.close(force: true);
    }
  }
}
