import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/view/staff_app.dart';
import 'package:shoepick_staff_app/view/login.dart';
import 'package:shoepick_staff_app/model/staff_session.dart';
import 'package:shoepick_staff_app/vm/staff_session.dart';

class ExpiringStaff extends MockStaffAuthRepository
    implements StaffSessionEvents {
  final events = StreamController<void>.broadcast();
  @override
  Stream<void> get sessionEnded => events.stream;
  @override
  Future<StaffProfile?> restoreSession() => signIn('test@example.com', 'test');
}

void main() {
  testWidgets('session expiration returns staff UI to login', (tester) async {
    final auth = ExpiringStaff();
    await tester.pumpWidget(MyApp(authRepository: auth));
    await tester.pumpAndSettle();
    expect(find.byType(Login), findsNothing);
    auth.events.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(Login), findsOneWidget);
    expect(find.byKey(const Key('role-selector')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await auth.events.close();
  });
}
