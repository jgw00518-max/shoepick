import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shupick/vm/firebase_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/vm/auth_api.dart';

class TestUser extends Fake implements User {
  final refreshes = <bool>[];
  String? token = 'old-token';
  Future<String?>? refreshed;
  @override
  String get uid => 'test-uid';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    refreshes.add(forceRefresh);
    return forceRefresh
        ? await (refreshed ?? Future.value('new-token'))
        : token;
  }
}

class TestCredential extends Fake implements UserCredential {}

class TestAuth extends Fake implements FirebaseAuth {
  User? user = TestUser();
  int signOuts = 0;
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    user = TestUser();
    return TestCredential();
  }

  @override
  User? get currentUser => user;
  @override
  Future<void> signOut() async {
    signOuts++;
    user = null;
  }
}

void main() {
  late HttpServer server;
  late TestAuth auth;
  late AuthApi api;
  late List<String?> headers;
  late List<int> statuses;
  late List<String> bodies;
  late List<String> methods;
  late bool malformed;
  late String payload;
  setUp(() async {
    auth = TestAuth();
    headers = [];
    bodies = [];
    methods = [];
    statuses = [200];
    malformed = false;
    payload = '{"data":{"customer_id":7}}';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      headers.add(request.headers.value('authorization'));
      methods.add(request.method);
      bodies.add(await utf8.decoder.bind(request).join());
      request.response.statusCode = statuses.length > 1
          ? statuses.removeAt(0)
          : statuses.first;
      request.response.write(malformed ? 'not-json' : payload);
      await request.response.close();
    });
    api = AuthApi(auth: auth, baseUrl: 'http://127.0.0.1:${server.port}');
  });
  tearDown(() async {
    await server.close(force: true);
  });

  test('successful login session request preserves Bearer token', () async {
    expect((await api.get('/session'))['customer_id'], 7);
    expect(headers, ['Bearer old-token']);
    expect(auth.signOuts, 0);
  });
  test('401 refreshes once and retries with new token', () async {
    final user = auth.user as TestUser;
    statuses = [401, 200];
    await api.get('/session');
    expect(headers, ['Bearer old-token', 'Bearer new-token']);
    expect(user.refreshes, [false, true]);
  });
  test('non JSON 401 still clears authentication after two requests', () async {
    statuses = [401];
    malformed = true;
    await expectLater(api.get('/session'), throwsStateError);
    expect(headers.length, 2);
    expect(auth.user, isNull);
    expect(auth.signOuts, 1);
  });
  test('non JSON 403 does not retry or sign out', () async {
    statuses = [403];
    malformed = true;
    await expectLater(api.get('/session'), throwsStateError);
    expect(headers.length, 1);
    expect(auth.signOuts, 0);
  });
  test('missing token never sends a request', () async {
    (auth.user as TestUser).token = null;
    await expectLater(api.get('/session'), throwsStateError);
    expect(headers, isEmpty);
  });
  test('logged out user never sends a request', () async {
    await auth.signOut();
    await expectLater(api.get('/session'), throwsStateError);
    expect(headers, isEmpty);
  });
  test(
    'POST preserves JSON and idempotency key on authentication retry',
    () async {
      statuses = [401, 201];
      await api.post('/payment', {'transaction_key': 'test-key'});
      expect(methods, ['POST', 'POST']);
      expect(bodies.map(jsonDecode).toList(), [
        {'transaction_key': 'test-key'},
        {'transaction_key': 'test-key'},
      ]);
    },
  );

  test('concurrent 401 responses share one pending token refresh', () async {
    final user = auth.user as TestUser;
    final gate = Completer<String?>();
    user.refreshed = gate.future;
    statuses = [401, 401, 200];
    final requests = [api.get('/first'), api.get('/second')];
    // Let both requests enter the refresh boundary before releasing the token.
    for (var i = 0; i < 100 && headers.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    gate.complete('new-token');
    await Future.wait(requests);
    expect(user.refreshes.where((value) => value).length, 1);
    expect(headers.length, 4);
  });
  test(
    'FirebaseAccount preserves customer login and clears ID on logout',
    () async {
      final account = FirebaseAccount(api: api);
      expect(await account.signIn('user@example.com', 'test-password'), isTrue);
      expect(account.customerId, 7);
      await account.signOut();
      expect(account.customerId, isNull);
      expect(auth.user, isNull);
    },
  );
  test('unregistered customer session clears Firebase state', () async {
    statuses = [403];
    final account = FirebaseAccount(api: api);
    await expectLater(
      account.signIn('user@example.com', 'test-password'),
      throwsStateError,
    );
    expect(account.customerId, isNull);
    expect(auth.user, isNull);
  });
}
