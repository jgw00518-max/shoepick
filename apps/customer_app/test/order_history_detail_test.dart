import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/model/order_history.dart';
import 'package:shupick/view/order_history_detail.dart';
import 'package:shupick/vm/order_history_detail_vm.dart';

OrderHistory sample() => OrderHistory.fromJson({
  'order_id': 1,
  'order_number': 'C-TEST',
  'order_status': 'PAID',
  'paid_total': 2000,
  'branch_name': '테스트 대리점',
  'items': [
    {
      'product_name': '신발',
      'color_name': '검정',
      'size_mm': 270,
      'unit_price': 1000,
      'quantity': 2,
      'line_total': 2000,
    },
  ],
  'fulfillments': [
    {
      'fulfillment_status': 'IN_TRANSIT',
      'tracking_number': 'TRACK',
      'shipped_at': '2026-10-10T10:00:00',
    },
  ],
});

void main() {
  test('수령 완료와 구매확정은 원본 상태를 유지하며 시각으로 구분한다', () {
    final received = OrderHistory({'order_status': 'COMPLETED'});
    final confirmed = OrderHistory({
      'order_status': 'COMPLETED',
      'purchase_confirmed_at': 'RAW-TIME',
    });
    expect(received.statusLabel, '수령 완료');
    expect(received.canConfirmPurchase, isTrue);
    expect(confirmed.statusLabel, '구매확정');
    expect(confirmed.canConfirmPurchase, isFalse);
    expect(confirmed.status, 'COMPLETED');
  });
  test('구매확정 중복 요청과 종료 후 응답을 막는다', () async {
    final pending = Completer<void>();
    var calls = 0;
    final vm = OrderHistoryDetailVm(
      () async => OrderHistory({'order_status': 'COMPLETED'}),
      confirmPurchase: () {
        calls++;
        return pending.future;
      },
    );
    await vm.fetch();
    final result = vm.confirm();
    await vm.confirm();
    expect(calls, 1);
    vm.onDelete();
    pending.complete();
    await result;
    expect(vm.detail!.statusLabel, '수령 완료');
  });
  testWidgets('상세 조회 로딩과 상품·배송 정보 없음 표시', (tester) async {
    final pending = Completer<OrderHistory>();
    final vm = OrderHistoryDetailVm(() => pending.future);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderHistoryDetail(number: 'EMPTY', vm: vm),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(
      OrderHistory.fromJson({
        'order_id': 1,
        'order_number': 'EMPTY',
        'order_status': 'PAID',
        'paid_total': 0,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('상품 정보가 없습니다.'), findsOneWidget);
    expect(find.text('등록된 배송·수령 정보가 없습니다.'), findsOneWidget);
  });
  test('알려진 상태는 표시하고 알 수 없는 값은 그대로 보존한다', () {
    expect(sample().statusLabel, '결제 완료');
    final unknown = OrderHistory({'order_status': 'NEW_STATUS'});
    expect(unknown.statusLabel, contains('NEW_STATUS'));
    expect(unknown.status, 'NEW_STATUS');
  });

  test('중복 요청과 종료 후 늦은 결과를 막는다', () async {
    final pending = Completer<OrderHistory>();
    var calls = 0;
    final vm = OrderHistoryDetailVm(() {
      calls++;
      return pending.future;
    });
    final request = vm.fetch();
    await vm.fetch();
    expect(calls, 1);
    vm.onDelete();
    pending.complete(sample());
    await request;
    expect(vm.detail, isNull);
  });

  testWidgets('상세 오류를 재시도한 뒤 상품·금액·배송을 표시한다', (tester) async {
    var calls = 0;
    final vm = OrderHistoryDetailVm(() async {
      if (++calls == 1) throw StateError('offline');
      return sample();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderHistoryDetail(number: 'C-TEST', vm: vm),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('주문 상세를 불러오지 못했습니다.'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('주문 상태: 결제 완료'), findsOneWidget);
    expect(find.text('단가: 1000원'), findsOneWidget);
    expect(find.text('항목 금액: 2000원'), findsOneWidget);
    expect(find.text('결제 금액: 2000원'), findsOneWidget);
    expect(find.text('배송 상태: 배송 중'), findsOneWidget);
    expect(find.text('출고 시각 (서버 기록): 2026-10-10T10:00:00'), findsOneWidget);
  });
}
