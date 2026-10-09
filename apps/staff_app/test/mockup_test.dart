import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/main.dart';
import 'package:shoepick_staff_app/model/mock_store.dart';
import 'package:shoepick_staff_app/model/staff_role.dart';
import 'package:shoepick_staff_app/model/staff_views.dart';
import 'package:shoepick_staff_app/vm/staff_order_api.dart';
import 'package:shoepick_staff_app/vm/staff_registration_service.dart';
import 'package:shoepick_staff_app/vm/staff_session.dart';
import 'package:shoepick_staff_app/vm/staff_work_api.dart';

void main() {
  setUp(() => MockStore.instance.reset());
  for (final size in [
    const Size(1400, 900),
    const Size(800, 1024),
    const Size(390, 844),
  ]) {
    testWidgets('원본 서버 없이 $size 크기에서 6개 직책의 모든 화면을 연다', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      final quick = find.byKey(const Key('mock-quick-login'));
      await tester.ensureVisible(quick);
      await tester.tap(quick);
      await tester.pumpAndSettle();
      expect(find.textContaining('UI 목업'), findsOneWidget);
      for (final role in StaffRole.values) {
        await tester.tap(find.byKey(const Key('role-selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(role.label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${role.name} overview');
        for (final menu in menusForRole(role.name).skip(1)) {
          if (size.width < 700) {
            await tester.tap(find.byIcon(Icons.menu));
            await tester.pumpAndSettle();
          }
          final item = find.byKey(Key('menu-${menu.view.name}'));
          await tester.ensureVisible(item);
          await tester.pumpAndSettle();
          await tester.tap(item);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${role.name} ${menu.view}',
          );
        }
      }
    });
  }
  test('가상 수령·반품·환불·품의가 메모리 상태를 갱신한다', () async {
    final orders = MockStaffOrderRepository();
    final api = StaffWorkApi();
    final order = await orders.verifyPickup('MOCK-1003');
    await orders.completePickup(order, 'MOCK-1003');
    expect(
      (await orders.listOrders(
        branchId: MockStore.gangnamBranchId,
      )).firstWhere((o) => o.id == 3).status,
      'COMPLETED',
    );
    final eligible = await api.lookupReturnOrder(
      MockStore.gangnamBranchId,
      'MOCK-1006',
    );
    final id =
        (await api.registerReturn(6, {
              'reason': '가상 반품',
              'items': [
                {'itemKey': eligible['items'][0]['itemKey'], 'quantity': 1},
              ],
            }))['id']
            as int;
    await api.inspectReturn(id, {
      'accepted': true,
      'componentsComplete': true,
      'packagingIntact': true,
      'notes': '가상 검수',
    });
    final quote = await api.returnRefund(id);
    await api.processTestReturnRefund(id, quote['refundAmount'] as int);
    expect(
      (await api.returns()).firstWhere((r) => r['id'] == id)['status'],
      'COMPLETED',
    );
    final requisition = await api.createRequisition(
      productVariantId: 1,
      quantity: 10,
      title: '가상 품의',
      reason: '목업',
    );
    final reqId = requisition['purchaseRequisitionId'] as int;
    await api.submitRequisition(reqId);
    await api.decideRequisition(reqId, 'APPROVED', '팀장');
    await api.decideRequisition(reqId, 'APPROVED', '이사');
    expect(
      (await api.requisitions()).firstWhere((r) => r['id'] == reqId)['status'],
      'APPROVED',
    );
  });
  test('직원 등록과 로그인이 Firebase 없이 해당 직책을 표시한다', () async {
    await MockStaffRegistrationRepository().register(
      email: 'new@example.com',
      password: 'mock1234',
      name: '목업 점장',
      affiliation: 'BRANCH',
      districtCode: 'SEOUL-JUNGNANG',
      roleCode: 'BRANCH_MANAGER',
    );
    final user = await MockStaffAuthRepository().signIn(
      'new@example.com',
      'mock1234',
    );
    expect(user.roles.single.code, 'BRANCH_MANAGER');
    expect(user.branches.single.districtCode, 'SEOUL-JUNGNANG');
  });
}
