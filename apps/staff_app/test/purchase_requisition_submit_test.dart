import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/vm/auth_api.dart';
import 'purchase_requisition_edit_test.dart' as fixture;

class SubmitApi extends fixture.EditApi {
  final submissions = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? pending;
  bool failSubmit = false;
  String status = 'DRAFT';
  @override
  Future<Map<String, dynamic>> getResponse(String path) async {
    final result = await super.getResponse(path);
    if (Uri.parse(path).path.endsWith('/40')) {
      final data = result['data'] as Map<String, dynamic>;
      data['requisition_status'] = status;
      data['items'] = [
        for (final item in data['items'] as List<dynamic>)
          <String, dynamic>{
            ...item as Map,
            'product_name': '확인 상품',
            'color_name': '검정',
            'size_mm': 250,
          },
      ];
    } else if (!path.endsWith('/creation-options')) {
      final row =
          (result['data'] as List<dynamic>).single as Map<String, dynamic>;
      result['data'] = [
        <String, dynamic>{
          ...row,
          'requisition_status': status,
          'can_submit': status == 'DRAFT',
          'can_edit': status == 'DRAFT',
        },
      ];
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    expect(path, '/api/v1/purchase-requisitions/40/submit');
    submissions.add(body);
    if (failSubmit) {
      throw const AuthApiException('품의 내용이 변경되었습니다. 다시 확인한 뒤 상신해주세요.');
    }
    final result = pending != null
        ? await pending!.future
        : <String, dynamic>{};
    status = 'PENDING_TEAM_LEAD';
    return result;
  }
}

Future<void> openConfirmation(WidgetTester tester, SubmitApi api) async {
  await fixture.openEditor(tester, api);
  await tester.tap(find.text('취소'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey('submit-requisition-40')),
  );
  await tester.tap(find.byKey(const ValueKey('submit-requisition-40')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('내용 확인 후 상신하며 중복 클릭을 막고 수정 버튼을 제거한다', (tester) async {
    final api = SubmitApi()..pending = Completer();
    await openConfirmation(tester, api);
    expect(find.text('기존 사유'), findsOneWidget);
    expect(find.textContaining('확인 상품'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('confirm-requisition-submit')));
    await tester.pump();
    expect(api.submissions, [
      {'revision': 'a' * 64},
    ]);
    final button = tester.widget<TextButton>(
      find.byKey(const ValueKey('submit-requisition-40')),
    );
    expect(button.onPressed, isNull);
    api.pending!.complete({});
    await tester.pumpAndSettle();
    expect(find.text('팀장 결재 대기'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-requisition-40')), findsNothing);
    expect(find.byKey(const ValueKey('submit-requisition-40')), findsNothing);
  });
  testWidgets('상신 확인 취소는 요청하지 않고 충돌은 안내한다', (tester) async {
    final api = SubmitApi();
    await openConfirmation(tester, api);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(api.submissions, isEmpty);
    api.failSubmit = true;
    await tester.tap(find.byKey(const ValueKey('submit-requisition-40')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-requisition-submit')));
    await tester.pumpAndSettle();
    expect(api.submissions, hasLength(1));
    expect(find.textContaining('품의 내용이 변경되었습니다'), findsOneWidget);
    expect(find.byKey(const ValueKey('submit-requisition-40')), findsOneWidget);
  });
}
