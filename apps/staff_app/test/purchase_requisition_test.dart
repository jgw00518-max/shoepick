import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/model/staff_views.dart';
import 'package:shoepick_staff_app/view/staff_pages.dart';
import 'package:shoepick_staff_app/view/matched_height_panels.dart';
import 'package:shoepick_staff_app/vm/auth_api.dart';
import 'package:shoepick_staff_app/vm/purchase_requisition_api.dart';

class FakeAuth extends Fake implements FirebaseAuth {}

class RecordingApi extends AuthApi {
  RecordingApi() : super(auth: FakeAuth());
  final posts = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? pending;
  bool fail = false;
  final listRequests = <Uri>[];
  bool listFail = false;
  final stored = <Map<String, dynamic>>[
    {
      'purchase_requisition_id': 40,
      'title': 'DB 기존 품의',
      'requisition_status': 'DRAFT',
      'employee_name': '작성 직원',
      'created_at': '2026-10-10T12:00:00',
    },
  ];
  @override
  Future<Map<String, dynamic>> getResponse(String path) async {
    final uri = Uri.parse(path);
    if (uri.path == '/api/v1/purchase-requisitions') {
      listRequests.add(uri);
      if (listFail) throw const AuthApiException('목록 조회 실패');
      final status = uri.queryParameters['status'];
      final rows = stored
          .where((row) => status == null || row['requisition_status'] == status)
          .toList();
      final page = int.parse(uri.queryParameters['page']!);
      return {
        'data': rows.skip((page - 1) * 20).take(20).toList(),
        'pagination': {
          'page': page,
          'page_size': 20,
          'total_count': rows.length,
        },
      };
    }
    expect(path, '/api/v1/purchase-requisitions/creation-options');
    return {
      'data': [
        {
          'manufacturer_id': 1,
          'manufacturer_name': '실제 제조사',
          'product_variant_id': 12,
          'product_name': '실제 운동화',
          'color_name': '검정',
          'size_mm': 250,
          'quantity': 29,
          'target_quantity': 100,
        },
        {
          'manufacturer_id': 2,
          'manufacturer_name': '다른 제조사',
          'product_variant_id': 13,
          'product_name': '다른 상품',
          'color_name': '흰색',
          'size_mm': 260,
          'quantity': 90,
          'target_quantity': 100,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    expect(path, '/api/v1/purchase-requisitions');
    posts.add(body);
    if (fail) throw const AuthApiException('접근 권한이 없습니다.');
    final result = pending != null
        ? await pending!.future
        : {
            'purchase_requisition_id': 51,
            'title': body['title'],
            'requisition_status': 'DRAFT',
          };
    stored.insert(0, {
      ...result,
      'employee_name': '작성 직원',
      'created_at': '2026-10-10T13:00:00',
    });
    return result;
  }
}

Future<void> fillForm(WidgetTester tester, RecordingApi api) async {
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
  await tester.tap(find.byKey(const Key('requisition-manufacturer')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('실제 제조사').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('requisition-variant-1')));
  await tester.pumpAndSettle();
  expect(find.text('다른 상품 · 흰색 / 260'), findsNothing);
  await tester.tap(find.text('실제 운동화 · 검정 / 250').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), '100');
  await tester.enterText(find.byType(TextField).at(1), '실제 품의');
  await tester.enterText(find.byType(TextField).at(2), '재고 보충');
  await tester.ensureVisible(find.text('품의 초안 저장'));
}

void main() {
  testWidgets('태블릿에서 제목 입력 후 사유로 이동해도 품의 폼이 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await fillForm(tester, RecordingApi());
    await tester.enterText(find.byType(TextField).at(1), 'request');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(TextField).at(2));
    await tester.tap(find.byType(TextField).at(2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byType(TextField).at(2),
      '재고 보충\n제조사 추가 구매\n100켤레 요청',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.textScaleFactorTestValue = 1.25;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final panels = tester.widget<MatchedHeightPanels>(
      find.byType(MatchedHeightPanels),
    );
    expect(
      tester.getSize(find.byWidget(panels.children[1])).height,
      tester.getSize(find.byWidget(panels.children[0])).height,
    );
  });
  testWidgets('실제 제조사로 초안 저장하며 중복 클릭과 목업 상신을 막는다', (tester) async {
    final api = RecordingApi()..pending = Completer();
    await fillForm(tester, api);
    await tester.tap(find.text('품의 초안 저장'));
    await tester.pump();
    expect(find.text('저장 중…'), findsOneWidget);
    expect(api.posts, hasLength(1));
    expect(api.posts.single, {
      'manufacturer_id': 1,
      'title': '실제 품의',
      'reason': '재고 보충',
      'items': [
        {'product_variant_id': 12, 'requested_quantity': 100},
      ],
    });
    api.pending!.complete({
      'purchase_requisition_id': 51,
      'title': '실제 품의',
      'requisition_status': 'DRAFT',
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('#51를 초안으로 저장'), findsOneWidget);
    expect(find.text('초안'), findsNWidgets(2));
    expect(api.listRequests, hasLength(2));
    expect(find.text('품의 상신'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('최근 DB 품의의 페이지·상태·새로고침을 연결한다', (tester) async {
    final api = RecordingApi();
    for (var i = 0; i < 24; i++) {
      api.stored.add({
        'purchase_requisition_id': i,
        'title': 'DB 품의 $i',
        'requisition_status': 'APPROVED',
        'employee_name': '다른 직원',
        'created_at': '2026-10-09T12:00:00',
      });
    }
    await fillForm(tester, api);
    expect(find.text('DB 기존 품의'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('requisition-next')));
    await tester.tap(find.byKey(const Key('requisition-next')));
    await tester.pumpAndSettle();
    expect(api.listRequests.last.queryParameters['page'], '2');
    expect(find.text('DB 품의 23'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('list-order-desc')));
    await tester.tap(find.byKey(const ValueKey('list-order-desc')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오래된순').last);
    await tester.pumpAndSettle();
    expect(api.listRequests.last.queryParameters['order'], 'asc');
    expect(api.listRequests.last.queryParameters['page'], '1');
    await tester.ensureVisible(
      find.byKey(const ValueKey('requisition-status-all')),
    );
    await tester.tap(find.byKey(const ValueKey('requisition-status-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('초안').last);
    await tester.pumpAndSettle();
    expect(api.listRequests.last.queryParameters['status'], 'DRAFT');
    expect(api.listRequests.last.queryParameters['page'], '1');
    expect(find.text('DB 기존 품의'), findsOneWidget);
    api.listFail = true;
    await tester.ensureVisible(find.byKey(const Key('requisition-refresh')));
    await tester.tap(find.byKey(const Key('requisition-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('목록 조회 실패'), findsOneWidget);
    api.listFail = false;
    await tester.ensureVisible(find.byKey(const Key('requisition-refresh')));
    await tester.tap(find.byKey(const Key('requisition-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('목록 조회 실패'), findsNothing);
    expect(find.text('DB 기존 품의'), findsOneWidget);
  });
  testWidgets('저장 오류는 입력 내용을 유지하고 안내한다', (tester) async {
    final api = RecordingApi()..fail = true;
    await fillForm(tester, api);
    await tester.tap(find.text('품의 초안 저장'));
    await tester.pumpAndSettle();
    expect(find.text('접근 권한이 없습니다.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      '실제 품의',
    );
    expect(api.posts, hasLength(1));
  });
}
