import '../model/purchase_approval.dart';
import '../model/staff_session.dart';
import 'auth_api.dart';

class PurchaseApprovalApi {
  PurchaseApprovalApi(this.api);
  final AuthApi api;

  Future<Map<String, dynamic>> decide(
    int id, {
    required bool approve,
    required String revision,
    required String comment,
    required String stage,
  }) => _safe(() async {
    return await api.post(
      '/api/v1/purchase-approvals/$id/${approve ? 'approve' : 'reject'}${stage == 'DIRECTOR' ? '?stage=DIRECTOR' : ''}',
      {'revision': revision, 'comment': comment.trim()},
    );
  });

  Future<PurchaseApprovalPage> overview({
    int page = 1,
    String? status,
    String keyword = '',
    String? submittedFrom,
    String? submittedTo,
    String order = 'desc',
  }) => _safe(() async {
    final uri = Uri(
      path: '/api/v1/purchase-approvals/overview',
      queryParameters: {
        'page': '$page',
        'page_size': '20',
        'status': ?status,
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
        'submitted_from': ?submittedFrom,
        'submitted_to': ?submittedTo,
        'order': order,
      },
    );
    return PurchaseApprovalPage.fromJson(await api.getResponse(uri.toString()));
  });
  Future<Map<String, dynamic>> overviewDetail(int id) =>
      _safe(() => api.get('/api/v1/purchase-approvals/overview/$id'));
  Future<T> _safe<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on AuthApiException catch (e) {
      throw StaffAuthException(e.message);
    } on StateError catch (e) {
      throw StaffAuthException(e.message.toString());
    } on TypeError {
      throw const StaffAuthException('결재 조회 응답 형식이 올바르지 않습니다.');
    }
  }

  Future<PurchaseApprovalPage> list({
    required String stage,
    required String view,
    int page = 1,
    String order = 'desc',
  }) => _safe(() async {
    final uri = Uri(
      path: '/api/v1/purchase-approvals/$view',
      queryParameters: {
        'stage': stage,
        'page': '$page',
        'page_size': '20',
        'order': order,
      },
    );
    return PurchaseApprovalPage.fromJson(await api.getResponse(uri.toString()));
  });
  Future<Map<String, dynamic>> detail(int id, String stage) => _safe(
    () => api.get(
      Uri(
        path: '/api/v1/purchase-approvals/$id',
        queryParameters: {'stage': stage},
      ).toString(),
    ),
  );
}
