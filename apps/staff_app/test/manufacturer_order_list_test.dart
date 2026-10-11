import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/model/staff_views.dart';
import 'package:shoepick_staff_app/view/staff_pages.dart';
import 'package:shoepick_staff_app/vm/purchase_requisition_api.dart';
import 'package:shoepick_staff_app/vm/auth_api.dart';
import 'purchase_approval_inbox_test.dart';

class OrderApi extends ApprovalApi {
  bool empty = false;
  @override
  Future<Map<String, dynamic>> getResponse(String path) async {
    final uri = Uri.parse(path);
    requests.add(uri);
    if (this.fail) throw const AuthApiException('발주 조회 실패');
    final row = <String, dynamic>{
      'audit_log_id': 10,
      'purchase_requisition_id': 40,
      'order_number': 'PO-000040',
      'title': '기존 발주',
      'manufacturer_name': '발주 당시 제조사',
      'total_requested_quantity': 100,
      'item_count': 1,
      'registered_at': '2026-10-11T12:00:00',
      'registered_by_name': '이사',
      'requested_by_name': '작성 직원',
      'requisition_status': 'ORDERED',
      'reason': '발주 당시 사유',
      'items': [
        {
          'product_code': 'SKU',
          'product_name': '발주 당시 상품',
          'color_name': '검정',
          'size_mm': 250,
          'requested_quantity': 100,
        },
      ],
    };
    if (uri.path.endsWith('/10')) return {'data': row};
    return {
      'data': empty ? <Map<String, dynamic>>[] : [row],
      'pagination': {'total_count': empty ? 0 : 21},
    };
  }
}

Widget orderScreen(OrderApi api) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: StaffPage(
        view: StaffView.manufacturerOrders,
        roleKey: 'hqStaff',
        isBranch: false,
        purchaseRequisitionApi: PurchaseRequisitionApi(api),
      ),
    ),
  ),
);
void main() {
  testWidgets('발주 목록 검색 정렬 페이지와 스냅샷 상세를 연결한다', (tester) async {
    final api = OrderApi();
    await tester.pumpWidget(orderScreen(api));
    await tester.pumpAndSettle();
    expect(api.requests.last.path, '/api/v1/manufacturer-orders');
    expect(find.textContaining('PO-000040'), findsOneWidget);
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters['page'], '2');
    await tester.tap(find.byKey(const ValueKey('list-order-desc')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오래된순').last);
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters['order'], 'asc');
    expect(api.requests.last.queryParameters['page'], '1');
    await tester.enterText(
      find.byKey(const Key('manufacturer-order-search')),
      '제조사',
    );
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters['keyword'], '제조사');
    await tester.tap(
      find.byKey(const ValueKey('manufacturer-order-detail-10')),
    );
    await tester.pumpAndSettle();
    expect(api.requests.last.path, '/api/v1/manufacturer-orders/10');
    expect(find.textContaining('발주 당시 상품'), findsOneWidget);
    expect(find.text('구매 사유: 발주 당시 사유'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    api.fail = true;
    await tester.tap(find.text('새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('발주 조회 실패'), findsOneWidget);
    api.fail = false;
    api.empty = true;
    await tester.tap(find.text('새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('조회 가능한 발주 내역이 없습니다.'), findsOneWidget);
  });
  test('본사에 발주 메뉴가 있고 대리점에는 없다', () {
    for (final role in ['hqStaff', 'teamLeader', 'director', 'executive']) {
      expect(
        menusForRole(role).any((m) => m.view == StaffView.manufacturerOrders),
        isTrue,
      );
    }
    for (final role in ['branchStaff', 'branchManager']) {
      expect(
        menusForRole(role).any((m) => m.view == StaffView.manufacturerOrders),
        isFalse,
      );
    }
  });
}
