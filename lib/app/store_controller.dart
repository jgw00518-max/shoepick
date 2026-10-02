import 'dart:async';

import 'package:get/get.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

/// 화면 상태를 관리하며 저장과 조회는 Repository에 위임합니다.
class StoreController extends GetxController {
  StoreController({
    required this.productsRepository,
    required this.accountRepository,
    required this.orderRepository,
    required this.reviewRepository,
    required this.shoppingRepository,
    required this.supportRepository,
  });

  final ProductRepository productsRepository;
  final AccountRepository accountRepository;
  final OrderRepository orderRepository;
  final ReviewRepository reviewRepository;
  final ShoppingRepository shoppingRepository;
  final SupportRepository supportRepository;
  List<Product> products = [];
  List<StoreOrder> orders = [];
  final List<ProductReview> reviews = [];
  final List<CartItem> cart = [];
  final Set<int> wishedIds = {2};
  final List<int> recentIds = [];
  final List<InquiryEntry> inquiries = [];
  final Set<String> restockKeys = {};
  bool loading = true;
  String? loadError;
  bool isLoggedIn = false;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  int get cartCount => cart.fold(0, (sum, item) => sum + item.quantity);
  int get cartTotal => cart.fold(0, (sum, item) => sum + item.total);
  List<Product> get wished =>
      products.where((p) => wishedIds.contains(p.id)).toList();
  List<Product> get recent => recentIds
      .map((id) => products.where((p) => p.id == id).firstOrNull)
      .whereType<Product>()
      .toList();

  /// 목업 데이터도 비동기로 읽어 API 교체 시 UI 흐름을 유지합니다.
  Future<void> load() async {
    loading = true;
    loadError = null;
    update();
    try {
      products = await productsRepository.getProducts();
      orders = List.of(await orderRepository.getOrders());
      reviews
        ..clear()
        ..addAll(await reviewRepository.getReviews());
      final shopping = await shoppingRepository.load();
      cart
        ..clear()
        ..addAll(shopping.cart);
      wishedIds
        ..clear()
        ..addAll(shopping.wishedIds);
      recentIds
        ..clear()
        ..addAll(shopping.recentIds);
      inquiries
        ..clear()
        ..addAll(await supportRepository.getInquiries());
      restockKeys
        ..clear()
        ..addAll(await supportRepository.getRestockKeys());
    } catch (_) {
      loadError = '상품을 불러오지 못했습니다.';
    } finally {
      loading = false;
      update();
    }
  }

  void view(Product product) {
    recentIds.remove(product.id);
    recentIds.insert(0, product.id);
    update();
    unawaited(_saveShopping());
  }

  void toggleWish(Product product) {
    if (!wishedIds.remove(product.id)) wishedIds.add(product.id);
    update();
    unawaited(_saveShopping());
  }

  void addToCart(Product product, String size, String color) {
    addCartItems([CartItem(product: product, size: size, color: color)]);
  }

  void addCartItems(List<CartItem> items) {
    for (final item in items) {
      final index = cart.indexWhere((entry) => entry.key == item.key);
      if (index < 0) {
        cart.add(item);
      } else {
        cart[index] = cart[index].copyWith(
          quantity: (cart[index].quantity + item.quantity).clamp(1, 99),
        );
      }
    }
    update();
    unawaited(_saveShopping());
  }

  void changeQuantity(CartItem item, int quantity) {
    final index = cart.indexWhere((entry) => entry.key == item.key);
    if (index < 0) return;
    cart[index] = cart[index].copyWith(quantity: quantity.clamp(1, 99));
    update();
    unawaited(_saveShopping());
  }

  void updateCartOption(CartItem item, {String? size, String? color}) {
    final index = cart.indexWhere((entry) => entry.key == item.key);
    if (index < 0) return;
    final updated = cart[index].copyWith(size: size, color: color);
    final duplicate = cart.indexWhere(
      (entry) => entry.key == updated.key && entry.key != item.key,
    );
    cart.removeAt(index);
    if (duplicate >= 0) {
      final target = cart.indexWhere((entry) => entry.key == updated.key);
      cart[target] = cart[target].copyWith(
        quantity: (cart[target].quantity + updated.quantity).clamp(1, 99),
      );
    } else {
      cart.add(updated);
    }
    update();
    unawaited(_saveShopping());
  }

  void removeCartKeys(Set<String> keys) {
    cart.removeWhere((item) => keys.contains(item.key));
    update();
    unawaited(_saveShopping());
  }

  Future<void> _saveShopping() async {
    await shoppingRepository.save(
      ShoppingSnapshot(
        cart: List.of(cart),
        wishedIds: Set.of(wishedIds),
        recentIds: List.of(recentIds),
      ),
    );
  }

  Future<bool> signIn(String email, String password) async {
    final success = await accountRepository.signIn(email, password);
    if (success) {
      isLoggedIn = true;
      update();
    }
    return success;
  }

  Future<void> signUp(String email, String password) =>
      accountRepository.signUp(email, password);

  void signOut() {
    isLoggedIn = false;
    update();
  }

  Future<StoreOrder> placeOrder(
    String district, {
    List<CartItem>? lines,
    int? paidTotal,
    int couponDiscount = 0,
    int pointsUsed = 0,
    bool fromCart = true,
  }) async {
    final selected = List<CartItem>.of(lines ?? cart);
    final subtotal = selected.fold(0, (sum, item) => sum + item.total);
    final order = await orderRepository.createOrder(
      selected,
      district,
      paidTotal: paidTotal ?? subtotal,
      couponDiscount: couponDiscount,
      pointsUsed: pointsUsed,
    );
    orders.insert(0, order);
    if (fromCart) {
      final selectedKeys = selected.map((item) => item.key).toSet();
      cart.removeWhere((item) => selectedKeys.contains(item.key));
    }
    update();
    unawaited(_saveShopping());
    return order;
  }

  Future<void> cancelOrder(StoreOrder order) async {
    final canceled = await orderRepository.cancelOrder(order);
    final index = orders.indexWhere((item) => item.number == order.number);
    if (index >= 0) orders[index] = canceled;
    update();
  }

  /// 구매 항목별 중복 리뷰를 막는 목업 상태입니다.
  Future<void> addReview(ProductReview review) async {
    if (reviews.any(
      (item) =>
          item.orderNumber == review.orderNumber &&
          item.itemKey == review.itemKey,
    )) {
      return;
    }
    await reviewRepository.addReview(review);
    reviews.add(review);
    update();
  }

  Future<void> updateReview(ProductReview review) async {
    await reviewRepository.updateReview(review);
    final index = reviews.indexWhere(
      (item) =>
          item.orderNumber == review.orderNumber &&
          item.itemKey == review.itemKey,
    );
    if (index >= 0) reviews[index] = review;
    update();
  }

  Future<void> deleteReview(ProductReview review) async {
    await reviewRepository.deleteReview(review);
    reviews.removeWhere(
      (item) =>
          item.orderNumber == review.orderNumber &&
          item.itemKey == review.itemKey,
    );
    update();
  }

  Future<void> addInquiry(String kind, String title, String body) async {
    final entry = await supportRepository.createInquiry(kind, title, body);
    inquiries.insert(0, entry);
    update();
  }

  Future<void> toggleRestock(String key) async {
    if (!restockKeys.remove(key)) restockKeys.add(key);
    await supportRepository.saveRestockKeys(Set.of(restockKeys));
    update();
  }

  bool hasReview(StoreOrder order, CartItem item) => reviews.any(
    (review) =>
        review.orderNumber == order.number && review.itemKey == item.key,
  );
}
