import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/model/staff_views.dart';
import 'package:shoepick_staff_app/view/staff_pages.dart';
import 'package:shoepick_staff_app/view/purchase_requisition_edit.dart';
import 'package:shoepick_staff_app/vm/auth_api.dart';
import 'package:shoepick_staff_app/vm/purchase_requisition_api.dart';

class FakeAuth extends Fake implements FirebaseAuth {}

class EditApi extends AuthApi {
  EditApi() : super(auth: FakeAuth());
  final patches = <Map<String, dynamic>>[];
  bool fail = false;
  String title = '기존 품의';
  @override
  Future<Map<String, dynamic>> getResponse(String path) async {
    if (path.endsWith('/creation-options')) {
      return {
        'data': [
          for (final i in [12, 13])
            {
              'manufacturer_id': 1,
              'manufacturer_name': '제조사',
              'product_variant_id': i,
              'product_name': '상품 $i',
              'color_name': '검정',
              'size_mm': 250,
              'quantity': 100,
              'target_quantity': 100,
            },
        ],
      };
    }
    if (Uri.parse(path).path.endsWith('/40')) {
      return {
        'data': {
          'purchase_requisition_id': 40,
          'title': title,
          'reason': '기존 사유',
          'branch_id': null,
          'requisition_status': 'DRAFT',
          'revision': 'a' * 64,
          'items': [
            for (final i in [12, 13])
              {
                'product_variant_id': i,
                'requested_quantity': i,
                'manufacturer_id': 1,
              },
          ],
        },
      };
    }
    return {
      'data': [
        {
          'purchase_requisition_id': 40,
          'title': title,
          'requisition_status': 'DRAFT',
          'employee_name': '작성 직원',
          'created_at': '2026-10-10T12:00:00',
          'can_edit': true,
        },
      ],
      'pagination': {'page': 1, 'page_size': 20, 'total_count': 1},
    };
  }

  @override
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    expect(path, '/api/v1/purchase-requisitions/40');
    patches.add(body);
    if (fail) {
      throw const AuthApiException('다른 곳에서 품의가 변경되었습니다. 다시 불러온 뒤 수정해주세요.');
    }
    title = body['title'] as String;
    return {'purchase_requisition_id': 40, 'title': title};
  }
}

Future<void> openEditor(WidgetTester tester, EditApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StaffPage(
            view: StaffView.requests,
            roleKey: 'hqStaff',
            isBranch: false,
            purchaseRequisitionApi: PurchaseRequisitionApi(api),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('edit-requisition-40')));
  await tester.tap(find.byKey(const ValueKey('edit-requisition-40')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('최근 품의 수정은 기존 여러 품목을 유지하고 저장 후 목록을 갱신한다', (tester) async {
    final api = EditApi();
    await openEditor(tester, api);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('edit-requisition-title')))
          .controller!
          .text,
      '기존 품의',
    );
    await tester.enterText(
      find.byKey(const Key('edit-requisition-title')),
      '수정 품의',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('edit-quantity-0')));
    await tester.enterText(
      find.byKey(const ValueKey('edit-quantity-0')),
      '100',
    );
    await tester.tap(find.byKey(const Key('edit-requisition-save')));
    await tester.pumpAndSettle();
    expect(api.patches.single['revision'], 'a' * 64);
    expect(api.patches.single['items'], [
      {'product_variant_id': 12, 'requested_quantity': 100},
      {'product_variant_id': 13, 'requested_quantity': 13},
    ]);
    expect(find.byType(PurchaseRequisitionEdit), findsNothing);
    expect(find.text('수정 품의'), findsOneWidget);
    expect(find.textContaining('#40 초안을 수정'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('변경 충돌은 입력을 유지하고 다시 불러올 수 있다', (tester) async {
    final api = EditApi()..fail = true;
    await openEditor(tester, api);
    await tester.enterText(
      find.byKey(const Key('edit-requisition-title')),
      '입력 유지',
    );
    await tester.tap(find.byKey(const Key('edit-requisition-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('다른 곳에서 품의가 변경'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('edit-requisition-title')))
          .controller!
          .text,
      '입력 유지',
    );
    await tester.tap(find.text('다시 불러오기'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('edit-requisition-title')))
          .controller!
          .text,
      '기존 품의',
    );
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(api.patches, hasLength(1));
  });
}
