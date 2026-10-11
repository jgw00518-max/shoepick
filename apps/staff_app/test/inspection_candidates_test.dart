import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/view/pickup_candidates_view.dart';
import 'package:shoepick_staff_app/vm/pickup_candidates_vm.dart';

Map<String, dynamic> list(String number) => {
  'data': [
    {'fulfillment_id': 7, 'order_number': number, 'arrived_at': 'RAW'},
  ],
  'pagination': {'page': 1, 'total_count': 1},
};

void main() {
  test('단계 전환은 이전 목록과 상세 응답을 폐기한다', () async {
    final oldList = Completer<Map<String, dynamic>>();
    final oldDetail = Completer<Map<String, dynamic>>();
    final vm = PickupCandidatesVm(
      arrival: true,
      branchId: 3,
      read: (path) {
        if (path.endsWith('/7')) return oldDetail.future;
        if (path.contains('stage=inspection')) return Future.value(list('NEW'));
        return oldList.future;
      },
    );
    final pendingList = vm.fetch();
    final pendingDetail = vm.fetchDetail(7);
    await vm.selectInspection(true);
    expect(vm.rows.single.number, 'NEW');
    expect(vm.rows.single.time, 'RAW');
    oldList.complete(list('OLD'));
    oldDetail.complete({
      'data': {'order_number': 'OLD'},
    });
    await Future.wait([pendingList, pendingDetail]);
    expect(vm.rows.single.number, 'NEW');
    expect(vm.detail, isNull);
    expect(vm.loading, isFalse);
    vm.onDelete();
  });

  testWidgets('검수 대기 상세는 전용 조회만 사용하고 도착 실행을 제공하지 않는다', (tester) async {
    final paths = <String>[];
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickupCandidatesView(
            arrival: true,
            read: (path) async {
              paths.add(path);
              return path.endsWith('/7')
                  ? {
                      'data': {'order_number': 'DETAIL', 'items': []},
                    }
                  : list('ORDER');
            },
            submit: (_, _) async {
              writes++;
              return {};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('검수 대기'));
    await tester.pumpAndSettle();
    expect(paths.last, contains('stage=inspection'));
    await tester.tap(find.text('ORDER'));
    await tester.pumpAndSettle();
    expect(paths.last, endsWith('inspection-candidates/7'));
    expect(find.text('도착 확인'), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '검수·보관 연결 준비 중'))
          .onPressed,
      isNull,
    );
    expect(writes, 0);
  });
}
