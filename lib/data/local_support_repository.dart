import 'package:shared_preferences/shared_preferences.dart';

import 'mock_repositories.dart';

/// 문의는 목업 데이터로 두고 재입고 신청만 기기에 저장합니다.
class LocalSupportRepository extends MockSupportRepository {
  SharedPreferencesAsync get _preferences => SharedPreferencesAsync();

  @override
  Future<Set<String>> getRestockKeys() async {
    try {
      return (await _preferences.getStringList('restockKeys') ?? []).toSet();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveRestockKeys(Set<String> keys) async {
    try {
      await _preferences.setStringList('restockKeys', keys.toList());
    } catch (_) {
      /* 플러그인이 없는 테스트 환경에서도 목업은 동작합니다. */
    }
  }
}
