import 'package:get/get.dart';

import '../data/local_support_repository.dart';
import '../data/mock_repositories.dart';
import '../domain/repositories.dart';
import 'store_controller.dart';
import 'store_navigation_controller.dart';
import '../data/api_product_repository.dart';

/// 앱에서 사용하는 저장소와 GetX 컨트롤러의 생성 책임을 모읍니다.
class StoreBinding extends Bindings {
  StoreBinding({this.accountRepository});

  final AccountRepository? accountRepository;
  @override
  void dependencies() {
    Get.lazyPut<ProductRepository>(() => ApiProductRepository());
    Get.lazyPut<AccountRepository>(
      () => accountRepository ?? MockAccountRepository(),
    );
    Get.lazyPut<OrderRepository>(() => MockOrderRepository());
    Get.lazyPut<ReviewRepository>(() => MockReviewRepository());
    Get.lazyPut<ShoppingRepository>(() => MockShoppingRepository());
    Get.lazyPut<SupportRepository>(() => LocalSupportRepository());
    Get.put(StoreNavigationController());
    Get.put(
      StoreController(
        productsRepository: Get.find(),
        accountRepository: Get.find(),
        orderRepository: Get.find(),
        reviewRepository: Get.find(),
        shoppingRepository: Get.find(),
        supportRepository: Get.find(),
      ),
    );
  }
}
