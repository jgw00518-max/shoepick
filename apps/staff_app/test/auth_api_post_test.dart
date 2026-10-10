import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/vm/auth_api.dart';

class TokenUser extends Fake implements User {
  final refreshes = <bool>[];
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    refreshes.add(forceRefresh);
    return forceRefresh ? 'refreshed' : 'original';
  }
}

class TokenAuth extends Fake implements FirebaseAuth {
  final user = TokenUser();
  @override
  User? get currentUser => user;
}

void main() {
  for (final method in ['POST', 'PATCH']) {
    test('$method sends bearer and JSON and retries only after 401', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final tokens = <String?>[];
      final bodies = <dynamic>[];
      server.listen((request) async {
        expect(request.method, method);
        expect(request.headers.contentType!.mimeType, 'application/json');
        tokens.add(request.headers.value(HttpHeaders.authorizationHeader));
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
        request.response.statusCode = tokens.length == 1
            ? 401
            : method == 'POST'
            ? 201
            : 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            tokens.length == 1
                ? {
                    'error': {'code': 'UNAUTHENTICATED'},
                  }
                : {
                    'data': {'purchase_requisition_id': 51},
                  },
          ),
        );
        await request.response.close();
      });
      final auth = TokenAuth();
      final api = AuthApi(
        auth: auth,
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      final body = {'title': '구매 품의'};
      final result = method == 'POST'
          ? await api.post('/api/v1/purchase-requisitions', body)
          : await api.patch('/api/v1/purchase-requisitions/51', body);
      expect(result['purchase_requisition_id'], 51);
      expect(tokens, ['Bearer original', 'Bearer refreshed']);
      expect(bodies, [
        {'title': '구매 품의'},
        {'title': '구매 품의'},
      ]);
      expect(auth.user.refreshes, [false, true]);
    });
  }
}
