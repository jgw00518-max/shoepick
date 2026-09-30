import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/shupick_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('비회원 홈에서 상품과 마이페이지로 이동할 수 있다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ShupickApp());
    await tester.pumpAndSettle();
    expect(find.text('SOLE / SELECT'), findsOneWidget);
    expect(find.text('기획전'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('로그인 / 회원가입'), findsOneWidget);
  });

  testWidgets('설정에서 영어를 선택하면 화면 문구가 전환된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ShupickApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Dark mode'), findsOneWidget);
  });

  testWidgets('카테고리에서 성별과 신발 종류를 선택해 상품 목록으로 이동한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ShupickApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('카테고리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('여성'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('스니커즈'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('캔버스/단화'));
    await tester.pumpAndSettle();
    expect(find.text('여성 · 캔버스/단화'), findsWidgets);
  });
}
