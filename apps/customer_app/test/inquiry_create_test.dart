import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/vm/inquiry_create_vm.dart';

void main() {
  test('중복 요청 차단과 실패 재전송 ID 유지', () async {
    final pending = Completer<Map<String, dynamic>>();
    final sent = <Map<String, dynamic>>[];
    final vm = InquiryCreateVm(
      send: (data) {
        sent.add(data);
        return sent.length == 1
            ? pending.future
            : Future.value({
                'data': {'inquiry_id': 1},
              });
      },
    );
    final body = {
      'title': 'test',
      'inquiry_type': 'OTHER',
      'inquiry_content': 'body',
      'product_id': null,
    };
    final first = vm.submit(body);
    expect(await vm.submit(body), isFalse);
    pending.completeError(StateError('unknown result'));
    expect(await first, isFalse);
    expect(await vm.submit({...body, 'title': 'changed'}), isFalse);
    expect(await vm.submit(body), isTrue);
    expect(sent[0]['request_id'], sent[1]['request_id']);
  });
  test('종료 후 응답은 성공으로 처리하지 않는다', () async {
    final task = Completer<Map<String, dynamic>>();
    final vm = InquiryCreateVm(send: (_) => task.future);
    final result = vm.submit({'title': 'test'});
    vm.onDelete();
    task.complete({
      'data': {'inquiry_id': 1},
    });
    expect(await result, isFalse);
  });
}
