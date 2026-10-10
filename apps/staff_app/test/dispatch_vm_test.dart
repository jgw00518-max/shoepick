import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/vm/dispatch_vm.dart';

void main() {
  test('선택 대리점과 페이지를 전달하고 목록을 읽는다', () async {
    String? path;
    final vm = DispatchVm(
      branchId: 3,
      request: (value) async {
        path = value;
        return {
          'data': [
            {
              'order_id': 1,
              'order_number': 'ORDER-1',
              'branch_name': '대리점',
              'paid_total': 59000,
            },
          ],
          'pagination': {'page': 2, 'total_count': 41},
        };
      },
    );
    await vm.fetchOrders(requestedPage: 2);
    expect(path, contains('branch_id=3'));
    expect(path, contains('page=2'));
    expect(vm.orders.single.orderId, 1);
    expect(vm.hasNext, isTrue);
  });
  test('연동 대기 오류 이후 재시도하며 중복 요청을 막는다', () async {
    var calls = 0;
    final pending = Completer<Map<String, dynamic>>();
    final vm = DispatchVm(
      request: (_) {
        calls++;
        return pending.future;
      },
    );
    final first = vm.fetchOrders();
    await vm.fetchOrders();
    expect(calls, 1);
    pending.completeError(StateError('출고 조회 연동을 준비 중입니다.'));
    await first;
    expect(vm.error, contains('연동'));
    expect(vm.orders, isEmpty);
    expect(vm.isLoading, isFalse);
  });
  test('화면 종료 후 늦게 도착한 응답을 저장하지 않는다', () async {
    final pending = Completer<Map<String, dynamic>>();
    final vm = DispatchVm(request: (_) => pending.future);
    final task = vm.fetchOrders();
    vm.onDelete();
    pending.complete({
      'data': [],
      'pagination': {'page': 2, 'total_count': 0},
    });
    await task;
    expect(vm.page, 1);
  });
}
