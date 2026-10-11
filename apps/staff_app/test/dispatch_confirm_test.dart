import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/vm/dispatch_vm.dart';

void main() {
  Future<Map<String, dynamic>> read(String _) async => {
    'data': <dynamic>[],
    'pagination': {'page': 1, 'total_count': 0},
  };
  test('동일 주문 실패 재시도는 키 유지하고 성공 후 목록 갱신', () async {
    final bodies = <Map<String, dynamic>>[];
    var attempts = 0;
    final vm = DispatchVm(
      request: read,
      submit: (path, body) async {
        bodies.add(body);
        if (++attempts == 1) throw Exception('lost response');
        return {'order_id': 1, 'order_status': 'SHIPPING', 'completed': true};
      },
    );
    expect(await vm.confirmDispatch(1), isFalse);
    expect(await vm.confirmDispatch(1), isTrue);
    expect(bodies[0], bodies[1]);
    expect(vm.submitError, isNull);
  });
  test('연속 클릭과 화면 종료 후 늦은 결과 차단', () async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    final vm = DispatchVm(
      request: read,
      submit: (path, body) {
        calls++;
        return pending.future;
      },
    );
    final first = vm.confirmDispatch(1);
    expect(await vm.confirmDispatch(1), isFalse);
    expect(calls, 1);
    vm.onDelete();
    pending.complete({
      'order_id': 1,
      'order_status': 'SHIPPING',
      'completed': true,
    });
    expect(await first, isFalse);
  });
  test('완료 아닌 응답을 성공으로 표시하지 않음', () async {
    final vm = DispatchVm(
      request: read,
      submit: (path, body) async => {'order_id': 1, 'completed': false},
    );
    expect(await vm.confirmDispatch(1), isFalse);
    expect(vm.submitError, isNotNull);
  });
}
