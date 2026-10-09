import '../domain/models.dart';
import '../domain/repositories.dart';

const _images = [
  'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071141_4579da28-0d2f-42fc-8ecf-9901a170129b.png',
  'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071141_2e7f3842-62de-421a-8855-6bbac9864ab6.png',
  'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_496afa2f-095c-4ce1-87bd-81f09c8f9fc7.png',
  'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_883111c9-d119-43bf-a16d-d11f25469a67.png',
  'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071117_6e9218c6-59d9-4a86-ab98-c15b856fd71c.png',
  'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_4a6637ae-b3c0-45bf-8dc4-23873e53ac6c.png',
];

final mockHeroImage = _images[5];

/// Higgsfield 상품 목업을 앱 실행 중 조회할 수 있게 제공합니다.
class MockProductRepository implements ProductRepository {
  static const _baseCategories = <int, (String, String)>{
    1: ('스니커즈', '캔버스/단화'),
    2: ('구두', '더비/레이스업'),
    3: ('부츠', '워커'),
    4: ('샌들', '캐쥬얼샌들'),
    5: ('스포츠', '러닝화'),
    6: ('스포츠', '농구화'),
    7: ('구두', '더비/레이스업'),
    8: ('구두', '더비/레이스업'),
    9: ('구두', '로퍼'),
    10: ('구두', '로퍼'),
    11: ('구두', '로퍼'),
    12: ('부츠', '패딩부츠'),
    13: ('부츠', '윈터 스니커즈'),
    14: ('샌들', '코르크샌들'),
    15: ('샌들', '스포츠샌들'),
    16: ('샌들', '슬라이드'),
    17: ('샌들', '슬라이드'),
    18: ('스니커즈', '뮬'),
    19: ('스니커즈', '슬립온'),
    20: ('구두', '더비/레이스업'),
    21: ('샌들', '캐쥬얼샌들'),
  };
  static const _sales = <int, int>{
    1: 984,
    2: 812,
    3: 615,
    4: 1103,
    5: 1450,
    6: 1328,
    7: 724,
    8: 901,
    9: 876,
    10: 669,
    11: 588,
    12: 742,
    13: 831,
    14: 1205,
    15: 993,
    16: 1542,
    17: 1377,
    18: 1064,
  };
  static const _reviews = <int, int>{
    1: 128,
    2: 94,
    3: 67,
    4: 156,
    5: 231,
    6: 184,
    7: 82,
    8: 113,
    9: 105,
    10: 76,
    11: 59,
    12: 88,
    13: 97,
    14: 169,
    15: 121,
    16: 248,
    17: 207,
    18: 143,
  };
  static const categoryTree = <String, List<String>>{
    '스니커즈': ['캔버스/단화', '슬립온', '뮬'],
    '스포츠': ['러닝화', '농구화', '골프화', '축구화'],
    '구두': ['로퍼', '더비/레이스업'],
    '샌들': ['슬라이드', '스포츠샌들', '코르크샌들', '캐쥬얼샌들'],
    '부츠': ['워커', '털부츠', '패딩부츠', '윈터 스니커즈'],
  };
  static const _names = <String, List<String>>{
    '스니커즈': ['Canvas Day', 'Easy Step', 'Urban Mule'],
    '스포츠': ['Motion Run', 'Court Drive', 'Field Pro'],
    '구두': ['Classic Form', 'City Leather', 'Daily Formal'],
    '샌들': ['Summer Flow', 'Coast Walk', 'Breeze Strap'],
    '부츠': ['Winter Base', 'Trail Warm', 'Snow Guard'],
  };
  static final List<Product> _products = [
    _p(1, 'Aero Shift 01', '운동화', 189000, '코발트', '공용', 1),
    _p(2, 'Classic Derby', '구두', 169000, '블랙', '남성', 3),
    _p(3, 'City Chelsea', '부츠', 209000, '브라운', '남성', 4),
    _p(4, 'Coast Sandal', '샌들', 79000, '베이지', '여성', 4),
    _p(5, 'Daily Runner', '운동화', 119000, '실버', '공용', 2),
    _p(6, 'Street Pace', '운동화', 99000, '블랙', '공용', 3),
    _p(7, 'Oxford Classic', '구두', 159000, '브라운', '남성', 4),
    _p(8, 'Soft Mary Jane', '구두', 129000, '그레이', '여성', 2),
    _p(9, 'Penny Loafer', '로퍼', 139000, '브라운', '남성', 4),
    _p(10, 'Suede Ease', '로퍼', 109000, '베이지', '여성', 4),
    _p(11, 'Modern Loafer', '로퍼', 149000, '블랙', '남성', 3),
    _p(12, 'Weekend Boot', '부츠', 179000, '베이지', '공용', 4),
    _p(13, 'Urban Ankle', '부츠', 199000, '블랙', '남성', 3),
    _p(14, 'Summer Strap', '샌들', 69000, '브라운', '여성', 4),
    _p(15, 'Light Trek Sandal', '샌들', 89000, '블랙', '남성', 3),
    _p(16, 'Cloud Slide', '슬리퍼', 39000, '베이지', '공용', 4),
    _p(17, 'Recovery Slide', '슬리퍼', 49000, '그레이', '여성', 2),
    _p(18, 'Soft Room', '슬리퍼', 29000, '브라운', '공용', 4),
    _p(19, 'Junior Pace', '운동화', 69000, '코발트', '키즈', 1),
    _p(20, 'Little Step', '구두', 79000, '브라운', '키즈', 4),
    _p(21, 'Sunny Kids', '샌들', 49000, '베이지', '키즈', 4),
  ];

