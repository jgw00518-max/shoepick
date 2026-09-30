/// 상품 목록과 상세 화면에서 공통으로 사용하는 상품 정보입니다.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.imageUrl,
    required this.color,
    required this.gender,
    this.middleCategory = '스니커즈',
    this.subcategory = '전체',
    this.images = const {},
    this.reviewCount = 2,
    this.salesCount = 0,
  });
  final int id;
  final String name;
  final String category;
  final int price;
  final String imageUrl;
  final String color;
  final String gender;
  final String middleCategory;
  final String subcategory;
  final Map<String, String> images;
  final int reviewCount;
  final int salesCount;
  String imageFor(String selectedColor) => images[selectedColor] ?? imageUrl;
  List<String> get colors =>
      images.isEmpty ? [color, '블랙', '베이지'] : images.keys.toList();
}

/// 선택한 옵션과 수량을 함께 보관하는 장바구니 항목입니다.
class CartItem {
  const CartItem({
    required this.product,
    required this.size,
    required this.color,
    this.quantity = 1,
  });
  final Product product;
  final String size;
  final String color;
  final int quantity;
  String get key => '${product.id}-$size-$color';
  int get total => product.price * quantity;
  CartItem copyWith({int? quantity, String? size, String? color}) => CartItem(
    product: product,
    size: size ?? this.size,
    color: color ?? this.color,
    quantity: quantity ?? this.quantity,
  );
}

/// 주문은 서버 API로 교체할 수 있도록 화면 상태와 분리합니다.
class StoreOrder {
  const StoreOrder({
    required this.number,
    required this.items,
    required this.date,
    required this.district,
    this.canceled = false,
    this.paidTotal,
    this.couponDiscount = 0,
    this.pointsUsed = 0,
  });
  final String number;
  final List<CartItem> items;
  final DateTime date;
  final String district;
  final bool canceled;
  final int? paidTotal;
  final int couponDiscount;
  final int pointsUsed;
  int get total => paidTotal ?? items.fold(0, (sum, item) => sum + item.total);
  StoreOrder copyWith({bool? canceled}) => StoreOrder(
    number: number,
    items: items,
    date: date,
    district: district,
    canceled: canceled ?? this.canceled,
    paidTotal: paidTotal,
    couponDiscount: couponDiscount,
    pointsUsed: pointsUsed,
  );
}

/// 구매 항목에 연결되는 화면 확인용 리뷰입니다.
class ProductReview {
  const ProductReview({
    required this.orderNumber,
    required this.itemKey,
    required this.rating,
    required this.content,
    this.fitSize = '정사이즈',
    this.fitWidth = '적당함',
    this.fitComfort = '편함',
    this.photos = const [],
  });
  final String orderNumber;
  final String itemKey;
  final int rating;
  final String content;
  final String fitSize;
  final String fitWidth;
  final String fitComfort;
  final List<String> photos;
}

/// FAQ와 별도로 표시하는 고객 문의 목업 정보입니다.
class InquiryEntry {
  const InquiryEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.date,
    this.answer,
  });
  final int id;
  final String kind;
  final String title;
  final String body;
  final String date;
  final String? answer;
  bool get answered => answer != null;
}

/// 찜·최근 본 상품·장바구니를 저장소와 주고받는 단위입니다.
class ShoppingSnapshot {
  const ShoppingSnapshot({
    required this.cart,
    required this.wishedIds,
    required this.recentIds,
  });
  final List<CartItem> cart;
  final Set<int> wishedIds;
  final List<int> recentIds;
}
