import 'dart:async';
import 'package:shupick/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';

class ExpiringAccount extends MockAccountRepository
    implements AccountSessionEvents {
  final events = StreamController<void>.broadcast();
  @override
  Stream<void> get sessionEnded => events.stream;
}

void main() {
  test('session expiration clears the existing customer UI state', () async {
    final account = ExpiringAccount();
    final store = StoreController(
      productsRepository: MockProductRepository(),
      accountRepository: account,
      orderRepository: MockOrderRepository(),
      reviewRepository: MockReviewRepository(),
      shoppingRepository: MockShoppingRepository(),
      supportRepository: MockSupportRepository(),
    );
    store.onInit();
    await Future<void>.delayed(Duration.zero);
    await store.signIn('user@sole.kr', 'sole1234');
    store.addToCart(store.products.first, '260', store.products.first.color);
    account.events.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(store.isLoggedIn, isFalse);
    expect(store.orders, isEmpty);
    expect(store.cart, isEmpty);
    store.onClose();
    await account.events.close();
  });
}
