import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/vm/staff_return_vm.dart';
import 'package:shoepick_staff_app/view/staff_return_view.dart';

Map<String, dynamic> list(int page) => {
  'data': [
    {
      'return_request_id': 2,
      'order_number': 'ORDER',
      'branch_name': 'BRANCH',
      'request_status': 'REQUESTED',
    },
  ],
  'pagination': {'page': page, 'total_count': 21},
};
void main() {
  test('화면 종료 후 늦은 최종 결정은 상태와 조회에 반영하지 않는다', () async {
    final pending = Completer<Map<String, dynamic>>();
    var reads = 0;
    final vm = StaffReturnVm(
      read: (_) async {
        reads++;
        return list(1);
      },
      write: (_, body) => pending.future,
    );
    final task = vm.saveDecision(2, 'APPROVED', null);
    vm.onDelete();
    pending.complete({'return_request_id': 2});
    expect(await task, isFalse);
    expect(reads, 0);
  });
  test('최종 결정 중복·반대 결정 재시도 차단·동일 키 보존', () async {
    final pending = Completer<Map<String, dynamic>>();
    final bodies = <Map<String, dynamic>>[];
    final vm = StaffReturnVm(
      read: (_) async => list(1),
      write: (path, body) {
        expect(path, endsWith('/decision'));
        bodies.add(Map.from(body));
        return bodies.length == 1
            ? pending.future
            : Future.value({
                'return_request_id': 2,
                'request_status': 'APPROVED',
              });
      },
    );
    final first = vm.saveDecision(2, 'APPROVED', null);
    await vm.saveDecision(2, 'APPROVED', null);
    expect(bodies.length, 1);
    pending.completeError(StateError('test'));
    await first;
    await vm.saveDecision(2, 'REJECTED', 'reason');
    expect(bodies.length, 1);
    expect(await vm.saveDecision(2, 'APPROVED', null), isTrue);
    expect(bodies[0]['request_id'], bodies[1]['request_id']);
    vm.onDelete();
  });

  testWidgets('본사 검수 후 거절 사유 필수·결정 전송', (tester) async {
    Map<String, dynamic>? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffReturnView(
            read: (path) async => path.endsWith('/2')
                ? {
                    'data': {
                      'return_request_id': 2,
                      'order_number': 'ORDER',
                      'request_status': 'INSPECTING',
                      'inspections': [
                        {
                          'inspection_stage': 'HEADQUARTERS',
                          'inspection_decision': 'PENDING',
                        },
                      ],
                    },
                  }
                : list(1),
            write: (path, body) async {
              sent = body;
              return {'return_request_id': 2, 'request_status': 'REJECTED'};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ORDER'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('최종 승인·거절 (본사 사원 전용)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('최종 승인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('거절').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '결정 저장'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextFormField), 'reason');
    await tester.pump();
    await tester.tap(find.text('결정 저장'));
    await tester.pumpAndSettle();
    expect(sent?['decision'], 'REJECTED');
    expect(sent?['rejection_reason'], 'reason');
  });
  test('검수 저장 중복 방지·응답 유실 동일 키 재시도', () async {
    final pending = Completer<Map<String, dynamic>>();
    final bodies = <Map<String, dynamic>>[];
    final vm = StaffReturnVm(
      read: (_) async => list(1),
      write: (path, body) {
        bodies.add(Map.from(body));
        return bodies.length == 1
            ? pending.future
            : Future.value({'after_sales_inspection_id': 9});
      },
    );
    final body = <String, dynamic>{
      'inspection_stage': 'BRANCH',
      'inspection_notes': 'test',
    };
    final first = vm.saveInspection(2, body);
    await vm.saveInspection(2, body);
    expect(bodies.length, 1);
    pending.completeError(StateError('test'));
    await first;
    expect(vm.saveError, isNotNull);
    await vm.saveInspection(2, {...body, 'inspection_notes': 'changed'});
    expect(bodies.length, 1);
    vm.closeDetail();
    expect(await vm.saveInspection(2, body), isTrue);
    expect(bodies[0]['request_id'], bodies[1]['request_id']);
    vm.onDelete();
  });
  test('목록 중복·종료 후 응답 차단과 지점 전달', () async {
    final pending = Completer<Map<String, dynamic>>();
    final paths = <String>[];
    final vm = StaffReturnVm(
      branchId: 3,
      read: (path) {
        paths.add(path);
        return pending.future;
      },
    );
    final task = vm.fetch();
    await vm.fetch();
    expect(paths.length, 1);
    expect(paths.single, contains('branch_id=3'));
    vm.onDelete();
    pending.complete(list(1));
    await task;
    expect(vm.rows, isEmpty);
  });
  test('상세 닫힘 후 응답 무시', () async {
    final pending = Completer<Map<String, dynamic>>();
    final vm = StaffReturnVm(read: (_) => pending.future);
    final task = vm.fetchDetail(2);
    await vm.fetchDetail(2);
    vm.closeDetail();
    pending.complete({
      'data': {'return_request_id': 2},
    });
    await task;
    expect(vm.detail, isNull);
    vm.onDelete();
  });
  testWidgets('목록 실패·재시도·페이지·상세와 빈 결과', (tester) async {
    var count = 0;
    final paths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffReturnView(
            read: (path) async {
              paths.add(path);
              count++;
              if (count == 1) throw StateError('test');
              if (path.endsWith('/2')) {
                return {
                  'data': {
                    'return_request_id': 2,
                    'order_number': 'ORDER',
                    'request_status': 'REQUESTED',
                    'return_reason': 'REASON',
                    'items': [
                      {
                        'product_name': 'SHOE',
                        'color_name': 'BLACK',
                        'size_mm': 270,
                        'quantity': 2,
                      },
                    ],
                    'inspections': [],
                    'refunds': [
                      {'refund_status': 'PROCESSING', 'refund_amount': 1000},
                    ],
                  },
                };
              }
              if (path.contains('page=2')) {
                return {
                  'data': [],
                  'pagination': {'page': 2, 'total_count': 21},
                };
              }
              return list(1);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('ORDER'), findsOneWidget);
    await tester.tap(find.text('ORDER'));
    await tester.pumpAndSettle();
    expect(find.text('사유: REASON'), findsOneWidget);
    expect(find.text('환불 진행 중 · 1000원'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(find.text('반품 접수가 없습니다.'), findsOneWidget);
    expect(paths.last, contains('page=2'));
  });
}
