import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/model/order_history.dart';
import 'package:shupick/vm/order_history_detail_vm.dart';

void main() {
  test('모의 취소 중복 클릭 방지 및 완료 후 상세 갱신', () async {
    final pending = Completer<void>();
    var calls = 0;
    var canceled = false;
    final vm = OrderHistoryDetailVm(
      () async =>
          OrderHistory({'order_status': canceled ? 'CANCELED' : 'PAID'}),
      cancelOrder: (_) {
        calls++;
        return pending.future;
      },
    );
    await vm.fetch();
    final operation = vm.submitCancel('test');
    await vm.submitCancel('test');
    expect(calls, 1);
    canceled = true;
    pending.complete();
    await operation;
    expect(vm.cancelSubmitted, isTrue);
    expect(vm.detail!.status, 'CANCELED');
    expect(vm.canCancel, isFalse);
  });
  test('응답 유실 재시도는 같은 키와 사유를 유지', () async {
    final bodies = <Map<String, dynamic>>[];
    final vm = OrderHistoryDetailVm(
      () async => OrderHistory({'order_status': 'PAID'}),
      cancelOrder: (body) async {
        bodies.add(body);
        throw Exception('lost');
      },
    );
    await vm.fetch();
    await vm.submitCancel('test');
    await vm.submitCancel('changed');
    expect(bodies.length, 1);
    await vm.submitCancel('test');
    expect(bodies[0], bodies[1]);
    expect(vm.cancelSubmitted, isFalse);
  });
  test('닫힌 화면에 늦은 성공을 반영하지 않음', () async {
    final pending = Completer<void>();
    final vm = OrderHistoryDetailVm(
      () async => OrderHistory({'order_status': 'PAID'}),
      cancelOrder: (_) => pending.future,
    );
    await vm.fetch();
    final operation = vm.submitCancel('test');
    vm.onDelete();
    pending.complete();
    await operation;
    expect(vm.cancelSubmitted, isFalse);
  });
  test('입력 오류와 출고 이후 주문은 요청하지 않음', () async {
    var calls = 0;
    final vm = OrderHistoryDetailVm(
      () async => OrderHistory({'order_status': 'PAID'}),
      cancelOrder: (_) async {
        calls++;
      },
    );
    await vm.fetch();
    await vm.submitCancel(' ');
    await vm.submitCancel('x' * 256);
    vm.detail = OrderHistory({'order_status': 'SHIPPING'});
    await vm.submitCancel('test');
    expect(calls, 0);
  });
}
