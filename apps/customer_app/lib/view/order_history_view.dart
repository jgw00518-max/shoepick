import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../model/order_history.dart';
import '../vm/auth_api.dart';
import '../vm/order_history_vm.dart';

/// 기존 주문 내역 진입점에서 인증된 고객의 조회 결과를 표시한다.
class OrderHistoryView extends StatefulWidget {
  const OrderHistoryView({super.key});
  @override
  State<OrderHistoryView> createState() => _OrderHistoryViewState();
}

class _OrderHistoryViewState extends State<OrderHistoryView> {
  late final String _tag;
  late final OrderHistoryVm _vm;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _tag = 'order-history-${identityHashCode(this)}';
    _vm = Get.put(OrderHistoryVm(api: AuthApi()), tag: _tag);
  }

  @override
  void dispose() {
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
                  '${order.status} · ${order.branch}\n${order.paidTotal}원',
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
    setState(() => _opening = true);
    try {
      final detail = await _vm.fetchDetail(order.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(detail.number),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('상태: ${detail.status}'),
                Text('수령: ${detail.branch}'),
                for (final item in detail.items)
                  Text(
                    '${item['product_name']} · ${item['color_name']} · ${item['size_mm']}\n${item['quantity']}개 / ${item['line_total']}원',
                  ),
                Text('결제 금액: ${detail.paidTotal}원'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('상세 조회에 실패했습니다. 다시 선택해주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }
}
