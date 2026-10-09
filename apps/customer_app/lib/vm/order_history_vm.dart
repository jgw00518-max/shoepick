import 'package:get/get.dart';
import '../model/order_history.dart';
import 'auth_api.dart';

/// C 주문 조회만 담당하며 종료된 화면의 늦은 응답은 무시한다.
class OrderHistoryVm extends GetxController {
  OrderHistoryVm({required this.api});
  final AuthApi api;
  List<OrderHistory> orders = [];
  bool loading = false;
  String? error;
  int page = 1;
  int totalCount = 0;
  int _request = 0;

  @override
  void onInit() {
    super.onInit();
    fetchOrders();
  }

  Future<void> fetchOrders({int targetPage = 1}) async {
    final request = ++_request;
    loading = true;
    error = null;
    orders = [];
    update();
    try {
      final response = await api.getResponse(
        '/api/v1/order-history/customer?page=$targetPage&page_size=20',
      );
      if (isClosed || request != _request) return;
      orders = (response['data'] as List)
          .map((row) => OrderHistory.fromJson(row as Map<String, dynamic>))
          .toList();
      page = targetPage;
      totalCount = response['pagination']['total_count'] as int;
    } catch (_) {
      if (isClosed || request != _request) return;
      error = '주문을 불러오지 못했습니다. 로그인과 서버 연결을 확인해주세요.';
    } finally {
      if (!isClosed && request == _request) {
        loading = false;
        update();
      }
    }
  }

  Future<OrderHistory> fetchDetail(int id) async {
    final data = await api.get('/api/v1/order-history/customer/$id');
    return OrderHistory.fromJson(data);
  }
}