  static Product _p(
    int id,
    String name,
    String category,
    int price,
    String color,
    String gender,
    int image,
  ) => Product(
    id: id,
    name: name,
    category: category,
    price: price,
    color: color,
    gender: gender,
    imageUrl: _images[image],
    middleCategory: _baseCategories[id]!.$1,
    subcategory: _baseCategories[id]!.$2,
    images: {color: _images[image], '블랙': _images[3], '베이지': _images[4]},
    reviewCount: _reviews[id] ?? 2,
    salesCount: _sales[id] ?? 300 + id,
  );

  /// 원본의 카테고리별 추가 상품 생성 규칙을 재현합니다.
  static List<Product> _generatedProducts() {
    final output = <Product>[];
    final groups = categoryTree.entries.toList();
    for (var middleIndex = 0; middleIndex < groups.length; middleIndex++) {
      final group = groups[middleIndex];
      for (var subIndex = 0; subIndex < group.value.length; subIndex++) {
        for (var genderIndex = 0; genderIndex < 3; genderIndex++) {
          final color = ['블랙', '베이지', '화이트'][genderIndex];
          output.add(
            Product(
              id: 100 + middleIndex * 20 + subIndex * 3 + genderIndex,
              name:
                  '${_names[group.key]![subIndex % 3]} ${(subIndex + 1).toString().padLeft(2, '0')}',
              category: group.value[subIndex],
              price:
                  59000 +
                  middleIndex * 24000 +
                  subIndex * 9000 +
                  genderIndex * 5000,
              imageUrl: _images[[3, 4, 2][genderIndex]],
              color: color,
              gender: ['남성', '여성', '키즈'][genderIndex],
              middleCategory: group.key,
              subcategory: group.value[subIndex],
              images: {'블랙': _images[3], '베이지': _images[4], '화이트': _images[2]},
              reviewCount: 2,
              salesCount:
                  300 + 100 + middleIndex * 20 + subIndex * 3 + genderIndex,
            ),
          );
        }
      }
    }
    return output;
  }

  @override
  Future<List<Product>> getProducts() async =>
      List.unmodifiable([..._products, ..._generatedProducts()]);
}

/// 비밀번호를 영구 저장하지 않는 화면 확인용 계정입니다.
class MockAccountRepository implements AccountRepository {
  @override
  Future<void> signOut() async {}
  final Map<String, String> _accounts = {'user@sole.kr': 'sole1234'};
  @override
  Future<bool> signIn(String email, String password) async =>
      _accounts[email] == password;
  @override
  Future<void> signUp(String email, String password) async {
    if (_accounts.containsKey(email)) throw StateError('이미 가입한 이메일입니다.');
    _accounts[email] = password;
  }
}

