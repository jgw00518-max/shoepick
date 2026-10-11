import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/model/staff_return.dart';
import 'package:shoepick_staff_app/vm/staff_return_vm.dart';

void main() {
  test('완료 실패 재시도 동일 키와 정상 완료 후 상세 갱신', () async {
    final keys = <String>[];
    final vm = StaffReturnVm(
      read: (path) async => path.endsWith('/7')
          ? {
              'data': {'return_request_id': 7, 'request_status': 'COMPLETED'},
            }
          : {
              'data': [],
              'pagination': {'page': 1, 'total_count': 0},
            },
      write: (path, body) async {
        expect(path, endsWith('/7/complete-mock'));
        expect(body['resale_confirmed'], true);
        keys.add(body['request_id'] as String);
        if (keys.length == 1) throw StateError('lost');
        return {
          'return_request_id': 7,
          'request_status': 'COMPLETED',
          'completed': true,
          'is_mock': true,
        };
      },
    );
    vm.detail = StaffReturn({
      'return_request_id': 7,
      'request_status': 'APPROVED',
    });
    expect(await vm.completeMock(7), false);
    expect(await vm.completeMock(7), true);
    expect(keys[0], keys[1]);
    expect(vm.detail!.data['request_status'], 'COMPLETED');
    expect(await vm.completeMock(7), false);
    vm.onDelete();
  });

  test('완료 응답 불일치는 성공으로 표시하지 않는다', () async {
    final vm = StaffReturnVm(
      read: (_) async => {},
      write: (_, _) async => {
        'return_request_id': 7,
        'request_status': 'APPROVED',
        'completed': false,
        'is_mock': true,
      },
    );
    vm.detail = StaffReturn({
      'return_request_id': 7,
      'request_status': 'APPROVED',
    });
    expect(await vm.completeMock(8), false);
    expect(await vm.completeMock(7), false);
    expect(vm.saveError, isNotNull);
    vm.onDelete();
  });
}
