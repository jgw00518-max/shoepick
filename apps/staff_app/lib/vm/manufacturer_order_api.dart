import '../model/manufacturer_order.dart';
import '../model/staff_session.dart';
import 'auth_api.dart';

class ManufacturerOrderApi {
  ManufacturerOrderApi(this.api);
  final AuthApi api;
  Future<T> _safe<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on AuthApiException catch (e) {
      throw StaffAuthException(e.message);
    } on StateError catch (e) {
      throw StaffAuthException(e.message.toString());
    } on TypeError {
      throw const StaffAuthException('발주 조회 응답 형식이 올바르지 않습니다.');
    }
  }

  Future<ManufacturerOrderPage> list({
    int page = 1,
    String order = 'desc',
    String keyword = '',
  }) => _safe(() async {
    final uri = Uri(
      path: '/api/v1/manufacturer-orders',
      queryParameters: {
        'page': '$page',
        'page_size': '20',
        'order': order,
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
    );
    return ManufacturerOrderPage.fromJson(
      await api.getResponse(uri.toString()),
    );
  });
  Future<Map<String, dynamic>> detail(int id) =>
      _safe(() => api.get('/api/v1/manufacturer-orders/$id'));
}
