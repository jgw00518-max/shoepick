import 'models.dart';

/// 실제 연동 시 API 기반 구현으로 교체하는 상품 조회 경계입니다.
abstract interface class ProductRepository {
  Future<List<Product>> getProducts();
}

/// 실제 연동 시 서버가 인증과 계정 정보를 관리하도록 교체합니다.
abstract interface class AccountRepository {
  Future<bool> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> signOut();
}

/// 주문 생성과 취소는 추후 MySQL 백엔드 API에서 검증해야 합니다.
abstract interface class OrderRepository {
  Future<List<StoreOrder>> getOrders();
  Future<StoreOrder> createOrder(
    List<CartItem> items,
    String district, {
    required int paidTotal,
    required int couponDiscount,
    required int pointsUsed,
  });
  Future<StoreOrder> cancelOrder(StoreOrder order);
}

/// 실제 연동 시 구매 항목을 검증하는 리뷰 API로 교체합니다.
abstract interface class ReviewRepository {
  Future<List<ProductReview>> getReviews();
  Future<void> addReview(ProductReview review);
  Future<void> updateReview(ProductReview review);
  Future<void> deleteReview(ProductReview review);
}

/// 추후 장바구니·찜·최근 본 기록의 API/SQLite 구현으로 교체합니다.
abstract interface class ShoppingRepository {
  Future<ShoppingSnapshot> load();
  Future<void> save(ShoppingSnapshot snapshot);
}

/// 문의와 재입고 알림의 목업 데이터를 추후 서버 저장소로 교체합니다.
abstract interface class SupportRepository {
  Future<List<InquiryEntry>> getInquiries();
  Future<InquiryEntry> createInquiry(String kind, String title, String body);
  Future<Set<String>> getRestockKeys();
  Future<void> saveRestockKeys(Set<String> keys);
}
