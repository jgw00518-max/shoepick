import 'package:get/get.dart';
import 'dart:math';
import '../model/dispatch_order.dart';

/// 인증 요청 함수만 전달받으며 결제·재고 규칙은 구현하지 않는다.
class DispatchVm extends GetxController {
  DispatchVm({required this.request, this.branchId, this.submit});
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  submit;
  bool submitting = false;
  String? submitError;
  final Map<int, String> _requestIds = {};

  /// 같은 주문 재시도는 같은 키를 사용하며 서버 완료 결과만 성공으로 처리한다.
  Future<bool> confirmDispatch(int orderId) async {
    if (isClosed || submitting || submit == null) return false;
    submitting = true;
    submitError = null;
    update();
    final key = _requestIds.putIfAbsent(
      orderId,
      () =>
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
    );
    try {
      final result = await submit!(
        '/api/v1/order-history/staff/dispatch/$orderId/confirm',
        {'request_id': key, 'confirmed': true},
      );
      if (isClosed) return false;
      if (result['order_id'] != orderId ||
          result['completed'] != true ||
          result['order_status'] != 'SHIPPING') {
        throw StateError('출고 응답을 확인하지 못했습니다.');
      }
      _requestIds.remove(orderId);
      await fetchOrders(requestedPage: page);
      return !isClosed;
    } catch (_) {
      if (!isClosed) submitError = '출고 결과를 확인하지 못했습니다. 같은 주문으로 다시 시도해주세요.';
      return false;
    } finally {
      if (!isClosed) {
        submitting = false;
        update();
      }
    }
  }

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
