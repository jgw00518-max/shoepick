import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/view/pickup_candidates_view.dart';
import 'package:shoepick_staff_app/vm/pickup_candidates_vm.dart';

Map<String, dynamic> data(String number) => {
  'data': number.isEmpty
      ? []
      : [
          {
            'order_number': number,
            'branch_name': 'BRANCH',
            'shipped_at': 'RAW',
          },
        ],
  'pagination': {'page': 1, 'total_count': number.isEmpty ? 0 : 1},
};
void main() {
  testWidgets('지점 변경은 이전 목록과 늦은 응답을 제거한다', (tester) async {
    final old = Completer<Map<String, dynamic>>();
    final paths = <String>[];
    Future<Map<String, dynamic>> read(String path) {
      paths.add(path);
      return path.contains('branch_id=3')
          ? old.future
          : Future.value(data('NEW-BRANCH'));
    }

    Widget page(int branch) => MaterialApp(
      home: Scaffold(
        body: PickupCandidatesView(
          key: ValueKey(branch),
          arrival: true,
          branchId: branch,
          read: read,
        ),
      ),
    );
    await tester.pumpWidget(page(3));
    await tester.pump();
    await tester.pumpWidget(page(4));
    await tester.pumpAndSettle();
    expect(find.text('NEW-BRANCH'), findsOneWidget);
    old.complete(data('OLD-BRANCH'));
    await tester.pumpAndSettle();
    expect(find.text('OLD-BRANCH'), findsNothing);
    expect(paths.length, 2);
  });

  testWidgets('입고·수령 상세는 실행 요청을 제공하지 않는다', (tester) async {
    for (final arrival in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PickupCandidatesView(
              key: ValueKey(arrival),
              arrival: arrival,
              read: (path) async => path.endsWith('/7')
                  ? {
                      'data': {'order_number': 'DETAIL', 'items': []},
                    }
                  : {
                      'data': [
                        {
                          'fulfillment_id': 7,
                          'pickup_id': 7,
                          'order_number': 'ORDER',
                        },
                      ],
                      'pagination': {'page': 1, 'total_count': 1},
                    },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ORDER'));
      await tester.pumpAndSettle();
      final label = arrival ? '입고 실행 준비 중' : '수령 인증·완료 준비 중';
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, label))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
    }
  });
  test('상세 중복 요청·닫힘 후 응답 폐기', () async {
    final task = Completer<Map<String, dynamic>>();
    var calls = 0;
    final vm = PickupCandidatesVm(
      read: (_) {
        calls++;
        return task.future;
      },
      arrival: true,
    );
    final result = vm.fetchDetail(1);
    await vm.fetchDetail(1);
    expect(calls, 1);
    vm.closeDetail();
    task.complete({
      'data': {'order_number': 'OLD'},
    });
    await result;
    expect(vm.detail, isNull);
  });
  testWidgets('상품 상세에서 주문 스냅샷과 배송 수량 표시', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickupCandidatesView(
            arrival: true,
            read: (path) async {
              if (path.endsWith('/7')) {
                return {
                  'data': {
                    'order_number': 'DETAIL',
                    'branch_name': 'BRANCH',
                    'items': [
                      {
                        'product_name': 'SHOE',
                        'product_code': 'CODE',
                        'color_name': 'BLACK',
                        'size_mm': 270,
                        'quantity': 2,
                        'unit_price': 1000,
                        'line_total': 2000,
                      },
                    ],
                  },
                };
              }
              return {
                'data': [
                  {
                    'fulfillment_id': 7,
                    'order_number': 'ORDER',
                    'branch_name': 'BRANCH',
                  },
                ],
                'pagination': {'page': 1, 'total_count': 1},
              };
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ORDER'));
    await tester.pumpAndSettle();
    expect(find.text('SHOE · CODE'), findsOneWidget);
    expect(find.text('배송 수량: 2'), findsOneWidget);
    expect(find.text('옵션: BLACK / 270'), findsOneWidget);
  });
  test('중복 조회와 종료 후 늦은 응답 방지', () async {
    final task = Completer<Map<String, dynamic>>();
    var calls = 0;
    final vm = PickupCandidatesVm(
      read: (_) {
        calls++;
        return task.future;
      },
      arrival: true,
      branchId: 3,
    );
    final result = vm.fetch();
    await vm.fetch();
    expect(calls, 1);
    vm.onDelete();
    task.complete(data('OLD'));
    await result;
    expect(vm.rows, isEmpty);
  });
  testWidgets('입고 목록 오류·재시도·실행 없음', (tester) async {
    var fail = true;
    final paths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickupCandidatesView(
            arrival: true,
            branchId: 3,
            read: (path) async {
              paths.add(path);
              if (fail) {
                fail = false;
                throw StateError('FAIL');
              }
              return data('ORDER');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('FAIL'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('ORDER'), findsOneWidget);
    expect(find.text('실행 준비 중'), findsOneWidget);
    expect(paths.last, contains('branch_id=3'));
    expect(paths.last, contains('arrival-candidates'));
  });
  testWidgets('수령 목록 빈 결과', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickupCandidatesView(
            arrival: false,
            read: (path) async {
              expect(path, contains('pickup-candidates'));
              return data('');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('대상 주문이 없습니다.'), findsOneWidget);
  });
}
