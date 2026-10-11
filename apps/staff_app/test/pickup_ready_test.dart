import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/vm/pickup_candidates_vm.dart';

Future<Map<String, dynamic>> read(String _) async => {
  'data': [],
  'pagination': {'page': 1, 'total_count': 0},
};
void ready(PickupCandidatesVm vm) {
  vm.detail = {
    'fulfillment_id': 7,
    'fulfillment_status': 'INSPECTING',
    'inspected_at': 'RAW',
  };
}

void main() {
  test('응답 유실 재시도는 같은 키를 사용하고 성공 후 목록을 갱신한다', () async {
    final keys = <String>[];
    final vm = PickupCandidatesVm(
      arrival: true,
      read: read,
      submit: (path, body) async {
        expect(path, endsWith('/7/ready'));
        expect(body['confirmed'], true);
        keys.add(body['request_id'] as String);
        if (keys.length == 1) throw StateError('lost');
        return {
          'fulfillment_id': 7,
          'order_status': 'READY_FOR_PICKUP',
          'completed': true,
        };
      },
    );
    await vm.selectInspection(true);
    ready(vm);
    expect(await vm.confirmReady(7), false);
    expect(await vm.confirmReady(7), true);
    expect(keys[0], keys[1]);
    expect(vm.saveError, isNull);
    vm.onDelete();
  });
  test('중복 클릭 차단과 종료 후 늦은 응답 폐기', () async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    final vm = PickupCandidatesVm(
      arrival: true,
      read: read,
      submit: (_, _) {
        calls++;
        return pending.future;
      },
    );
    await vm.selectInspection(true);
    ready(vm);
    final first = vm.confirmReady(7);
    expect(await vm.confirmReady(7), false);
    expect(calls, 1);
    vm.onDelete();
    pending.complete({
      'fulfillment_id': 7,
      'order_status': 'READY_FOR_PICKUP',
      'completed': true,
    });
    expect(await first, false);
  });
  test('미검수·다른 배송·수령 화면에서는 실행하지 않는다', () async {
    var calls = 0;
    final vm = PickupCandidatesVm(
      arrival: true,
      read: read,
      submit: (_, _) async {
        calls++;
        return {};
      },
    );
    await vm.selectInspection(true);
    expect(await vm.confirmReady(7), false);
    ready(vm);
    expect(await vm.confirmReady(8), false);
    vm.detail!['inspected_at'] = null;
    expect(await vm.confirmReady(7), false);
    expect(calls, 0);
    vm.onDelete();
  });
}
