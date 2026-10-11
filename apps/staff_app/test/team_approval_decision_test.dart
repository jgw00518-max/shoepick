import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/vm/auth_api.dart';
import 'purchase_approval_inbox_test.dart';

class DecisionApi extends ApprovalApi {
  String? postedPath;
  Map<String, dynamic>? postedBody;
  bool processed = false;
  bool failDecision = false;
  @override
  Future<Map<String, dynamic>> getResponse(String path) async {
    final response = await super.getResponse(path);
    if (Uri.parse(path).path.endsWith('/1')) {
      final data = response['data'] as Map<String, dynamic>;
      data['approval'] = {'approval_status': 'PENDING'};
      if (Uri.parse(path).queryParameters['stage'] == 'DIRECTOR') {
        data['requisition']['requisition_status'] = 'PENDING_DIRECTOR';
      }
      data['requisition']['revision'] = List.filled(64, 'a').join();
    } else if (processed && Uri.parse(path).path.endsWith('/pending')) {
      response['data'] = <Map<String, dynamic>>[];
      response['pagination']['total_count'] = 0;
    }
    return response;
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    postedPath = path;
    postedBody = body;
    if (failDecision) throw const AuthApiException('품의 내용이 변경되었습니다.');
    processed = true;
    if (path.endsWith('/approve?stage=DIRECTOR')) {
      return {
        'requisition_status': 'ORDERED',
        'manufacturer_order': {
          'order_number': 'PO-000040',
          'transmission_status': 'NOT_SENT',
        },
      };
    }
    return {};
  }
}

void main() {
  for (final approve in [true, false]) {
    testWidgets('이사 ${approve ? '최종 승인' : '반려'} API를 연결한다', (tester) async {
      final api = DecisionApi();
      await tester.pumpWidget(screen(api, 'director'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('approval-detail-1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, approve ? '승인' : '반려'),
      );
      await tester.pumpAndSettle();
      expect(find.text(approve ? '이사 승인' : '이사 반려'), findsOneWidget);
      if (approve) {
        expect(find.textContaining('제조사 발주가 자동 등록됩니다.'), findsOneWidget);
      }
      if (!approve) {
        await tester.tap(find.text('반려 확정'));
        await tester.pumpAndSettle();
        expect(api.postedPath, isNull);
        expect(find.text('반려 사유를 입력해주세요.'), findsOneWidget);
      }
      await tester.enterText(find.byType(TextField), '최종 결재 의견');
      await tester.tap(find.text(approve ? '승인 확정' : '반려 확정'));
      await tester.pumpAndSettle();
      expect(
        api.postedPath,
        '/api/v1/purchase-approvals/1/${approve ? 'approve' : 'reject'}?stage=DIRECTOR',
      );
      expect(api.postedBody?['comment'], '최종 결재 의견');
      expect(find.text('결재 대기 품의가 없습니다.'), findsOneWidget);
      if (approve) {
        expect(
          find.text('최종 승인 및 자동 발주 등록 완료: PO-000040 (외부 전송 전)'),
          findsOneWidget,
        );
      }
    });
  }
  for (final approve in [true, false]) {
    testWidgets('팀장 상세에서 ${approve ? '승인' : '반려'}하고 결재 대기를 갱신한다', (
      tester,
    ) async {
      final api = DecisionApi();
      await tester.pumpWidget(screen(api, 'teamLeader'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('approval-detail-1')));
      await tester.pumpAndSettle();
      expect(find.text('전체 구매 사유'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, approve ? '승인' : '반려'),
      );
      await tester.pumpAndSettle();
      if (!approve) {
        await tester.tap(find.text('반려 확정'));
        await tester.pumpAndSettle();
        expect(find.text('반려 사유를 입력해주세요.'), findsOneWidget);
        expect(api.postedPath, isNull);
      }
      await tester.enterText(find.byType(TextField), '결재 의견');
      api.failDecision = true;
      await tester.tap(find.text(approve ? '승인 확정' : '반려 확정'));
      await tester.pumpAndSettle();
      expect(find.text('품의 내용이 변경되었습니다.'), findsOneWidget);
      expect(find.text('결재 의견'), findsOneWidget);
      api.failDecision = false;
      await tester.tap(find.text(approve ? '승인 확정' : '반려 확정'));
      await tester.pumpAndSettle();
      expect(
        api.postedPath,
        '/api/v1/purchase-approvals/1/${approve ? 'approve' : 'reject'}',
      );
      expect(api.postedBody?['comment'], '결재 의견');
      expect(api.postedBody?['revision'], List.filled(64, 'a').join());
      expect(find.text('결재 대기 품의가 없습니다.'), findsOneWidget);
    });
  }
}
