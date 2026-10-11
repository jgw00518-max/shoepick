import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/view/inquiry_history_view.dart';
import 'package:shupick/vm/inquiry_history_vm.dart';

Map<String, dynamic> listResult() => {
  'data': [
    {
      'inquiry_id': 1,
      'title': 'QUESTION',
      'inquiry_status': 'OPEN',
      'created_at': '2026-10-11',
    },
  ],
  'pagination': {'page': 1, 'total_count': 1},
};
void main() {
  test('duplicate and late detail responses are ignored', () async {
    final task = Completer<Map<String, dynamic>>();
    var calls = 0;
    final vm = InquiryHistoryVm(
      request: (_) {
        calls++;
        return task.future;
      },
    );
    final first = vm.fetchDetail(1);
    await vm.fetchDetail(1);
    expect(calls, 1);
    vm.closeDetail();
    task.complete({
      'data': {'inquiry_id': 1, 'title': 'LATE'},
    });
    await first;
    expect(vm.detail, isNull);
    final pending = Completer<Map<String, dynamic>>();
    final other = InquiryHistoryVm(request: (_) => pending.future);
    final load = other.fetch();
    other.onDelete();
    pending.complete(listResult());
    await load;
    expect(other.inquiries, isEmpty);
  });
  testWidgets('list detail answer and retry display', (tester) async {
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InquiryHistoryView(
            request: (path) async {
              if (fail) {
                fail = false;
                throw StateError('FAIL');
              }
              if (path.endsWith('/1')) {
                return {
                  'data': {
                    'inquiry_id': 1,
                    'title': 'QUESTION',
                    'inquiry_status': 'ANSWERED',
                    'inquiry_content': 'BODY',
                    'inquiry_type': 'TYPE',
                    'created_at': 'RAW',
                    'responses': [
                      {
                        'response_content': 'ANSWER',
                        'responded_at': 'RAW-TIME',
                      },
                    ],
                  },
                };
              }
              return listResult();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('FAIL'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QUESTION'));
    await tester.pumpAndSettle();
    expect(find.text('BODY'), findsOneWidget);
    expect(find.text('ANSWER'), findsOneWidget);
    expect(find.text('RAW-TIME'), findsOneWidget);
  });
}
