import 'package:get/get.dart';
import '../model/dispatch_order.dart';

/// 인증 요청 함수만 전달받으며 결제·재고 규칙은 구현하지 않는다.
class DispatchVm extends GetxController {
  DispatchVm({required this.request, this.branchId});
  final Future<Map<String, dynamic>> Function(String) request;
  final int? branchId;
  bool isLoading = false;
  String? error;
  List<DispatchOrder> orders = [];
  int page = 1;
  int totalCount = 0;
  bool get hasNext => page * 20 < totalCount;

  @override
  void onInit() {
    super.onInit();
    fetchOrders();
  }

  Future<void> fetchOrders({int requestedPage = 1}) async {
    if (isLoading || isClosed) return;
    isLoading = true;
    error = null;
    orders = [];
    totalCount = 0;
    update();
    try {
      final response = await request(
        '/api/v1/order-history/staff/dispatch?page=$requestedPage&page_size=20${branchId == null ? '' : '&branch_id=$branchId'}',
      );
      if (isClosed) return;
      final rows = (response['data'] as List)
          .map(
            (row) =>
                DispatchOrder.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
      final pagination = response['pagination'] as Map;
      orders = rows;
      page = pagination['page'] as int;
      totalCount = pagination['total_count'] as int;
    } catch (exception) {
      if (isClosed) return;
      error = exception is StateError
          ? exception.message.toString()
          : '출고 목록을 불러오지 못했습니다. 다시 시도해주세요.';
    } finally {
      if (!isClosed) {
        isLoading = false;
        update();
      }
    }
  }
}
