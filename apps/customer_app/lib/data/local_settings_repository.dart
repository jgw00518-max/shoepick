import 'package:shared_preferences/shared_preferences.dart';

/// 서버 데이터와 무관한 표시 설정만 로컬 저장소에 보관합니다.
class LocalSettingsRepository {
  SharedPreferencesAsync get _preferences => SharedPreferencesAsync();

  Future<String> language() async =>
      await _preferences.getString('language') ?? '한국어';
  Future<bool> dark() async => await _preferences.getBool('dark') ?? false;
  Future<bool> push() async => await _preferences.getBool('push') ?? true;

  Future<void> saveLanguage(String value) =>
      _preferences.setString('language', value);
  Future<void> saveDark(bool value) => _preferences.setBool('dark', value);
  Future<void> savePush(bool value) => _preferences.setBool('push', value);
}
