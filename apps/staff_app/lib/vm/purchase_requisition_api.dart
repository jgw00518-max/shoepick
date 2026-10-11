import '../model/staff_session.dart';
import '../model/purchase_requisition.dart';
import 'auth_api.dart';

class PurchaseRequisitionApi {
  PurchaseRequisitionApi(this.api);
  final AuthApi api;

  Future<Map<String, dynamic>> submit(int id, String revision) async {
    try {
      return await api.post('/api/v1/purchase-requisitions/$id/submit', {
        'revision': revision,
      });
    } on AuthApiException catch (e) {
      throw StaffAuthException(e.message);
    } on StateError catch (e) {
      throw StaffAuthException(e.message.toString());
    } on TypeError {
      throw const StaffAuthException('품의 상신 응답 형식이 올바르지 않습니다.');
    }
  }

  Future<Map<String, dynamic>> detail(int id) async {
    try {
      return await api.get('/api/v1/purchase-requisitions/$id');
    } on AuthApiException catch (e) {
      throw StaffAuthException(e.message);
    } on StateError catch (e) {
      throw StaffAuthException(e.message.toString());
    } on TypeError {
      throw const StaffAuthException('품의 상세 응답 형식이 올바르지 않습니다.');
    }
  }

  Future<Map<String, dynamic>> update(int id, Map<String, dynamic> body) async {
    try {
      return await api.patch('/api/v1/purchase-requisitions/$id', body);
    } on AuthApiException catch (e) {
      throw StaffAuthException(e.message);
    } on StateError catch (e) {
      throw StaffAuthException(e.message.toString());
    } on TypeError {
      throw const StaffAuthException('품의 수정 응답 형식이 올바르지 않습니다.');
    }
  }

  Future<PurchaseRequisitionPage> list({
    int page = 1,
    String? status,
    String order = 'desc',
  }) async {
    try {
      final path = Uri(
        path: '/api/v1/purchase-requisitions',
        queryParameters: {
          'page': '$page',
          'page_size': '20',
          'status': ?status,
          'order': order,
        },
      );
      return PurchaseRequisitionPage.fromJson(
        await api.getResponse(path.toString()),
      );
    } on AuthApiException catch (e) {
      throw StaffAuthException(e.message);
    } on StateError catch (e) {
      throw StaffAuthException(e.message.toString());
    } on TypeError {
      throw const StaffAuthException('최근 품의 조회 응답 형식이 올바르지 않습니다.');
    }
  }

  Future<List<Map<String, dynamic>>> options() async {
    try {
      final response = await api.getResponse(
        '/api/v1/purchase-requisitions/creation-options',
      );
      return (response['data'] as List<dynamic>).cast<Map<String, dynamic>>();
    } on AuthApiException catch (e) {
      throw StaffAuthException(e.message);
    } on StateError catch (e) {
      throw StaffAuthException(e.message.toString());
    } on TypeError {
      throw const StaffAuthException('품의 작성용 상품 응답 형식이 올바르지 않습니다.');
    }
  }

  Future<Map<String, dynamic>> create({
    required int manufacturerId,
    required int productVariantId,
    required int quantity,
    required String title,
    required String reason,
    int? branchId,
  }) async {
    try {
      return await api.post('/api/v1/purchase-requisitions', {
        'manufacturer_id': manufacturerId,
        'branch_id': ?branchId,
        'title': title.trim(),
        'reason': reason.trim(),
        'items': [
          {
            'product_variant_id': productVariantId,
            'requested_quantity': quantity,
          },
        ],
      });
    } on AuthApiException catch (e) {
      throw StaffAuthException(e.message);
    } on StateError catch (e) {
      throw StaffAuthException(e.message.toString());
    } on TypeError {
      throw const StaffAuthException('품의 저장 응답 형식이 올바르지 않습니다.');
    }
  }
}
