import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../model/staff_session.dart';

/// 실제 재고 요청에 ID 토큰을 포함하고 401이면 한 번만 갱신한다.
class FirebaseHttpClient extends http.BaseClient {
  FirebaseHttpClient({
    http.Client? client,
    Future<String?> Function(bool refresh)? tokenProvider,
    Future<void> Function()? signOut,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider ?? _firebaseToken,
       _signOut = signOut ?? (() => FirebaseAuth.instance.signOut());

  final http.Client _client;
  final Future<String?> Function(bool refresh) _tokenProvider;
  final Future<void> Function() _signOut;

  Future<String?>? _refreshing;

  Future<String?> _token(bool refresh) async {
    if (!refresh) return _tokenProvider(false);
    final pending = _refreshing ??= _tokenProvider(true);
    try {
      return await pending;
    } finally {
      if (identical(_refreshing, pending)) _refreshing = null;
    }
  }

  static Future<String?> _firebaseToken(bool refresh) async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken(refresh);
    } on FirebaseException {
      throw const StaffAuthException('로그인 상태를 확인하지 못했습니다. 다시 로그인해주세요.');
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await _token(attempt == 1);
      if (token == null || token.isEmpty) {
        throw const StaffAuthException('로그인이 필요합니다.');
      }
      final authenticated = http.Request(request.method, request.url)
        ..followRedirects = false
        ..headers.addAll(request.headers)
        ..bodyBytes = bytes;
      authenticated.headers['Authorization'] = 'Bearer $token';
      final response = await _client.send(authenticated);
      if (response.statusCode == 401 && attempt == 0) {
        await response.stream.drain<void>();
        continue;
      }
      if (response.statusCode == 401) await _signOut();
      return response;
    }
    throw const StaffAuthException('로그인이 만료되었습니다. 다시 로그인해주세요.');
  }

  @override
  void close() => _client.close();
}
