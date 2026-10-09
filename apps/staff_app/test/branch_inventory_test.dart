import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoepick_staff_app/view/branch_inventory.dart';
import 'package:shoepick_staff_app/vm/branch_inventory_api.dart';
import 'package:shoepick_staff_app/vm/staff_session.dart';

http.Response response({int branchId = 1, int page = 1, bool empty = false}) =>
    http.Response(
      jsonEncode({
        'data': empty
            ? []
            : [
                {
                  'branch_id': branchId,
                  'branch_name': '대리점 $branchId',
                  'product_name': '조회 상품 $branchId',
                  'product_code': 'SKU-$branchId',
                  'color_name': '검정',
                  'size_mm': 250,
                  'quantity': 2,
                  'holding_status': 'READY_FOR_PICKUP',
                  'order_number': 'ORDER-$branchId',
                  'fulfillment_number': 'FUL-$branchId',
                  'received_at': '2026-10-09T12:00:00',
                  'picked_up_at': null,
                },
              ],
        'pagination': {
          'page': page,
          'page_size': 20,
          'total_count': empty ? 0 : 21,
        },
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Widget screen(BranchInventoryApi api, {int? branchId = 1}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: BranchInventoryView(branchId: branchId, api: api),
    ),
  ),
);

void main() {
  test('로그인 대리점 이름과 실제 조회 branch_id가 일치한다', () async {
    final profile = await MockStaffAuthRepository().signIn(
      'demo@example.com',
      'mock1234',
    );
    final gangnam = profile.branches.singleWhere(
      (branch) => branch.districtCode == 'SEOUL-GANGNAM',
    );
    final seongdong = profile.branches.singleWhere(
      (branch) => branch.districtCode == 'SEOUL-SEONGDONG',
    );
    expect(gangnam.id, 2);
    expect(gangnam.name, 'SHOEPICK 강남점');
    expect(seongdong.id, 1);
    expect(seongdong.name, 'SHOEPICK 성동점');
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return response(branchId: int.parse(request.url.pathSegments.last));
    });
    addTearDown(client.close);
    final api = BranchInventoryApi(client: client);
    await api.fetch(branchId: gangnam.id);
    await api.fetch(branchId: seongdong.id);
    expect(paths, [
      '/api/v1/inventory/branches/2',
      '/api/v1/inventory/branches/1',
    ]);
  });

  testWidgets('대리점 보관 조회·상태 필터·검색·페이지 이동', (tester) async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return response(page: int.parse(request.url.queryParameters['page']!));
    });
    addTearDown(client.close);
    await tester.pumpWidget(screen(BranchInventoryApi(client: client)));
    await tester.pumpAndSettle();
    expect(requests.first.host, '10.0.2.2');
    expect(requests.first.path, '/api/v1/inventory/branches/1');
    expect(
      requests.first.queryParameters['holding_status'],
      'READY_FOR_PICKUP',
    );
    expect(find.text('조회 상품 1'), findsOneWidget);
    expect(find.text('조회 결과 21건 · 1페이지'), findsOneWidget);
    expect(find.text('2026-10-09 12:00'), findsOneWidget);

    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['page'], '2');
    await tester.ensureVisible(
      find.byKey(const Key('branch-inventory-search')),
    );
    await tester.enterText(
      find.byKey(const Key('branch-inventory-search')),
      '운동화',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['page'], '1');
    expect(requests.last.queryParameters['keyword'], '운동화');
    await tester.tap(find.byKey(const Key('branch-inventory-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전체 이력').last);
    await tester.pumpAndSettle();
    expect(
      requests.last.queryParameters.containsKey('holding_status'),
      isFalse,
    );
    expect(find.text('전체 이력에는 입고 대기·수령 완료 기록도 포함됩니다.'), findsOneWidget);
  });

  testWidgets('대리점 변경 시 이전 요청이 새 지점 결과를 덮어쓰지 않는다', (tester) async {
    final old = Completer<http.Response>();
    final client = MockClient(
      (request) async =>
          request.url.path.endsWith('/1') ? old.future : response(branchId: 2),
    );
    addTearDown(client.close);
    final api = BranchInventoryApi(client: client);
    await tester.pumpWidget(screen(api));
    await tester.pump();
    await tester.pumpWidget(screen(api, branchId: 2));
    await tester.pumpAndSettle();
    expect(find.text('조회 상품 2'), findsOneWidget);
    old.complete(response());
    await tester.pumpAndSettle();
    expect(find.text('조회 상품 2'), findsOneWidget);
    expect(find.text('조회 상품 1'), findsNothing);
  });

  testWidgets('조회 실패 안내 후 재시도와 빈 결과 표시', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      if (++calls == 1) {
        return http.Response(
          jsonEncode({
            'error': {'message': '대리점 조회 실패'},
          }),
          500,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return response(empty: true);
    });
    addTearDown(client.close);
    await tester.pumpWidget(screen(BranchInventoryApi(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('대리점 조회 실패'), findsOneWidget);
    expect(find.text('검색 조건에 맞는 보관 상품이 없습니다.'), findsNothing);
    await tester.tap(find.text('새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('검색 조건에 맞는 보관 상품이 없습니다.'), findsOneWidget);
    expect(find.text('대리점 조회 실패'), findsNothing);
  });

  testWidgets('소속 대리점 없이 조회하지 않는다', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return response();
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      screen(BranchInventoryApi(client: client), branchId: null),
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('조회할 소속 대리점을 선택해주세요.'), findsOneWidget);
  });
}
