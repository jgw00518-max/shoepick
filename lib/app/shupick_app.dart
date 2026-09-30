import 'package:flutter/material.dart';

import '../data/mock_repositories.dart';
import '../data/local_support_repository.dart';
import '../presentation/store_shell.dart';
import 'store_controller.dart';

/// 앱 진입점은 의존성 조립과 공통 테마만 담당합니다.
class ShupickApp extends StatefulWidget {
  const ShupickApp({super.key});
  @override
  State<ShupickApp> createState() => _ShupickAppState();
}

class _ShupickAppState extends State<ShupickApp> {
  late final StoreController store;
  @override
  void initState() {
    super.initState();
    store = StoreController(
      productsRepository: MockProductRepository(),
      accountRepository: MockAccountRepository(),
      orderRepository: MockOrderRepository(),
      reviewRepository: MockReviewRepository(),
      shoppingRepository: MockShoppingRepository(),
      supportRepository: LocalSupportRepository(),
    );
    store.load();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SOLE SELECT',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF7F6F3),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF244D82)),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F6F3),
        surfaceTintColor: Colors.transparent,
      ),
    ),
    home: StoreShell(store: store),
  );
}
