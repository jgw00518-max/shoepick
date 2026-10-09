import 'package:shupick_staff_mockup/model/mock_store.dart';
import 'package:shupick_staff_mockup/model/staff_session.dart';

abstract class StaffAuthRepository {
  Future<StaffProfile?> restoreSession();
  Future<StaffProfile> signIn(String email, String password);
  Future<void> signOut();
}

class MockStaffAuthRepository implements StaffAuthRepository {
  @override
  Future<StaffProfile?> restoreSession() async => null;
  @override
  Future<void> signOut() async {}
  @override
  Future<StaffProfile> signIn(String email, String password) async {
    if (!email.contains('@') || password.isEmpty) {
      throw const StaffAuthException('목업 이메일과 비밀번호를 입력해주세요.');
    }
    final store = MockStore.instance;
    final registered = store.registeredStaff[email.trim().toLowerCase()];
    const labels = {
      'BRANCH_STAFF': '대리점 직원',
      'BRANCH_MANAGER': '대리점장',
      'HQ_STAFF': '본사 사원',
      'TEAM_LEAD': '본사 팀장',
      'DIRECTOR': '본사 이사',
      'EXECUTIVE': '본사 임원',
    };
    final roleCodes = registered == null
        ? labels.keys.toList()
        : [registered['roleCode'] as String];
    final branchRows = registered == null
        ? store.branches.where((b) => b['branchId'] == 1 || b['branchId'] == 16)
        : store.branches.where(
            (b) => b['districtCode'] == registered['districtCode'],
          );
    return StaffProfile(
      id: registered == null ? 1 : 2,
      code: 'MOCK-STAFF',
      name: registered?['name'] as String? ?? '목업 직원',
      roles: [
        for (final role in roleCodes)
          StaffRoleAssignment(code: role, name: labels[role]!),
      ],
      branches: [
        for (final b in branchRows)
          StaffBranch(
            id: b['branchId'] as int,
            code: 'MOCK-${b['branchId']}',
            name: b['branchName'] as String,
            districtCode: b['districtCode'] as String,
          ),
      ],
    );
  }
}
