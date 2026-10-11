import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/view/staff_overview.dart';
import 'package:shoepick_staff_app/vm/dashboard_api.dart';
import 'package:shoepick_staff_app/vm/auth_api.dart';
import 'purchase_approval_inbox_test.dart';

class LowStockApi extends ApprovalApi {
  int count = 7;
  bool failSales = false;
  @override
  Future<Map<String, dynamic>> getResponse(String path) async {
    requests.add(Uri.parse(path));
    if (this.fail) throw const AuthApiException('본사 재고 부족 조회 실패');
    if (path.endsWith('/executive/sales')) {
      if (failSales) throw const AuthApiException('판매 현황 조회 실패');
      return {
        'data': {
          'sales_quantity': 5,
          'revenue_amount': 120000,
          'order_count': 2,
        },
      };
    }
    return {
      'data': {
        'low_stock_variant_count': count,
        'monitored_variant_count': 242,
      },
    };
  }
}

Widget screen(LowStockApi api, String role) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: StaffOverview(
        roleKey: role,
        selectedBranchId: null,
        onOpenView: (_) {},
        dashboardApi: DashboardApi(api),
      ),
    ),
  ),
);
void main() {
  for (final role in ['hqStaff', 'teamLeader', 'director', 'executive']) {
    testWidgets('$role 대시보드의 재고 부족을 실제 API에 연결한다', (tester) async {
      final api = LowStockApi();
      await tester.pumpWidget(screen(api, role));
      await tester.pumpAndSettle();
      expect(
        api.requests.first.path,
        '/api/v1/dashboard/headquarters/low-stock',
      );
      expect(find.text('7종'), findsOneWidget);
      expect(
        find.text('API 연결 예정'),
        role == 'executive' ? findsNothing : findsNWidgets(3),
      );
      if (role == 'executive') {
        expect(find.text('5켤레'), findsOneWidget);
        expect(find.text('₩120,000'), findsOneWidget);
        expect(find.text('2건'), findsOneWidget);
      }
      expect(find.textContaining('7개 제품 옵션의 가용 재고'), findsOneWidget);
      api.fail = true;
      await tester.tap(find.text('새로고침'));
      await tester.pumpAndSettle();
      expect(find.text('본사 재고 부족 조회 실패'), findsOneWidget);
      expect(find.text('7종'), findsNothing);
      api.fail = false;
      api.count = 0;
      await tester.tap(find.text('새로고침'));
      await tester.pumpAndSettle();
      expect(find.text('0종'), findsOneWidget);
      expect(find.textContaining('7개 제품 옵션의 가용 재고'), findsNothing);
    });
  }
  testWidgets('판매 집계 실패 시 실제 재고 부족은 유지하고 재시도한다', (tester) async {
    final api = LowStockApi()..failSales = true;
    await tester.pumpWidget(screen(api, 'executive'));
    await tester.pumpAndSettle();
    expect(find.text('판매 현황 조회 실패'), findsOneWidget);
    expect(find.text('7종'), findsOneWidget);
    expect(find.text('₩120,000'), findsNothing);
    api.failSales = false;
    await tester.tap(find.text('새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('₩120,000'), findsOneWidget);
  });
}
