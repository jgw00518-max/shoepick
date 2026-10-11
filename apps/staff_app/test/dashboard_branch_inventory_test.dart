import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/view/staff_overview.dart';
import 'package:shoepick_staff_app/vm/dashboard_api.dart';
import 'package:shoepick_staff_app/vm/auth_api.dart';
import 'purchase_approval_inbox_test.dart';

class DashboardTestApi extends ApprovalApi {
  @override
  Future<Map<String, dynamic>> getResponse(String path) async {
    final uri = Uri.parse(path);
    requests.add(uri);
    if (this.fail) throw const AuthApiException('보관 수량 조회 실패');
    final branchId = int.parse(uri.pathSegments[uri.pathSegments.length - 2]);
    return {
      'data': {
        'branch_id': branchId,
        'branch_name': branchId == 1 ? '강남점' : '성동점',
        'held_quantity': branchId == 1 ? 13 : 0,
      },
    };
  }
}

Widget screen(DashboardTestApi api, int? branchId) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: StaffOverview(
        roleKey: 'branchStaff',
        selectedBranchId: branchId,
        onOpenView: (_) {},
        dashboardApi: DashboardApi(api),
      ),
    ),
  ),
);
void main() {
  testWidgets('선택한 지점의 실제 보관 합계를 표시하고 새로고침과 지점 변경을 반영한다', (tester) async {
    final api = DashboardTestApi();
    await tester.pumpWidget(screen(api, 1));
    await tester.pumpAndSettle();
    expect(api.requests.last.path, '/api/v1/dashboard/branches/1/inventory');
    expect(find.text('13켤레'), findsOneWidget);
    expect(find.text('강남점 · 실제 보관 수량'), findsOneWidget);
    expect(find.text('API 연결 예정'), findsNWidgets(3));
    api.fail = true;
    await tester.tap(find.text('새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('보관 수량 조회 실패'), findsOneWidget);
    expect(find.text('13켤레'), findsNothing);
    api.fail = false;
    await tester.pumpWidget(screen(api, 2));
    await tester.pumpAndSettle();
    expect(api.requests.last.path, '/api/v1/dashboard/branches/2/inventory');
    expect(find.text('0켤레'), findsOneWidget);
    expect(find.text('성동점 · 실제 보관 수량'), findsOneWidget);
  });
  testWidgets('지점 미선택 시 목업 수량으로 대체하지 않는다', (tester) async {
    final api = DashboardTestApi();
    await tester.pumpWidget(screen(api, null));
    await tester.pumpAndSettle();
    expect(find.text('조회할 대리점을 선택해주세요.'), findsOneWidget);
    expect(api.requests, isEmpty);
  });
}
