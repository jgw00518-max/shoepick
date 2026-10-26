import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoepick_staff_app/model/staff_session.dart';
import 'package:shoepick_staff_app/vm/firebase_http_client.dart';

void main() {
  test('401이면 새 토큰으로 한 번만 재요청한다', () async {
    final refreshes = <bool>[];
    final headers = <String?>[];
    final client = FirebaseHttpClient(
      client: MockClient((request) async {
        headers.add(request.headers['Authorization']);
        return http.Response('{}', headers.length == 1 ? 401 : 200);
      }),
      tokenProvider: (refresh) async {
        refreshes.add(refresh);
        return refresh ? 'new-token' : 'old-token';
      },
      signOut: () async => fail('정상 갱신 후 로그아웃하면 안 됩니다.'),
    );
    addTearDown(client.close);
    expect(
      (await client.get(Uri.parse('http://localhost/inventory'))).statusCode,
      200,
    );
    expect(refreshes, [false, true]);
    expect(headers, ['Bearer old-token', 'Bearer new-token']);
  });

  test('연속 401은 두 번만 요청하고 로그아웃한다', () async {
    var requests = 0;
    var signedOut = false;
    final client = FirebaseHttpClient(
      client: MockClient((request) async {
        requests++;
        return http.Response('{}', 401);
      }),
      tokenProvider: (_) async => 'token',
      signOut: () async {
        signedOut = true;
      },
    );
    addTearDown(client.close);
    expect(
      (await client.get(Uri.parse('http://localhost/inventory'))).statusCode,
      401,
    );
    expect(requests, 2);
    expect(signedOut, isTrue);
  });

  test('토큰이 없으면 서버 요청을 보내지 않는다', () async {
    final client = FirebaseHttpClient(
      client: MockClient((request) async {
        fail('미인증 요청 전송');
      }),
      tokenProvider: (_) async => null,
    );
    addTearDown(client.close);
    await expectLater(
      client.get(Uri.parse('http://localhost/inventory')),
      throwsA(isA<StaffAuthException>()),
    );
  });

  test('403은 재요청하거나 로그아웃하지 않는다', () async {
    var requests = 0;
    final client = FirebaseHttpClient(
      client: MockClient((request) async {
        requests++;
        return http.Response('{}', 403);
      }),
      tokenProvider: (_) async => 'token',
      signOut: () async => fail('권한 거부로 로그아웃하면 안 됩니다.'),
    );
    addTearDown(client.close);
    expect(
      (await client.get(Uri.parse('http://localhost/inventory'))).statusCode,
      403,
    );
    expect(requests, 1);
  });
}
