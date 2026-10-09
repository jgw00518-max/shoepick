import 'package:firebase_auth/firebase_auth.dart';

import '../domain/repositories.dart';
import 'auth_api.dart';

/// 기존 계정 인터페이스를 유지하면서 Firebase 로그인과 서버 회원 확인을 연결한다.
class FirebaseAccount implements AccountRepository {
  FirebaseAccount({AuthApi? api}) : api = api ?? AuthApi();

  final AuthApi api;
  int? customerId;

  @override
  Future<bool> signIn(String email, String password) async {
    try {
      await api.auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final customer = await api.get('/api/v1/authentication/customer');
      customerId = customer['customer_id'] as int;
      return true;
    } on FirebaseAuthException {
      await signOut();
      return false;
    } catch (_) {
      await signOut();
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    customerId = null;
    await api.auth.signOut();
  }

  @override
  Future<void> signUp(String email, String password) async {
    throw StateError('초기 검증은 미리 등록한 계정으로 로그인해주세요.');
  }
}
