import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../model/order_history.dart';
import '../model/order_after_sales.dart';
import 'order_history_detail.dart';
import '../vm/order_history_detail_vm.dart';
import '../vm/auth_api.dart';
import '../vm/order_history_vm.dart';

/// 기존 주문 내역 진입점에서 인증된 고객의 조회 결과를 표시한다.
class OrderHistoryView extends StatefulWidget {
  const OrderHistoryView({super.key, this.api});
  final AuthApi? api;
  @override
  State<OrderHistoryView> createState() => _OrderHistoryViewState();
}

class _OrderHistoryViewState extends State<OrderHistoryView> {
  late final String _tag;
  late final OrderHistoryVm _vm;
  bool _opening = false;
  OrderHistoryDetailVm? _detailVm;

  @override
  void initState() {
    super.initState();
    _tag = 'order-history-${identityHashCode(this)}';
    _vm = Get.put(OrderHistoryVm(api: widget.api ?? AuthApi()), tag: _tag);
  }

  @override
  void dispose() {
    if (_detailVm != null && !_detailVm!.isClosed) _detailVm!.onDelete();
    Get.delete<OrderHistoryVm>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GetBuilder<OrderHistoryVm>(
    tag: _tag,
    builder: (vm) {
      if (vm.loading) return const Center(child: CircularProgressIndicator());
      if (vm.error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(vm.error!),
              TextButton(
                onPressed: () => vm.fetchOrders(targetPage: vm.page),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '주문 내역',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const Text('주문과 배송 상태를 확인하세요.'),
          if (vm.orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('구매 내역이 없습니다.'),
            ),
          for (final order in vm.orders)
            Card(
              child: ListTile(
                title: Text(order.number),
                subtitle: Text(
                  '${order.statusLabel} · ${order.branch}\n${order.paidTotal}원',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: _opening ? null : () => _openDetail(order),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: vm.page > 1
                    ? () => vm.fetchOrders(targetPage: vm.page - 1)
                    : null,
                child: const Text('이전'),
              ),
              Text('${vm.page}'),
              TextButton(
                onPressed: vm.page * 20 < vm.totalCount
                    ? () => vm.fetchOrders(targetPage: vm.page + 1)
                    : null,
                child: const Text('다음'),
              ),
            ],
          ),
        ],
      );
    },
  );

  Future<void> _openDetail(OrderHistory order) async {
    if (_opening) return;
    setState(() => _opening = true);
    final detailVm = OrderHistoryDetailVm(
      () => _vm.fetchDetail(order.id),
      cancelOrder: (body) async {
        final response = await _vm.api.post(
          '/api/v1/order-history/customer/${order.id}/cancel-mock',
          body,
        );
        final data = response['data'] as Map?;
        if (data?['order_id'] != order.id ||
            data?['completed'] != true ||
            data?['is_mock'] != true ||
            data?['order_status'] != 'CANCELED') {
          throw StateError('Invalid mock cancel response');
        }
      },
      createReturn: (body) async {
        final response = await _vm.api.post(
          '/api/v1/order-history/customer/${order.id}/returns',
          body,
        );
        if ((response['data'] as Map?)?['return_request_id'] is! int) {
          throw StateError('Invalid return response');
        }
      },
      loadAfterSales: () async => OrderAfterSales.fromJson(
        await _vm.api.get(
          '/api/v1/order-history/customer/${order.id}/after-sales',
        ),
      ),
      confirmPurchase: () async {
        await _vm.api.post(
          '/api/v1/order-history/customer/${order.id}/purchase-confirmation',
          {},
        );
        if (!_vm.isClosed) await _vm.fetchOrders(targetPage: _vm.page);
      },
    );
    _detailVm = detailVm;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => OrderHistoryDetail(number: order.number, vm: detailVm),
      );
    } finally {
      if (!detailVm.isClosed) detailVm.onDelete();
      if (detailVm.cancelSubmitted && !_vm.isClosed) {
        await _vm.fetchOrders(targetPage: _vm.page);
      }
      _detailVm = null;
      if (mounted) setState(() => _opening = false);
    }
  }
}
