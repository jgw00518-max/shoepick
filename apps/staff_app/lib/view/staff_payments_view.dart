import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../vm/staff_payments_vm.dart';

class StaffPaymentsView extends StatefulWidget {
  const StaffPaymentsView({super.key});

  @override
  State<StaffPaymentsView> createState() => _StaffPaymentsViewState();
}

class _StaffPaymentsViewState extends State<StaffPaymentsView> {
  late final String tag;

  @override
  void initState() {
    super.initState();
    tag = 'staff-payments-${identityHashCode(this)}';
    Get.put(StaffPaymentsVm(), tag: tag);
  }

  @override
  void dispose() {
    Get.delete<StaffPaymentsVm>(tag: tag);
    super.dispose();
  }

  String statusLabel(String status) {
    return switch (status) {
      'PENDING' => '결제 대기',
      'PAID' => '결제 완료',
      'FAILED' => '결제 실패',
      'CANCELED' => '취소',
      'PARTIALLY_REFUNDED' => '부분 환불',
      'REFUNDED' => '환불 완료',
      _ => status,
    };
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<StaffPaymentsVm>(
      tag: tag,
      builder: (controller) {
        if (controller.loading) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (controller.error != null) {
          return Column(
            children: [
              Text(controller.error!),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => controller.fetchPayments(),
                child: const Text('다시 시도'),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '전체 결제 기록 ${controller.totalCount}건',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => controller.fetchPayments(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('새로고침'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (controller.payments.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('조회된 결제 기록이 없습니다.'),
                ),
              ),
            for (final payment in controller.payments)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '주문 ID ${payment.orderId}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(statusLabel(payment.status)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('결제 ID: ${payment.id}'),
                      Text('주문 번호: ${payment.orderNumber}'),
                      Text('주문 상태: ${payment.orderStatus}'),
                      Text(
                        '결제 방식: '
                        '${payment.method == 'MOCK' ? '모의 결제' : payment.method}',
                      ),
                      Text('결제 금액: ${payment.amount}원'),
                      Text(
                        '결제 시각: '
                        '${payment.paidAt?.replaceFirst('T', ' ') ?? '미기록'}',
                      ),
                      Text('수령 지점: ${payment.branchName ?? '미지정'}'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: controller.hasPrevious
                      ? () => controller.fetchPayments(
                            targetPage: controller.page - 1,
                          )
                      : null,
                  child: const Text('이전'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('${controller.page} 페이지'),
                ),
                OutlinedButton(
                  onPressed: controller.hasNext
                      ? () => controller.fetchPayments(
                            targetPage: controller.page + 1,
                          )
                      : null,
                  child: const Text('다음'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}