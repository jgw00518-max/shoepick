import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/view/pickup_candidates_view.dart';

void main() {
  for (final execute in [true, false]) {
    testWidgets(execute ? '준비 완료 확인 후 요청·목록 갱신' : '확인 취소는 요청 없이 상세 유지', (
      tester,
    ) async {
      var completed = false;
      var posts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PickupCandidatesView(
              arrival: true,
              read: (path) async => path.endsWith('/7')
                  ? {
                      'data': {
                        'fulfillment_id': 7,
                        'order_number': 'ORDER',
                        'fulfillment_status': 'INSPECTING',
                        'inspected_at': 'RAW',
                        'items': [],
                      },
                    }
                  : {
                      'data': completed
                          ? []
                          : [
                              {
                                'fulfillment_id': 7,
                                'order_number': 'ORDER',
                                'inspected_at': 'RAW',
                              },
                            ],
                      'pagination': {
                        'page': 1,
                        'total_count': completed ? 0 : 1,
                      },
                    },
              submit: (path, body) async {
                posts++;
                expect(path, endsWith('/7/ready'));
                expect(body['confirmed'], true);
                expect(body['request_id'], isNotEmpty);
                completed = true;
                return {
                  'fulfillment_id': 7,
                  'order_status': 'READY_FOR_PICKUP',
                  'completed': true,
                };
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('검수 대기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ORDER'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '수령 준비 완료'));
      await tester.pumpAndSettle();
      expect(find.text('수령 준비 완료 확인'), findsOneWidget);
      if (execute) {
        await tester.tap(find.text('준비 완료 확인'));
        await tester.pumpAndSettle();
        expect(posts, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('대상 주문이 없습니다.'), findsOneWidget);
      } else {
        await tester.tap(find.text('닫기').last);
        await tester.pumpAndSettle();
        expect(posts, 0);
        expect(find.widgetWithText(FilledButton, '수령 준비 완료'), findsOneWidget);
      }
    });
  }

  testWidgets('조회 전용 상세에는 준비 실행 버튼 없음', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickupCandidatesView(
            arrival: true,
            read: (path) async => path.endsWith('/7')
                ? {
                    'data': {
                      'fulfillment_id': 7,
                      'fulfillment_status': 'INSPECTING',
                      'inspected_at': 'RAW',
                      'items': [],
                    },
                  }
                : {
                    'data': [
                      {'fulfillment_id': 7, 'order_number': 'ORDER'},
                    ],
                    'pagination': {'page': 1, 'total_count': 1},
                  },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('검수 대기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ORDER'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '수령 준비 완료'), findsNothing);
  });
}
