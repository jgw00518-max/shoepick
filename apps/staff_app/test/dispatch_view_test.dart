import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/view/dispatch_view.dart';

Map<String, dynamic> result(String number, {int page = 1, int total = 21}) => {
  'data': number.isEmpty
      ? []
      : [
          {
            'order_id': 1,
            'order_number': number,
            'paid_total': 1000,
            'branch_name': '지점',
          },
        ],
  'pagination': {'page': page, 'total_count': total},
};
void main() {
  testWidgets('출고 준비 창은 중복으로 열리지 않고 실행과 추가 요청을 하지 않는다', (tester) async {
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DispatchView(
            request: (_) async {
              requests++;
              return result('REVIEW-1');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('출고 내용 확인'));
    await tester.tap(find.text('출고 내용 확인'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('주문 번호: REVIEW-1'), findsOneWidget);
    expect(find.text('수령 대리점: 지점'), findsOneWidget);
    expect(find.text('결제 금액: 1000원'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(requests, 1);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('출고 내용 확인'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(requests, 1);
  });

  testWidgets('출고 화면 로딩·정상·페이지·오류·재시도·빈 결과', (tester) async {
    final tasks = <Completer<Map<String, dynamic>>>[];
    final paths = <String>[];
    Future<Map<String, dynamic>> request(String path) {
      paths.add(path);
      final task = Completer<Map<String, dynamic>>();
      tasks.add(task);
      return task.future;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DispatchView(request: request, branchId: 3)),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    tasks[0].complete(result('STAFF-1'));
    await tester.pumpAndSettle();
    expect(find.text('STAFF-1'), findsOneWidget);
    await tester.tap(find.text('다음'));
    await tester.pump();
    expect(paths.last, contains('page=2'));
    tasks[1].completeError(StateError('출고 조회 연동을 준비 중입니다.'));
    await tester.pumpAndSettle();
    expect(find.text('STAFF-1'), findsNothing);
    expect(find.text('출고 조회 연동을 준비 중입니다.'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    tasks[2].complete(result('', total: 0));
    await tester.pumpAndSettle();
    expect(find.text('출고 대상 주문이 없습니다.'), findsOneWidget);
  });

  testWidgets('직급·대리점 키 변경 시 이전 목록과 늦은 응답 제거', (tester) async {
    final old = Completer<Map<String, dynamic>>();
    final next = Completer<Map<String, dynamic>>();
    Widget screen(
      String role,
      int? branch,
      Future<Map<String, dynamic>> task,
    ) => MaterialApp(
      home: Scaffold(
        body: DispatchView(
          key: ValueKey('$role-dispatch-$branch'),
          branchId: branch,
          request: (_) => task,
        ),
      ),
    );
    await tester.pumpWidget(screen('branchStaff', 3, old.future));
    await tester.pumpWidget(screen('hqStaff', null, next.future));
    old.complete(result('OLD'));
    next.complete(result('NEW'));
    await tester.pumpAndSettle();
    expect(find.text('OLD'), findsNothing);
    expect(find.text('NEW'), findsOneWidget);
    final third = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(screen('branchStaff', 4, third.future));
    expect(find.text('NEW'), findsNothing);
    third.complete(result('BRANCH-4'));
    await tester.pumpAndSettle();
    expect(find.text('BRANCH-4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
