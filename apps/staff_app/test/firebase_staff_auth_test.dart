import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/model/staff_session.dart';
import 'package:shoepick_staff_app/vm/auth_api.dart';
import 'package:shoepick_staff_app/vm/firebase_staff_auth.dart';

class TestAuth extends Fake implements FirebaseAuth {
  FirebaseAuthException? failure;
  int signOutCalls = 0;

  @override
  User? get currentUser => null;

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (failure != null) throw failure!;
    return TestCredential();
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

class TestCredential extends Fake implements UserCredential {}

class FailingApi extends AuthApi {
  FailingApi(TestAuth auth) : super(auth: auth);
  @override
  Future<Map<String, dynamic>> get(String path) async {
    throw const AuthApiException('API 서버에 연결할 수 없습니다.');
  }
}

void main() {
  test('Android emulator uses the same default API address as inventory', () {
    expect(AuthApi(auth: TestAuth()).baseUrl, 'http://10.0.2.2:8000');
  });

  for (final entry in {
    'invalid-credential': '이메일 또는 비밀번호가 올바르지 않습니다.',
    'network-request-failed': 'Firebase 인증 서버에 연결할 수 없습니다. 인터넷 연결을 확인해주세요.',
  }.entries) {
    test('Firebase ${entry.key} preserves its actionable reason', () async {
      final auth = TestAuth()..failure = FirebaseAuthException(code: entry.key);
      await expectLater(
        FirebaseStaffAuth(
          api: AuthApi(auth: auth),
        ).signIn('staff@example.com', 'test'),
        throwsA(
          isA<StaffAuthException>().having(
            (e) => e.message,
            'message',
            entry.value,
          ),
        ),
      );
      expect(auth.signOutCalls, 1);
    });
  }

  test(
    'API failure after Firebase sign-in is shown and clears the session',
    () async {
      final auth = TestAuth();
      await expectLater(
        FirebaseStaffAuth(
          api: FailingApi(auth),
        ).signIn('staff@example.com', 'test'),
        throwsA(
          isA<StaffAuthException>().having(
            (e) => e.message,
            'message',
            'API 서버에 연결할 수 없습니다.',
          ),
        ),
      );
      expect(auth.signOutCalls, 1);
    },
  );
}
