import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/main.dart' as entry;
import 'package:shoepick_staff_app/model/mock_store.dart';
import 'package:shoepick_staff_app/model/staff_session.dart';
import 'package:shoepick_staff_app/view/staff_app.dart';
import 'package:shoepick_staff_app/vm/staff_session.dart';

class RecordingAuth implements StaffAuthRepository {
  RecordingAuth({this.fail = false});
  final bool fail;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Future<StaffProfile?> restoreSession() async => null;

  @override
  Future<StaffProfile> signIn(String email, String password) async {
    signInCalls++;
    if (fail) throw const StaffAuthException('실제 로그인 실패');
    final sample = await MockStaffAuthRepository().signIn(
      'demo@example.com',
      'mock1234',
    );
    return StaffProfile(
      id: 100,
      code: 'AUTH-100',
      name: '인증 직원',
      roles: sample.roles,
      branches: sample.branches,
    );
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

void main() {
  setUp(() => MockStore.instance.reset());

  testWidgets('목업 버튼은 실제 인증을 호출하지 않고 대시보드를 연다', (tester) async {
    final auth = RecordingAuth(fail: true);
    await tester.pumpWidget(MyApp(authRepository: auth));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('mock-quick-login')));
    await tester.tap(find.byKey(const Key('mock-quick-login')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('role-selector')), findsOneWidget);
    expect(find.textContaining('목업 모드'), findsOneWidget);
    expect(auth.signInCalls, 0);
    await tester.tap(find.byTooltip('로그아웃'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('staff-email')), findsOneWidget);
    expect(auth.signOutCalls, 0);
    await tester.enterText(
      find.byKey(const Key('staff-email')),
      'staff@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('staff-password')),
      'test-password',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, '로그인'));
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pumpAndSettle();
    expect(auth.signInCalls, 1);
    expect(find.text('실제 로그인 실패'), findsOneWidget);
  });

  testWidgets('일반 로그인과 로그아웃은 실제 인증 구현을 사용한다', (tester) async {
    final auth = RecordingAuth();
    await tester.pumpWidget(MyApp(authRepository: auth));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('staff-email')),
      'staff@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('staff-password')),
      'test-password',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, '로그인'));
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pumpAndSettle();
    expect(auth.signInCalls, 1);
    expect(find.textContaining('목업 모드'), findsNothing);
    await tester.tap(find.byTooltip('로그아웃'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.byKey(const Key('staff-email')), findsOneWidget);
  });

  testWidgets('UI 전용 실행 옵션은 Firebase 초기화 없이 시작한다', (tester) async {
    await tester.pumpWidget(await entry.createStaffApp(previewOnly: true));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('mock-quick-login')));
    await tester.tap(find.byKey(const Key('mock-quick-login')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('role-selector')), findsOneWidget);
    expect(find.textContaining('목업 모드'), findsOneWidget);
  });
}
