import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shupick/view/order_history_view.dart';
import 'package:shupick/vm/auth_api.dart';
import 'package:shupick/vm/order_history_vm.dart';

class FakeAuth extends Fake implements FirebaseAuth {}

class ControlledApi extends AuthApi {
  ControlledApi() : super(auth: FakeAuth());
  final calls = <String>[];
  final pending = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> getResponse(String path) {
    calls.add(path);
    final task = Completer<Map<String, dynamic>>();
    pending.add(task);
    return task.future;
  }
}

Map<String, dynamic> response({bool empty = false}) => {
  'data': empty
      ? []
      : [
          {
            'order_id': 1,
            'order_number': 'C-1',
            'order_status': 'PAID',
            'paid_total': 1000,
          },
        ],
  'pagination': {'total_count': empty ? 0 : 21},
};
void main() {
  tearDown(Get.reset);
  testWidgets('목록 로딩·정상 표시·페이지·실패·재시도·빈 결과', (tester) async {
    final api = ControlledApi();
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(body: OrderHistoryView(api: api)),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    api.pending[0].complete(response());
    await tester.pumpAndSettle();
    expect(find.text('C-1'), findsOneWidget);
    expect(find.textContaining('결제 완료'), findsOneWidget);
    await tester.tap(find.text('다음'));
    await tester.pump();
    expect(api.calls.last, contains('page=2'));
    api.pending[1].completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('C-1'), findsNothing);
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    api.pending[2].complete(response(empty: true));
    await tester.pumpAndSettle();
    expect(find.text('구매 내역이 없습니다.'), findsOneWidget);
  });
  test('목록 중복 요청과 종료 후 응답 반영 차단', () async {
    final api = ControlledApi();
    final vm = OrderHistoryVm(api: api);
    final first = vm.fetchOrders();
    await vm.fetchOrders();
    expect(api.calls.length, 1);
    vm.onDelete();
    api.pending.single.complete(response());
    await first;
    expect(vm.orders, isEmpty);
  });
}
