import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_navigation_controller.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/presentation/store_shell.dart';

void main() {
  test('GetX 화면 이동 기록에 따라 이전 화면으로 돌아간다', () {
    final navigation = StoreNavigationController();

    navigation.go(StorePage.catalog);
    navigation.go(StorePage.detail);
    expect(navigation.page, StorePage.detail);

    navigation.back();
    expect(navigation.page, StorePage.catalog);
    navigation.back();
    expect(navigation.page, StorePage.home);
  });

  test('목업 상품 조회와 장바구니 주문 흐름', () async {
    final store = StoreController(
      productsRepository: MockProductRepository(),
      accountRepository: MockAccountRepository(),
      orderRepository: MockOrderRepository(),
      reviewRepository: MockReviewRepository(),
      shoppingRepository: MockShoppingRepository(),
      supportRepository: MockSupportRepository(),
    );
    await store.load();
    expect(store.products.length, 72);
    expect(store.products.where((item) => item.subcategory == '러닝화').length, 4);
    expect(store.orders.first.number, 'SS0928-1842');
    final product = store.products.first;
    store.addToCart(product, '260', product.color);
    store.addToCart(product, '260', product.color);
    expect(store.cartCount, 2);
    expect(store.cartTotal, product.price * 2);
    final order = await store.placeOrder('성동구');
    expect(order.total, product.price * 2);
    expect(store.cart, isEmpty);
    await store.cancelOrder(order);
    expect(store.orders.first.canceled, isTrue);
    await store.addReview(
      ProductReview(
        orderNumber: order.number,
        itemKey: order.items.first.key,
        rating: 5,
        content: '편하게 신을 수 있습니다.',
      ),
    );
    expect(store.hasReview(order, order.items.first), isTrue);
    store.dispose();
  });

  test('바로 구매는 기존 장바구니를 보존하고 선택 결제는 선택 상품만 제거한다', () async {
    final store = StoreController(
      productsRepository: MockProductRepository(),
      accountRepository: MockAccountRepository(),
      orderRepository: MockOrderRepository(),
      reviewRepository: MockReviewRepository(),
      shoppingRepository: MockShoppingRepository(),
      supportRepository: MockSupportRepository(),
    );
    await store.load();
    final first = store.products[0];
    final second = store.products[1];
    store.addToCart(first, '260', first.color);
    store.addToCart(second, '270', second.color);
    await store.placeOrder(
      '성동구',
      lines: [CartItem(product: first, size: '260', color: first.color)],
      fromCart: false,
    );
    expect(store.cartCount, 2);
    await store.placeOrder(
      '성동구',
      lines: [CartItem(product: first, size: '260', color: first.color)],
    );
    expect(store.cartCount, 1);
    expect(store.cart.single.product.id, second.id);
    store.dispose();
  });

  test('리뷰 수정·삭제와 문의·재입고 상태가 저장소 경계를 통과한다', () async {
    final support = MockSupportRepository();
    final store = StoreController(
      productsRepository: MockProductRepository(),
      accountRepository: MockAccountRepository(),
      orderRepository: MockOrderRepository(),
      reviewRepository: MockReviewRepository(),
      shoppingRepository: MockShoppingRepository(),
      supportRepository: support,
    );
    await store.load();
    final order = store.orders.first;
    final review = ProductReview(
      orderNumber: order.number,
      itemKey: order.items.first.key,
      rating: 5,
      content: '좋아요',
    );
    await store.addReview(review);
    await store.updateReview(
      ProductReview(
        orderNumber: order.number,
        itemKey: review.itemKey,
        rating: 4,
        content: '수정했어요',
      ),
    );
    expect(store.reviews.single.content, '수정했어요');
    await store.deleteReview(store.reviews.single);
    expect(store.reviews, isEmpty);
    await store.addInquiry('상품 문의', '재입고 문의', '260 사이즈는 언제 오나요?');
    expect(store.inquiries.first.title, '재입고 문의');
    await store.toggleRestock('1-블랙-260');
    expect(await support.getRestockKeys(), contains('1-블랙-260'));
    store.dispose();
  });
}
