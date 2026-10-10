import 'package:firebase_auth/firebase_auth.dart';
import 'auth_api.dart';
import '../model/staff_session.dart';
import 'staff_session.dart';
import 'package:flutter/foundation.dart';

/// Firebase 인증 후 서버가 확인한 직원·직책·소속만 기존 화면 모델에 전달한다.
class FirebaseStaffAuth implements StaffAuthRepository {
  FirebaseStaffAuth({AuthApi? api}) : api = api ?? AuthApi();
  final AuthApi api;

  Future<StaffProfile> _profile() async {
    final data = await api.get('/api/v1/authentication/staff');
    return StaffProfile.fromJson({
      'employeeId': data['employee_id'],
      'employeeCode': data['employee_code'],
      'employeeName': data['employee_name'],
      'roles': [
        for (final role in data['roles'])
          {'roleCode': role['role_code'], 'roleName': role['role_name']},
      ],
      'branches': [
        for (final branch in data['branches'])
          {
            'branchId': branch['branch_id'],
            'branchCode': branch['branch_code'],
            'branchName': branch['branch_name'],
            'districtCode': branch['district_code'],
          },
      ],
    });
  }

  @override
  Future<StaffProfile?> restoreSession() async {
    if (api.auth.currentUser == null) return null;
    try {
      return await _profile();
    } catch (_) {
      await signOut();
      rethrow;
    }
  }

  @override
  Future<StaffProfile> signIn(String email, String password) async {
    try {
      await api.auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (kDebugMode) {
        final token = await api.auth.currentUser?.getIdToken(true);
        debugPrint('Firebase ID Token: $token');
      }
      return await _profile();
    } on FirebaseAuthException catch (error) {
      await _clearSession();
      throw StaffAuthException(switch (error.code) {
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' => '이메일 또는 비밀번호가 올바르지 않습니다.',
        'invalid-email' => '이메일 형식을 확인해주세요.',
        'user-disabled' => '사용이 중지된 계정입니다.',
        'network-request-failed' =>
          'Firebase 인증 서버에 연결할 수 없습니다. 인터넷 연결을 확인해주세요.',
        'too-many-requests' => '로그인 시도가 너무 많습니다. 잠시 후 다시 시도해주세요.',
        'operation-not-allowed' => 'Firebase에서 이메일/비밀번호 로그인을 활성화해주세요.',
        _ => 'Firebase 인증에 실패했습니다. (${error.code})',
      });
    } on AuthApiException catch (error) {
      await _clearSession();
      throw StaffAuthException(error.message);
    } on StateError catch (error) {
      await _clearSession();
      throw StaffAuthException(error.message.toString());
    } catch (_) {
      await _clearSession();
      throw const StaffAuthException(
        '직원 로그인 응답을 처리하지 못했습니다. 서버 응답 형식을 확인해주세요.',
      );
    }
  }

  Future<void> _clearSession() async {
    try {
      await signOut();
    } catch (_) {
      // 세션 정리 오류가 원래 로그인 오류를 덮어쓰지 않도록 한다.
    }
  }

  @override
  Future<void> signOut() => api.auth.signOut();
}
