import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../vm/dispatch_vm.dart';

/// 화면이 컨트롤러를 소유하여 직급·대리점 변경과 로그아웃 시 목록을 정리한다.
class DispatchView extends StatelessWidget {
  const DispatchView({super.key, required this.request, this.branchId});
  final Future<Map<String, dynamic>> Function(String) request;
  final int? branchId;

  @override
  Widget build(BuildContext context) => GetBuilder<DispatchVm>(
    init: DispatchVm(request: request, branchId: branchId),
    global: false,
    builder: (vm) => Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('출고 대상 조회')),
                IconButton(
                  tooltip: '새로고침',
                  onPressed: vm.isLoading ? null : () => vm.fetchOrders(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (vm.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (vm.error != null) ...[
              Text(vm.error!),
              TextButton(
                onPressed: () => vm.fetchOrders(),
                child: const Text('다시 시도'),
              ),
            ] else if (vm.orders.isEmpty)
              const Text('출고 대상 주문이 없습니다.')
            else ...[
              for (final order in vm.orders)
                ListTile(
                  title: Text(order.orderNumber),
                  subtitle: Text(order.branchName),
                  trailing: Text('${order.paidTotal}원'),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: vm.page > 1
                        ? () => vm.fetchOrders(requestedPage: vm.page - 1)
                        : null,
                    child: const Text('이전'),
                  ),
                  Text('${vm.page}페이지 · 총 ${vm.totalCount}건'),
                  TextButton(
                    onPressed: vm.hasNext
                        ? () => vm.fetchOrders(requestedPage: vm.page + 1)
                        : null,
                    child: const Text('다음'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
