import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/vm/auth_api.dart';
import 'purchase_approval_inbox_test.dart' as fixture;

class MonitorApi extends fixture.ApprovalApi {
  @override
  Future<Map<String, dynamic>> getResponse(String path) async {
    final uri = Uri.parse(path);
    requests.add(uri);
    if (this.fail) throw const AuthApiException('현황 조회 실패');
    if (uri.path == '/api/v1/purchase-approvals/overview/40') {
      return {
        'data': {
          'requisition': {
            'purchase_requisition_id': 40,
            'title': '임원 품의',
            'reason': '전체 구매 사유',
            'requisition_status': 'REJECTED',
            'submitted_at': '2026-10-10T12:00:00',
            'items': [
              {
                'product_name': '실제 상품',
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
              'approval_status': 'APPROVED',
              'approver_name': '팀장 직원',
              'decided_at': '2026-10-10T13:00:00',
              'approval_comment': '팀장 승인 의견',
            },
            {
              'approval_sequence': 2,
              'role_name': '이사',
              'approval_status': 'REJECTED',
              'approver_name': '이사 직원',
              'decided_at': '2026-10-10T14:00:00',
              'approval_comment': '이사 반려 사유',
            },
          ],
        },
      };
    }
    expect(uri.path, '/api/v1/purchase-approvals/overview');
    expect(uri.queryParameters.containsKey('stage'), isFalse);
    final empty = uri.queryParameters['keyword'] == '없음';
    final page = int.parse(uri.queryParameters['page']!);
    return {
      'data': empty
          ? []
          : [
              {
                'purchase_requisition_id': 40,
                'title': '전체 현황 $page',
                'employee_name': '작성 직원',
                'branch_name': null,
                'item_count': 1,
                'total_requested_quantity': 100,
                'requisition_status': 'REJECTED',
                'submitted_at': '2026-10-10T12:00:00',
                'team_approval_status': 'APPROVED',
                'team_approver_name': '팀장 직원',
                'director_approval_status': 'REJECTED',
                'director_approver_name': '이사 직원',
              },
            ],
      'pagination': {
        'page': page,
        'page_size': 20,
        'total_count': empty ? 0 : 21,
      },
    };
  }
}

void main() {
  testWidgets('임원 결재 현황의 상태·검색·페이지와 전체 상세를 연결한다', (tester) async {
    final api = MonitorApi();
    await tester.pumpWidget(fixture.screen(api, 'executive'));
    await tester.pumpAndSettle();
    expect(find.text('내 처리 이력'), findsNothing);
    expect(find.text('팀장: 승인 · 팀장 직원'), findsOneWidget);
    expect(find.text('이사: 반려 · 이사 직원'), findsOneWidget);
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
    await tester.ensureVisible(
      find.byKey(const ValueKey('monitor-status-all')),
    );
    await tester.tap(find.byKey(const ValueKey('monitor-status-all')));
    await tester.pumpAndSettle();
    expect(find.text('초안'), findsNothing);
    await tester.tap(find.text('반려').last);
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters['status'], 'REJECTED');
    expect(api.requests.last.queryParameters['page'], '1');
    await tester.enterText(find.byKey(const Key('monitor-search')), '작성 직원');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters['keyword'], '작성 직원');
    await tester.ensureVisible(
      find.byKey(const ValueKey('approval-detail-40')),
    );
    await tester.tap(find.byKey(const ValueKey('approval-detail-40')));
    await tester.pumpAndSettle();
    expect(api.requests.last.path, '/api/v1/purchase-approvals/overview/40');
    expect(find.text('팀장 승인 의견'), findsOneWidget);
    expect(find.text('이사 반려 사유'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '승인'), findsNothing);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
  });
  testWidgets('현황 조회 오류를 재시도하고 빈 검색 결과를 표시한다', (tester) async {
    final api = MonitorApi()..fail = true;
    await tester.pumpWidget(fixture.screen(api, 'executive'));
    await tester.pumpAndSettle();
    expect(find.text('현황 조회 실패'), findsOneWidget);
    api.fail = false;
    await tester.ensureVisible(find.byKey(const Key('approval-refresh')));
    await tester.tap(find.byKey(const Key('approval-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('현황 조회 실패'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('monitor-search')));
    await tester.enterText(find.byKey(const Key('monitor-search')), '없음');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('상신된 품의가 없습니다.'), findsOneWidget);
    expect(find.textContaining('전체 현황'), findsNothing);
  });
}
