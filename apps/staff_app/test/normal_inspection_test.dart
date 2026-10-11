import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/vm/pickup_candidates_vm.dart';

void main() {
  test('검수 실패 재시도는 같은 요청 키를 사용하고 도착 실행과 구분한다', () async {
    final keys = <String>[];
    final vm = PickupCandidatesVm(
      arrival: true,
      read: (_) async => {
        'data': [],
        'pagination': {'page': 1, 'total_count': 0},
      },
      submit: (path, body) async {
        expect(path, endsWith('/inspection'));
        expect(body['all_items_normal'], true);
        keys.add(body['request_id'] as String);
        if (keys.length == 1) throw StateError('lost response');
        return {'fulfillment_id': 7, 'fulfillment_status': 'INSPECTING'};
      },
    );
    await vm.selectInspection(true);
    vm.detail = {'fulfillment_status': 'ARRIVED'};
    expect(await vm.confirmInspection(7), false);
    expect(await vm.confirmInspection(7), true);
    expect(keys[0], keys[1]);
    expect(await vm.confirmArrival(7), false);
    vm.onDelete();
  });

  test('이미 검수 기록이 있는 배송과 다른 단계는 저장하지 않는다', () async {
    var calls = 0;
    final vm = PickupCandidatesVm(
      arrival: true,
      read: (_) async => {
        'data': [],
        'pagination': {'page': 1, 'total_count': 0},
      },
      submit: (_, _) async {
        calls++;
        return {};
      },
    );
    expect(await vm.confirmInspection(7), false);
    await vm.selectInspection(true);
    vm.detail = {'fulfillment_status': 'INSPECTING'};
    expect(await vm.confirmInspection(7), false);
    expect(calls, 0);
    vm.onDelete();
  });
}
