import '../model/staff_session.dart';
import 'auth_api.dart';

class DashboardApi {
  DashboardApi(this.api);
  final AuthApi api;
  Future<Map<String, dynamic>> executiveSales() async {
    try {
      final data = await api.get('/api/v1/dashboard/executive/sales');
      if ([
        'sales_quantity',
        'revenue_amount',
        'order_count',
      ].any((key) => data[key] is! int)) {
        throw const StaffAuthException('판매 현황 응답 형식이 올바르지 않습니다.');
      }
      return data;
    } on AuthApiException catch (e) {
      throw StaffAuthException(e.message);
    } on StateError catch (e) {
      throw StaffAuthException(e.message.toString());
    } on TypeError {
      throw const StaffAuthException('판매 현황 응답 형식이 올바르지 않습니다.');
    }
  }

  Future<Map<String, dynamic>> headquartersLowStock() async {
    try {
      final data = await api.get('/api/v1/dashboard/headquarters/low-stock');
      if (data['low_stock_variant_count'] is! int ||
          data['monitored_variant_count'] is! int) {
        throw const StaffAuthException('본사 재고 부족 응답 형식이 올바르지 않습니다.');
      }
      return data;
    } on AuthApiException catch (e) {
      throw StaffAuthException(e.message);
    } on StateError catch (e) {
      throw StaffAuthException(e.message.toString());
    } on TypeError {
      throw const StaffAuthException('본사 재고 부족 응답 형식이 올바르지 않습니다.');
    }
  }

  Future<Map<String, dynamic>> branchInventory(int branchId) async {
    try {
      final data = await api.get(
        '/api/v1/dashboard/branches/$branchId/inventory',
      );
      if (data['branch_id'] != branchId ||
          data['held_quantity'] is! int ||
          data['branch_name'] is! String) {
        throw const StaffAuthException('대리점 보관 수량 응답 형식이 올바르지 않습니다.');
      }
      return data;
    } on AuthApiException catch (e) {
      throw StaffAuthException(e.message);
    } on StateError catch (e) {
      throw StaffAuthException(e.message.toString());
    } on TypeError {
      throw const StaffAuthException('대리점 보관 수량 응답 형식이 올바르지 않습니다.');
    }
  }
}