/// 주문의 실제 저장 대신 메모리에서 화면 흐름을 재현합니다.
class MockOrderRepository implements OrderRepository {
  final List<StoreOrder> _orders = [
    StoreOrder(
      number: 'SS0928-1842',
      items: [
        CartItem(
          product: MockProductRepository._products.first,
          size: '260',
          color: '코발트',
        ),
      ],
      date: DateTime(2026, 9, 28),
      district: '성동구',
    ),
  ];
  @override
  Future<List<StoreOrder>> getOrders() async => List.unmodifiable(_orders);
  @override
  Future<StoreOrder> createOrder(
    List<CartItem> items,
    String district, {
    required int paidTotal,
    required int couponDiscount,
    required int pointsUsed,
  }) async {
    final order = StoreOrder(
      number: 'SS${DateTime.now().millisecondsSinceEpoch}',
      items: List.unmodifiable(items),
      date: DateTime.now(),
      district: district,
      paidTotal: paidTotal,
      couponDiscount: couponDiscount,
      pointsUsed: pointsUsed,
    );
    _orders.insert(0, order);
    return order;
  }

  @override
  Future<StoreOrder> cancelOrder(StoreOrder order) async {
    final index = _orders.indexWhere((item) => item.number == order.number);
    if (index < 0) throw StateError('주문을 찾을 수 없습니다.');
    final canceled = order.copyWith(canceled: true);
    _orders[index] = canceled;
    return canceled;
  }
}

/// 리뷰는 실행 중에만 보존하는 목업 저장소입니다.
class MockReviewRepository implements ReviewRepository {
  final List<ProductReview> _reviews = [];
  @override
  Future<List<ProductReview>> getReviews() async => List.unmodifiable(_reviews);
  @override
  Future<void> addReview(ProductReview review) async => _reviews.add(review);
  @override
  Future<void> updateReview(ProductReview review) async {
    final index = _reviews.indexWhere(
      (item) =>
          item.orderNumber == review.orderNumber &&
          item.itemKey == review.itemKey,
    );
    if (index >= 0) _reviews[index] = review;
  }

  @override
  Future<void> deleteReview(ProductReview review) async => _reviews.removeWhere(
    (item) =>
        item.orderNumber == review.orderNumber &&
        item.itemKey == review.itemKey,
  );
}

/// 쇼핑 상태는 앱 실행 중에만 저장하는 목업 구현입니다.
class MockShoppingRepository implements ShoppingRepository {
  ShoppingSnapshot _snapshot = const ShoppingSnapshot(
    cart: [],
    wishedIds: {2},
    recentIds: [],
  );
  @override
  Future<ShoppingSnapshot> load() async => _snapshot;
  @override
  Future<void> save(ShoppingSnapshot snapshot) async => _snapshot = snapshot;
}

/// 문의 예시와 재입고 알림을 보유하는 목업 구현입니다.
class MockSupportRepository implements SupportRepository {
  final List<InquiryEntry> _inquiries = [
    const InquiryEntry(
      id: 1,
      kind: '배송 문의',
      title: '픽업 대리점 운영시간이 궁금해요',
      body: '퇴근 후 방문하려고 합니다. 평일 운영시간을 알려주세요.',
      date: '2026.09.20',
      answer: 'SOLE 성동점은 평일 오전 10시 30분부터 오후 8시까지 운영합니다. 방문 시 주문 QR을 준비해주세요.',
    ),
    const InquiryEntry(
      id: 2,
      kind: '상품 문의',
      title: 'Silver Current 재입고 문의',
      body: '260 사이즈 재입고 예정일이 궁금합니다.',
      date: '2026.09.27',
    ),
  ];
  Set<String> _restockKeys = {};
  @override
  Future<List<InquiryEntry>> getInquiries() async =>
      List.unmodifiable(_inquiries);
  @override
  Future<InquiryEntry> createInquiry(
    String kind,
    String title,
    String body,
  ) async {
    final entry = InquiryEntry(
      id: DateTime.now().microsecondsSinceEpoch,
      kind: kind,
      title: title,
      body: body,
      date: '2026.09.28',
    );
    _inquiries.insert(0, entry);
    return entry;
  }

  @override
  Future<Set<String>> getRestockKeys() async => Set.of(_restockKeys);
  @override
  Future<void> saveRestockKeys(Set<String> keys) async =>
      _restockKeys = Set.of(keys);
}
