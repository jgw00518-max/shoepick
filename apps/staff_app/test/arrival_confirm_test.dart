import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/vm/pickup_candidates_vm.dart';

void main() {
  Future<Map<String, dynamic>> read(String _) async => {
    'data': <dynamic>[],
    'pagination': {'page': 1, 'total_count': 0},
  };
  test('실패 재시도는 같은 키 유지하고 성공 후 목록 갱신', () async {
    final bodies = <Map<String, dynamic>>[];
    final vm = PickupCandidatesVm(
      read: read,
      arrival: true,
      submit: (path, body) async {
        bodies.add(body);
        if (bodies.length == 1) throw Exception('lost');
        return {'fulfillment_id': 7, 'fulfillment_status': 'ARRIVED'};
      },
    );
    expect(await vm.confirmArrival(7), isFalse);
    expect(await vm.confirmArrival(7), isTrue);
    expect(bodies[0], bodies[1]);
  });
  test('중복 클릭과 종료 후 늦은 응답 무시', () async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    final vm = PickupCandidatesVm(
      read: read,
      arrival: true,
      submit: (path, body) {
        calls++;
        return pending.future;
      },
    );
    final first = vm.confirmArrival(7);
    expect(await vm.confirmArrival(7), isFalse);
    expect(calls, 1);
    vm.onDelete();
    pending.complete({'fulfillment_id': 7, 'fulfillment_status': 'ARRIVED'});
    expect(await first, isFalse);
  });
  test('수령 화면은 도착 실행 금지', () async {
    var calls = 0;
    final vm = PickupCandidatesVm(
      read: read,
      arrival: false,
      submit: (path, body) async {
        calls++;
        return {};
      },
    );
    expect(await vm.confirmArrival(7), isFalse);
    expect(calls, 0);
  });
}
