import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/model/staff_views.dart';
import 'package:shoepick_staff_app/view/staff_pages.dart';
import 'package:shoepick_staff_app/vm/auth_api.dart';
import 'package:shoepick_staff_app/vm/purchase_requisition_api.dart';

class FakeAuth extends Fake implements FirebaseAuth {}

class ApprovalApi extends AuthApi {
  ApprovalApi() : super(auth: FakeAuth());
  final requests = <Uri>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> getResponse(String path) async {
    final uri = Uri.parse(path);
    requests.add(uri);
    if (fail) throw const AuthApiException('결재 조회 실패');
    final stage = uri.queryParameters['stage'];
    if (uri.path.endsWith('/1')) {
      return {
        'data': {
          'requisition': {
            'purchase_requisition_id': 40,
            'title': '실제 결재 품의',
            'reason': '전체 구매 사유',
            'requisition_status': 'PENDING_TEAM_LEAD',
            'items': [
              for (final i in [1, 2])
                {
                  'product_name': '전체 품목 $i',
                  'color_name': '검정',
                  'size_mm': 250,
                  'requested_quantity': 100,
                },
            ],
          },
          'steps': [
            {
              'approval_sequence': 1,
              'role_name': '팀장',
              'approval_status': 'PENDING',
              'approver_name': null,
              'approval_comment': null,
              'decided_at': null,
            },
          ],
        },
      };
    }
    expect(
      uri.path,
      anyOf(
        '/api/v1/purchase-approvals/pending',
        '/api/v1/purchase-approvals/history',
      ),
    );
    final history = uri.path.endsWith('/history');
    return {
      'data': [
        {
          'purchase_approval_id': 1,
          'purchase_requisition_id': 40,
          'title': '실제 $stage 결재 품의',
          'employee_name': '작성 직원',
          'branch_name': null,
          'item_count': 2,
          'total_requested_quantity': 200,
          'requisition_status': history
              ? 'REJECTED'
              : stage == 'DIRECTOR'
              ? 'PENDING_DIRECTOR'
              : 'PENDING_TEAM_LEAD',
          'approval_status': history ? 'APPROVED' : 'PENDING',
          'submitted_at': '2026-10-10T12:00:00',
          'decided_at': history ? '2026-10-10T13:00:00' : null,
          'approval_comment': history ? '팀장 승인 의견' : null,
        },
      ],
      'pagination': {
        'page': int.parse(uri.queryParameters['page']!),
        'page_size': 20,
        'total_count': 21,
      },
    };
  }
}

Widget screen(ApprovalApi api, String role) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: StaffPage(
        key: ValueKey(role),
        view: StaffView.approvals,
        roleKey: role,
        isBranch: false,
        purchaseRequisitionApi: PurchaseRequisitionApi(api),
      ),
    ),
  ),
);

void main() {
  testWidgets('팀장 결재함은 실제 대기와 본인 처리 이력을 조회한다', (tester) async {
    final api = ApprovalApi();
    await tester.pumpWidget(screen(api, 'teamLeader'));
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters['stage'], 'TEAM_LEAD');
    expect(find.textContaining('실제 TEAM_LEAD 결재 품의'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('approval-next')));
    await tester.tap(find.byKey(const Key('approval-next')));
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters['page'], '2');
    await tester.ensureVisible(find.byKey(const ValueKey('list-order-desc')));
    await tester.tap(find.byKey(const ValueKey('list-order-desc')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오래된순').last);
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters['order'], 'asc');
    expect(api.requests.last.queryParameters['page'], '1');
    await tester.ensureVisible(find.text('내 처리 이력'));
    await tester.tap(find.text('내 처리 이력'));
    await tester.pumpAndSettle();
    expect(api.requests.last.path, '/api/v1/purchase-approvals/history');
    expect(api.requests.last.queryParameters['page'], '1');
    expect(find.text('현재 상태: 반려'), findsOneWidget);
    expect(find.textContaining('내 결재: 승인'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '승인'), findsNothing);
  });
  testWidgets('이사 결재함 상세에 전체 품목을 표시하고 조회 오류를 재시도한다', (tester) async {
    final api = ApprovalApi();
    await tester.pumpWidget(screen(api, 'director'));
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters['stage'], 'DIRECTOR');
    await tester.ensureVisible(find.byKey(const ValueKey('list-order-desc')));
    await tester.tap(find.byKey(const ValueKey('list-order-desc')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오래된순').last);
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters['order'], 'asc');
    await tester.ensureVisible(find.byKey(const ValueKey('approval-detail-1')));
    await tester.tap(find.byKey(const ValueKey('approval-detail-1')));
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters['stage'], 'DIRECTOR');
    expect(find.text('전체 구매 사유'), findsOneWidget);
    expect(find.textContaining('전체 품목'), findsNWidgets(2));
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    api.fail = true;
    await tester.ensureVisible(find.byKey(const Key('approval-refresh')));
    await tester.tap(find.byKey(const Key('approval-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('결재 조회 실패'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.byKey(const Key('approval-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('결재 조회 실패'), findsNothing);
    expect(find.textContaining('실제 DIRECTOR 결재 품의'), findsOneWidget);
  });
}
