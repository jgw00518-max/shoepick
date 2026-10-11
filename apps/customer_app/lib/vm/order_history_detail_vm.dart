import 'package:get/get.dart';
import 'dart:math';
import '../model/order_history.dart';
import '../model/order_after_sales.dart';

/// 상세 창의 조회 상태를 담당하며 닫힌 창에는 늦은 결과를 반영하지 않는다.
class OrderHistoryDetailVm extends GetxController {
  OrderHistoryDetailVm(
    this.load, {
    this.confirmPurchase,
    this.loadAfterSales,
    this.createReturn,
    this.cancelOrder,
  });
  final Future<void> Function(Map<String, dynamic>)? cancelOrder;
  bool canceling = false;
  bool cancelSubmitted = false;
  String? cancelError;
  Map<String, dynamic>? _pendingCancel;
  String get pendingCancelReason => _pendingCancel?['reason'] as String? ?? '';
  bool get cancelResultUncertain => _pendingCancel != null;
  bool get canCancel =>
      cancelOrder != null &&
      !cancelSubmitted &&
      !canceling &&
      !loading &&
      !confirming &&
      !returning &&
      (detail?.status == 'PAID' || _pendingCancel != null);

  /// 응답 유실 시 같은 요청 키와 사유로 재시도하며 닫힌 화면의 결과는 버린다.
  Future<void> submitCancel(String reason) async {
    if (isClosed || !canCancel) return;
    reason = reason.trim();
    if (reason.isEmpty || reason.length > 255) {
      cancelError = '취소 사유를 1~255자로 입력해주세요.';
      update();
      return;
    }
    if (_pendingCancel != null && _pendingCancel!['reason'] != reason) {
      cancelError = '이전 요청과 같은 사유로 재시도해주세요.';
      update();
      return;
    }
    _pendingCancel ??= {
      'request_id':
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      'reason': reason,
    };
    canceling = true;
    cancelError = null;
    update();
    try {
      await cancelOrder!(Map<String, dynamic>.from(_pendingCancel!));
      if (!isClosed) {
        cancelSubmitted = true;
        _pendingCancel = null;
        await fetch();
        await fetchAfterSales();
      }
    } catch (_) {
      if (!isClosed) {
        cancelError = '취소 결과를 확인하지 못했습니다. 혜택 사용·출고 여부를 확인하고 같은 사유로 재시도해주세요.';
      }
    } finally {
      if (!isClosed) {
        canceling = false;
        update();
      }
    }
  }

  final Future<void> Function(Map<String, dynamic>)? createReturn;
  bool returning = false;
  String? returnError;
  bool returnSubmitted = false;
  Map<String, dynamic>? _pendingReturn;
  String get pendingReturnReason =>
      _pendingReturn?['return_reason'] as String? ?? '';
  String get pendingReturnCode =>
      _pendingReturn?['return_reason_code'] as String? ?? 'CUSTOMER_CHANGE';
  bool get returnResultUncertain => _pendingReturn != null;
  bool get afterSalesReady => loadAfterSales == null || afterSales != null;
  bool get canConfirm =>
      detail?.canConfirmPurchase == true &&
      confirmPurchase != null &&
      !confirming &&
      !canceling &&
      !returning &&
      !returnSubmitted &&
      !returnResultUncertain &&
      !hasActiveReturn &&
      !loading &&
      !afterSalesLoading &&
      afterSalesError == null &&
      afterSalesReady;
  bool get hasActiveReturn =>
      afterSales?.returns.any(
        (record) => [
          'REQUESTED',
          'APPROVED',
          'COLLECTING',
          'INSPECTING',
          'RETURNED',
        ].contains(record['request_status']),
      ) ??
      false;
  bool get canReturn =>
      createReturn != null &&
      detail?.canConfirmPurchase == true &&
      !returnSubmitted &&
      !hasActiveReturn &&
      !afterSalesLoading &&
      afterSalesReady &&
      afterSalesError == null;

  /// 응답 불명 시 같은 요청 식별자로 재시도하여 새 접수를 만들지 않는다.
  Future<void> submitReturn(String reasonCode, String reason) async {
    if (isClosed || returning || confirming || canceling || !canReturn) return;
    if (reason.trim().isEmpty) {
      returnError = '반품 사유를 입력해주세요.';
      update();
      return;
    }
    if (_pendingReturn != null &&
        (_pendingReturn!['return_reason_code'] != reasonCode ||
            _pendingReturn!['return_reason'] != reason.trim())) {
      returnError = '이전 요청 결과가 불명확합니다. 같은 내용으로 재시도해주세요.';
      update();
      return;
    }
    _pendingReturn ??= {
      'request_id':
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      'return_reason_code': reasonCode,
      'return_reason': reason.trim(),
    };
    returning = true;
    returnError = null;
    update();
    try {
      await createReturn!(_pendingReturn!);
      if (!isClosed) {
        returnSubmitted = true;
        _pendingReturn = null;
        await fetchAfterSales();
      }
    } catch (_) {
      if (!isClosed) returnError = '반품 접수 결과를 확인하지 못했습니다. 같은 내용으로 재시도해주세요.';
    } finally {
      if (!isClosed) {
        returning = false;
        update();
      }
    }
  }

  final Future<OrderAfterSales> Function()? loadAfterSales;
  OrderAfterSales? afterSales;
  bool afterSalesLoading = false;
  String? afterSalesError;

  /// 주문 상세와 독립적으로 재시도하며 닫힌 창의 결과는 버린다.
  Future<void> fetchAfterSales() async {
    if (isClosed || afterSalesLoading || loadAfterSales == null) return;
    afterSalesLoading = true;
    afterSalesError = null;
    afterSales = null;
    update();
    try {
      final result = await loadAfterSales!();
      if (!isClosed) afterSales = result;
    } catch (_) {
      if (!isClosed) afterSalesError = '반품·환불 처리내역을 불러오지 못했습니다.';
    } finally {
      if (!isClosed) {
        afterSalesLoading = false;
        update();
      }
    }
  }

  final Future<void> Function()? confirmPurchase;
  bool confirming = false;
  String? confirmationError;
  Future<void> confirm() async {
    if (isClosed || !canConfirm) {
      return;
    }
    confirming = true;
    confirmationError = null;
    update();
    try {
      await confirmPurchase!();
      if (!isClosed) await fetch();
    } catch (_) {
      if (!isClosed) {
        confirmationError = '구매확정 결과를 확인하지 못했습니다. 새로 조회한 뒤 다시 확인해주세요.';
      }
    } finally {
      if (!isClosed) {
        confirming = false;
        update();
      }
    }
  }

  final Future<OrderHistory> Function() load;
  bool loading = false;
  String? error;
  OrderHistory? detail;

  @override
  void onInit() {
    super.onInit();
    fetch();
    fetchAfterSales();
  }

  Future<void> fetch() async {
    if (isClosed || loading) return;
    loading = true;
    error = null;
    detail = null;
    update();
    try {
      final result = await load();
      if (!isClosed) detail = result;
    } catch (_) {
      if (!isClosed) error = '주문 상세를 불러오지 못했습니다.';
    } finally {
      if (!isClosed) {
        loading = false;
        update();
      }
    }
  }
}
