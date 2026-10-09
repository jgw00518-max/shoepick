import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';

void main() {
  test('로그아웃은 이전 고객의 개인 상태와 로컬 장바구니를 비운다', () async {
    final shopping = MockShoppingRepository();
    final store = StoreController(
      productsRepository: MockProductRepository(),
      accountRepository: MockAccountRepository(),
      orderRepository: MockOrderRepository(),
      reviewRepository: MockReviewRepository(),
      shoppingRepository: shopping,
      supportRepository: MockSupportRepository(),
    );
    await store.load();
    await store.signIn('user@sole.kr', 'sole1234');
    store.addToCart(store.products.first, '260', store.products.first.color);
    await store.signOut();
    expect(store.isLoggedIn, isFalse);
    expect(store.orders, isEmpty);
    expect(store.cart, isEmpty);
    expect(store.reviews, isEmpty);
    expect((await shopping.load()).cart, isEmpty);
  });
}
