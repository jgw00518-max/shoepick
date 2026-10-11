import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/model/order_after_sales.dart';
import 'package:shupick/model/order_history.dart';
import 'package:shupick/vm/order_history_detail_vm.dart';
import 'package:shupick/view/order_history_detail.dart';

void main() {
  testWidgets('환불 상태와 완료 시각을 실제 기록대로 구분한다', (tester) async {
    final vm = OrderHistoryDetailVm(
      () async => OrderHistory({
        'order_id': 1,
        'order_number': 'ORDER',
        'order_status': 'COMPLETED',
        'paid_total': 1000,
      }),
      loadAfterSales: () async => OrderAfterSales.fromJson({
        'return_requests': [],
        'refunds': [
          {
            'refund_status': 'SUCCEEDED',
            'refund_amount': 1000,
            'completed_at': 'RAW-COMPLETE',
          },
          {
            'refund_status': 'FAILED',
            'refund_amount': 1000,
            'failed_at': 'RAW-FAILED',
          },
          {'refund_status': 'NEW', 'refund_amount': 1000},
        ],
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OrderHistoryDetail(number: 'ORDER', vm: vm),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('환불 완료'), findsOneWidget);
    expect(find.text('환불 실패'), findsOneWidget);
    expect(find.text('환불 완료 시각 (서버 기록): RAW-COMPLETE'), findsOneWidget);
    expect(find.text('환불 실패 시각 (서버 기록): RAW-FAILED'), findsOneWidget);
    expect(find.text('확인되지 않은 상태'), findsOneWidget);
  });
  test('응답 유실 반품은 구매확정을 차단하고 늦은 접수 성공을 버린다', () async {
    var confirmations = 0;
    final pending = Completer<void>();
    final vm = OrderHistoryDetailVm(
      () async => OrderHistory({'order_status': 'COMPLETED'}),
      confirmPurchase: () async {
        confirmations++;
      },
      createReturn: (_) => pending.future,
    );
    await vm.fetch();
    final request = vm.submitReturn('OTHER', 'reason');
    pending.completeError(StateError('test'));
    await request;
    expect(vm.returnResultUncertain, isTrue);
    expect(vm.canConfirm, isFalse);
    await vm.confirm();
    expect(confirmations, 0);
    vm.onDelete();
    final late = Completer<void>();
    final closed = OrderHistoryDetailVm(
      () async => OrderHistory({'order_status': 'COMPLETED'}),
      createReturn: (_) => late.future,
    );
    await closed.fetch();
    final lateRequest = closed.submitReturn('OTHER', 'reason');
    closed.onDelete();
    late.complete();
    await lateRequest;
    expect(closed.returnSubmitted, isFalse);
  });

  test('처리내역 확인 전에는 구매확정과 반품을 허용하지 않는다', () async {
    final vm = OrderHistoryDetailVm(
      () async => OrderHistory({'order_status': 'COMPLETED'}),
      loadAfterSales: () async =>
          OrderAfterSales.fromJson({'return_requests': [], 'refunds': []}),
      confirmPurchase: () async {},
      createReturn: (_) async {},
    );
    await vm.fetch();
    expect(vm.canConfirm, isFalse);
    expect(vm.canReturn, isFalse);
    await vm.fetchAfterSales();
    expect(vm.canConfirm, isTrue);
    expect(vm.canReturn, isTrue);
    vm.onDelete();
  });
  test('최종 승인 표시는 환불 완료와 구분한다', () {
    expect(OrderAfterSales.returnLabel('APPROVED'), '반품 최종 승인 · 환불 대기');
    expect(OrderAfterSales.refundLabel('PROCESSING'), '환불 진행 중');
  });
  test('전체 반품 중복 요청·동일 키 재시도·구매확정 차단', () async {
    final pending = Completer<void>();
    final bodies = <Map<String, dynamic>>[];
    var confirmCalls = 0;
    final vm = OrderHistoryDetailVm(
      () async => OrderHistory({'order_status': 'COMPLETED'}),
      createReturn: (body) {
        bodies.add(Map.from(body));
        return bodies.length == 1 ? pending.future : Future.value();
      },
      confirmPurchase: () async {
        confirmCalls++;
      },
    );
    await vm.fetch();
    final first = vm.submitReturn('OTHER', '사유');
    await vm.submitReturn('OTHER', '사유');
    await vm.confirm();
    expect(bodies.length, 1);
    expect(confirmCalls, 0);
    pending.completeError(StateError('test'));
    await first;
    await vm.submitReturn('OTHER', '변경');
    expect(bodies.length, 1);
    await vm.submitReturn('OTHER', '사유');
    expect(bodies[1]['request_id'], bodies[0]['request_id']);
    expect(vm.returnSubmitted, isTrue);
    await vm.confirm();
    expect(confirmCalls, 0);
    vm.onDelete();
  });

  test('중복 조회와 종료 후 늦은 응답을 차단한다', () async {
    final pending = Completer<OrderAfterSales>();
    var calls = 0;
    final vm = OrderHistoryDetailVm(
      () async => OrderHistory({}),
      loadAfterSales: () {
        calls++;
        return pending.future;
      },
    );
    final request = vm.fetchAfterSales();
    await vm.fetchAfterSales();
    expect(calls, 1);
    expect(vm.afterSalesLoading, isTrue);
    vm.onDelete();
    pending.complete(
      OrderAfterSales.fromJson({'return_requests': [], 'refunds': []}),
    );
    await request;
    expect(vm.afterSales, isNull);
  });

  testWidgets('실패·재시도·실제 기록·빈 결과를 표시한다', (tester) async {
    var calls = 0;
    final vm = OrderHistoryDetailVm(
      () async => OrderHistory({
        'order_id': 1,
        'order_number': 'ORDER',
        'order_status': 'PAID',
        'paid_total': 59000,
      }),
      loadAfterSales: () async {
        calls++;
        if (calls == 1) throw StateError('test');
        return OrderAfterSales.fromJson({
          'return_requests': calls == 2
              ? [
                  {'request_status': 'REQUESTED', 'return_reason': '크기 불일치'},
                ]
              : [],
          'refunds': calls == 2
              ? [
                  {
                    'refund_status': 'PROCESSING',
                    'refund_amount': 59000,
                    'requested_at': 'RAW-TIME',
                  },
                ]
              : [],
        });
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OrderHistoryDetail(number: 'ORDER', vm: vm),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('처리내역 다시 시도'), findsOneWidget);
    await tester.tap(find.text('처리내역 다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('반품 접수'), findsOneWidget);
    expect(find.text('환불 진행 중'), findsOneWidget);
    expect(find.text('환불 금액: 59000원'), findsOneWidget);
    expect(find.text('접수 시각 (서버 기록): RAW-TIME'), findsOneWidget);
    expect(find.text('환불 완료'), findsNothing);
    await vm.fetchAfterSales();
    await tester.pumpAndSettle();
    expect(find.text('반품·환불 처리내역이 없습니다.'), findsOneWidget);
  });

  test('알 수 없는 상태를 성공으로 해석하지 않는다', () {
    expect(OrderAfterSales.refundLabel('NEW'), '확인되지 않은 상태');
    expect(OrderAfterSales.returnLabel(null), '확인되지 않은 상태');
    expect(OrderAfterSales.refundLabel('SUCCEEDED'), '환불 완료');
  });
}
