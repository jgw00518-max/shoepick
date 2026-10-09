import 'auth_api.dart';
import '../model/staff_session.dart';
import 'staff_session.dart';

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
      return await _profile();
    } catch (_) {
      await signOut();
      throw const StaffAuthException('로그인 정보·직원 권한·서버 연결을 확인해주세요.');
    }
  }

  @override
  Future<void> signOut() => api.auth.signOut();
}
