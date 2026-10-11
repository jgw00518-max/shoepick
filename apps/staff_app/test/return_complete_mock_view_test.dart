import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/view/staff_return_view.dart';

void main() {
  for (final outcome in ['success', 'cancel', 'failure']) {
    testWidgets('모의 반품 완료 화면: $outcome', (tester) async {
      var completed = false;
      var posts = 0;
      Map<String, dynamic> row() => {
        'return_request_id': 7,
        'order_number': 'ORDER',
        'request_status': completed ? 'COMPLETED' : 'APPROVED',
        'refunds': completed
            ? [
                {'refund_status': 'SUCCEEDED', 'refund_amount': 59000},
              ]
            : [],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffReturnView(
              read: (path) async => path.endsWith('/7')
                  ? {'data': row()}
                  : {
                      'data': [row()],
                      'pagination': {'page': 1, 'total_count': 1},
                    },
              write: (path, body) async {
                posts++;
                expect(path, endsWith('/7/complete-mock'));
                expect(body['resale_confirmed'], true);
                if (outcome == 'failure') throw StateError('server rejected');
                completed = true;
                return {
                  'return_request_id': 7,
                  'request_status': 'COMPLETED',
                  'completed': true,
                  'is_mock': true,
                };
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ORDER'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '정상 반품 모의 환불 완료'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      expect(find.text('정상 반품 모의 환불 완료'), findsNWidgets(2));
      await tester.tap(
        find.text(outcome == 'cancel' ? '취소' : '회수·재판매 확인 후 처리'),
      );
      await tester.pumpAndSettle();
      if (outcome == 'success') {
        expect(posts, 1);
        expect(find.text('환불 완료 · 59000원'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, '정상 반품 모의 환불 완료'),
          findsNothing,
        );
      } else {
        expect(posts, outcome == 'cancel' ? 0 : 1);
        expect(
          find.widgetWithText(FilledButton, '정상 반품 모의 환불 완료'),
          findsOneWidget,
        );
        expect(find.text('환불 완료 · 59000원'), findsNothing);
        if (outcome == 'failure') {
          expect(
            find.text('저장 결과를 확인하지 못했습니다. 같은 내용으로 재시도해주세요.'),
            findsOneWidget,
          );
        }
      }
    });
  }
}
