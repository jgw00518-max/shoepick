import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/view/staff_inquiry_view.dart';
import 'package:shoepick_staff_app/vm/staff_inquiry_vm.dart';

Map<String, dynamic> listData() => {
  'data': [
    {
      'inquiry_id': 1,
      'title': 'Q',
      'inquiry_status': 'OPEN',
      'created_at': 'RAW',
    },
  ],
  'pagination': {'page': 1, 'total_count': 1},
};
void main() {
  test('답변 중복과 실패 재전송 ID 유지', () async {
    final task = Completer<Map<String, dynamic>>();
    final sent = <Map<String, dynamic>>[];
    final vm = StaffInquiryVm(
      read: (_) async => listData(),
      write: (_, data) {
        sent.add(data);
        return sent.length == 1
            ? task.future
            : Future.value({'inquiry_response_id': 1});
      },
    );
    final first = vm.answer(1, 'answer');
    expect(await vm.answer(1, 'answer'), isFalse);
    task.completeError(StateError('fail'));
    expect(await first, isFalse);
    expect(await vm.answer(1, 'answer'), isTrue);
    expect(sent[0]['request_id'], sent[1]['request_id']);
  });
  testWidgets('목록·상세·첫 답변 등록', (tester) async {
    var answered = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffInquiryView(
            read: (path) async {
              if (path.endsWith('/1')) {
                return {
                  'data': {
                    'inquiry_id': 1,
                    'title': 'Q',
                    'inquiry_status': answered ? 'ANSWERED' : 'OPEN',
                    'inquiry_content': 'BODY',
                    'responses': answered
                        ? [
                            {
                              'response_content': 'ANSWER',
                              'responded_at': 'RAW',
                            },
                          ]
                        : [],
                  },
                };
              }
              return listData();
            },
            write: (path, body) async {
              answered = true;
              expect(body['response_content'], 'ANSWER');
              return {'inquiry_response_id': 1};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Q'));
    await tester.pumpAndSettle();
    expect(find.text('BODY'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ANSWER');
    await tester.tap(find.text('답변 등록'));
    await tester.pumpAndSettle();
    expect(find.text('ANSWER'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
  test('화면 종료 후 상세 응답 무시', () async {
    final task = Completer<Map<String, dynamic>>();
    final vm = StaffInquiryVm(read: (_) => task.future);
    final result = vm.loadDetail(1);
    vm.onDelete();
    task.complete({
      'data': {'title': 'OLD'},
    });
    await result;
    expect(vm.detail, isNull);
  });
}
