import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../model/order_history.dart';
import '../model/order_after_sales.dart';

import '../vm/order_history_detail_vm.dart';

class OrderHistoryDetail extends StatelessWidget {
  const OrderHistoryDetail({super.key, required this.number, required this.vm});
  final String number;
  final OrderHistoryDetailVm vm;

  Future<void> _cancelForm(BuildContext context) async {
    var reason = vm.pendingCancelReason;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('구매 취소 · 모의 환불'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '출고 전 주문 전체를 취소합니다. 실제 결제·환불은 발생하지 않습니다. 쿠폰·적립금 사용 주문은 현재 지원하지 않습니다.',
              ),
              TextFormField(
                initialValue: reason,
                maxLength: 255,
                decoration: const InputDecoration(labelText: '취소 사유'),
                onChanged: (value) => setState(() => reason = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
            TextButton(
              onPressed: reason.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, reason.trim()),
              child: const Text('취소 요청'),
            ),
          ],
        ),
      ),
    );
    if (result != null && context.mounted && !vm.isClosed) {
      await vm.submitCancel(result);
    }
  }

  Future<void> _returnForm(BuildContext context) async {
    var reason = vm.pendingReturnReason;
    var code = vm.pendingReturnCode;
    final body = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('주문 전체 반품 접수'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('주문의 모든 상품을 접수합니다. 접수만으로 환불되지 않습니다.'),
              DropdownButton<String>(
                value: code,
                items:
                    const {
                          'CUSTOMER_CHANGE': '단순 변심',
                          'PRODUCT_DEFECT': '상품 하자',
                          'WRONG_ITEM': '오배송',
                          'OTHER': '기타',
                        }.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setState(() => code = value!),
              ),
              TextFormField(
                initialValue: reason,
                decoration: const InputDecoration(labelText: '반품 사유'),
                onChanged: (value) => setState(() => reason = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
            TextButton(
              onPressed: reason.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, {
                      'code': code,
                      'reason': reason.trim(),
                    }),
              child: const Text('접수하기'),
            ),
          ],
        ),
      ),
    );
    if (body != null && context.mounted && !vm.isClosed) {
      await vm.submitReturn(body['code']!, body['reason']!);
    }
  }

  @override
  Widget build(BuildContext context) => GetBuilder<OrderHistoryDetailVm>(
    init: vm,
    global: false,
    builder: (state) => AlertDialog(
      title: Text(number),
      content: SingleChildScrollView(
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.error!),
                  TextButton(
                    onPressed: state.fetch,
                    child: const Text('다시 시도'),
                  ),
                ],
              )
            : _content(context, state.detail!),
      ),
      actions: [
        if (state.canReturn)
          TextButton(
            onPressed: state.returning || state.confirming
                ? null
                : () => _returnForm(context),
            child: Text(state.returning ? '접수 중' : '주문 전체 반품 접수'),
          ),
        if (state.detail?.canConfirmPurchase == true &&
            state.confirmPurchase != null)
          TextButton(
            onPressed: !state.canConfirm
                ? null
                : () async {
                    final agreed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('구매확정'),
                        content: const Text(
                          '구매확정 후에는 반품·환불이 불가능합니다. 구매확정하시겠습니까?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('돌아가기'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('확정하기'),
                          ),
                        ],
                      ),
                    );
                    if (agreed == true && context.mounted && !state.isClosed) {
                      await state.confirm();
                    }
                  },
            child: Text(state.confirming ? '처리 중' : '구매확정'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    ),
  );

  Widget _content(BuildContext context, OrderHistory detail) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('주문 번호: ${detail.number}'),
      Text('주문 상태: ${detail.statusLabel}'),
      if (detail.purchaseConfirmedAt != null)
        Text('구매확정 시각: ${detail.purchaseConfirmedAt}'),
      if (vm.confirmationError != null) Text(vm.confirmationError!),
      if (vm.returnError != null) Text(vm.returnError!),
      if (vm.returnSubmitted) const Text('반품이 접수되었습니다. 환불 완료가 아닙니다.'),
      if (vm.returnResultUncertain && !vm.returning)
        const Text('반품 접수 결과 확인 전에는 구매확정할 수 없습니다. 같은 내용으로 접수를 재시도해주세요.'),
      if (vm.hasActiveReturn) const Text('반품 진행 중에는 구매확정할 수 없습니다.'),
      if (detail.status == 'PAID' ||
          vm.cancelResultUncertain ||
          vm.canceling) ...[
        const Text('구매 취소는 실제 출고 전까지만 가능합니다. 모의 결제·환불로 처리합니다.'),
        TextButton(
          onPressed: vm.canCancel ? () => _cancelForm(context) : null,
          child: Text(vm.canceling ? '취소 처리 중' : '구매 취소 · 모의 환불'),
        ),
      ],
      if (vm.cancelError != null) Text(vm.cancelError!),
      if (vm.cancelSubmitted) const Text('모의 환불과 주문 취소가 완료되었습니다.'),
      Text('수령 대리점: ${detail.branch}'),
      const Divider(),
      const Text('주문 상품'),
      if (detail.items.isEmpty) const Text('상품 정보가 없습니다.'),
      for (final item in detail.items) _item(item),
      Text('결제 금액: ${detail.paidTotal}원'),
      const Divider(),
      const Text('배송·수령 정보'),
      if (detail.fulfillments.isEmpty) const Text('등록된 배송·수령 정보가 없습니다.'),
      for (final shipment in detail.fulfillments) _shipment(shipment),
      if (vm.loadAfterSales != null) ...[
        const Divider(),
        const Text('반품·환불 처리내역'),
        if (vm.afterSalesLoading) const CircularProgressIndicator(),
        if (vm.afterSalesError != null) ...[
          Text(vm.afterSalesError!),
          TextButton(
            onPressed: vm.fetchAfterSales,
            child: const Text('처리내역 다시 시도'),
          ),
        ],
        if (vm.afterSales?.isEmpty == true) const Text('반품·환불 처리내역이 없습니다.'),
        for (final record in vm.afterSales?.returns ?? <Map<String, dynamic>>[])
          _afterSalesRecord(record, refund: false),
        for (final record in vm.afterSales?.refunds ?? <Map<String, dynamic>>[])
          _afterSalesRecord(record, refund: true),
      ],
    ],
  );

  Widget _afterSalesRecord(
    Map<String, dynamic> record, {
    required bool refund,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          refund
              ? OrderAfterSales.refundLabel(record['refund_status'])
              : OrderAfterSales.returnLabel(record['request_status']),
        ),
        if (refund) Text('환불 금액: ${record['refund_amount'] ?? '정보 없음'}원'),
        if (!refund && record['return_reason'] != null)
          Text('반품 사유: ${record['return_reason']}'),
        if (!refund && record['rejection_reason'] != null)
          Text('거절 이유: ${record['rejection_reason']}'),
        // 시간대 합의 전에는 서버 기록을 변환하지 않는다.
        for (final entry in {
          'requested_at': '접수 시각',
          'processed_at': '처리 시각',
          'completed_at': '환불 완료 시각',
          'failed_at': '환불 실패 시각',
        }.entries)
          if (record[entry.key] != null)
            Text('${entry.value} (서버 기록): ${record[entry.key]}'),
      ],
    ),
  );

  Widget _item(Map<String, dynamic> item) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${item['product_name'] ?? '상품 정보 없음'}'),
        Text(
          '옵션: ${item['color_name'] ?? '정보 없음'} / ${item['size_mm'] ?? '정보 없음'} mm',
        ),
        Text('수량: ${item['quantity'] ?? '정보 없음'}개'),
        Text('단가: ${item['unit_price'] ?? '정보 없음'}원'),
        Text('항목 금액: ${item['line_total'] ?? '정보 없음'}원'),
      ],
    ),
  );

  Widget _shipment(Map<String, dynamic> shipment) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '배송 상태: ${OrderHistory.fulfillmentLabel(shipment['fulfillment_status'] as String?)}',
        ),
        Text('운송장: ${shipment['tracking_number'] ?? '등록되지 않음'}'),
        // 시간대가 미확정이므로 서버 문자열을 변환하지 않고 원문으로 표시한다.
        for (final entry in {
          'shipped_at': '출고 시각',
          'arrived_at': '도착 시각',
          'completed_at': '완료 시각',
        }.entries)
          if (shipment[entry.key] != null)
            Text('${entry.value} (서버 기록): ${shipment[entry.key]}'),
      ],
    ),
  );
}
