import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoepick_staff_app/model/staff_views.dart';
import 'package:shoepick_staff_app/view/staff_pages.dart';
import 'package:shoepick_staff_app/vm/headquarters_inventory_api.dart';

http.Response inventoryResponse(int page) => http.Response(
  jsonEncode({
    'data': [
      {
        'product_variant_id': 12,
        'product_id': 3,
        'product_code': 'SKU-12',
        'product_name': '실제 조회 운동화',
        'color_code': 'BLK',
        'color_name': '검정',
        'size_mm': 250,
        'on_hand_quantity': 100,
        'reserved_quantity': 10,
        'defective_quantity': 2,
        'available_quantity': 88,
        'updated_at': '2026-10-09T12:00:00',
      },
    ],
    'pagination': {'page': page, 'page_size': 20, 'total_count': 242},
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Widget inventoryScreen(HeadquartersInventoryApi api) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: StaffPage(
        view: StaffView.inventory,
        roleKey: 'hqStaff',
        isBranch: false,
        headquartersInventoryApi: api,
      ),
    ),
  ),
);

void main() {
  testWidgets('본사 재고 응답 표시·페이지 이동·검색 초기화', (tester) async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return inventoryResponse(int.parse(request.url.queryParameters['page']!));
    });
    addTearDown(client.close);
    final api = HeadquartersInventoryApi(client: client);
    await tester.pumpWidget(inventoryScreen(api));
    await tester.pumpAndSettle();
    expect(find.text('실제 조회 운동화'), findsOneWidget);
    expect(find.text('불량'), findsOneWidget);
    expect(find.text('88'), findsOneWidget);
    expect(find.text('조회 결과 242종 · 1페이지'), findsOneWidget);
    expect(requests.first.path, '/api/v1/inventory/headquarters');
    expect(requests.first.host, '10.0.2.2');
    expect(requests.first.port, 8000);

    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['page'], '2');

    await tester.ensureVisible(find.byKey(const Key('hq-inventory-search')));
    await tester.enterText(find.byKey(const Key('hq-inventory-search')), '운동화');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['page'], '1');
    expect(requests.last.queryParameters['keyword'], '운동화');
    expect(tester.takeException(), isNull);
  });

  testWidgets('오류 후 새로고침으로 실제 조회 재시도', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      if (++calls == 1) {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'INTERNAL_ERROR',
              'message': '데이터 조회 중 오류가 발생했습니다.',
            },
          }),
          500,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return inventoryResponse(1);
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      inventoryScreen(HeadquartersInventoryApi(client: client)),
    );
    await tester.pumpAndSettle();
    expect(find.text('데이터 조회 중 오류가 발생했습니다.'), findsOneWidget);
    expect(find.text('표시할 재고가 없습니다.'), findsNothing);
    await tester.tap(find.text('새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('실제 조회 운동화'), findsOneWidget);
    expect(find.text('데이터 조회 중 오류가 발생했습니다.'), findsNothing);
  });
}
