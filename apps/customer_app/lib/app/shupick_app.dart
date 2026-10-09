import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../presentation/store_shell.dart';
import 'store_binding.dart';
import '../domain/repositories.dart';

/// 앱 진입점은 의존성 조립과 공통 테마만 담당합니다.
class ShupickApp extends StatelessWidget {
  const ShupickApp({super.key, this.accountRepository});

  final AccountRepository? accountRepository;

  @override
  Widget build(BuildContext context) => GetMaterialApp(
    title: 'SOLE SELECT',
    debugShowCheckedModeBanner: false,
    initialBinding: StoreBinding(accountRepository: accountRepository),
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF7F6F3),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF244D82)),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F6F3),
        surfaceTintColor: Colors.transparent,
      ),
    ),
    home: const StoreShell(),
  );
}
