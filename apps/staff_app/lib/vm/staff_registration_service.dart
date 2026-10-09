import 'package:shupick_staff_mockup/model/mock_store.dart';
import 'package:shupick_staff_mockup/model/staff_session.dart';

abstract class StaffRegistrationRepository {
  Future<void> register({
    required String email,
    required String password,
    required String name,
    required String affiliation,
    required String? districtCode,
    required String roleCode,
  });
}

class MockStaffRegistrationRepository implements StaffRegistrationRepository {
  @override
  Future<void> register({
    required String email,
    required String password,
    required String name,
    required String affiliation,
    required String? districtCode,
    required String roleCode,
  }) async {
    final store = MockStore.instance;
    if (store.registeredStaff.containsKey(email.toLowerCase())) {
      throw const StaffAuthException('이미 목업에 등록된 이메일입니다.');
    }
    store.registeredStaff[email.toLowerCase()] = {
      'name': name,
      'affiliation': affiliation,
      'districtCode': districtCode,
      'roleCode': roleCode,
    };
  }
}
