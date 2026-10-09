/// UI-only fixtures. All changes live in memory and reset when the app restarts.
class MockStore {
  MockStore._() {
    reset();
  }
  static final instance = MockStore._();
  final orders = <Map<String, dynamic>>[];
  final returns = <Map<String, dynamic>>[];
  final requisitions = <Map<String, dynamic>>[];
  final inquiries = <Map<String, dynamic>>[];
  final customers = <Map<String, dynamic>>[];
  final registeredStaff = <String, Map<String, dynamic>>{};
  final refunds = <int, Map<String, dynamic>>{};
  final variants = <Map<String, dynamic>>[];
  static const districts = {
    '강남구': 'SEOUL-GANGNAM',
    '강동구': 'SEOUL-GANGDONG',
    '강북구': 'SEOUL-GANGBUK',
    '강서구': 'SEOUL-GANGSEO',
    '관악구': 'SEOUL-GWANAK',
    '광진구': 'SEOUL-GWANGJIN',
    '구로구': 'SEOUL-GURO',
    '금천구': 'SEOUL-GEUMCHEON',
    '노원구': 'SEOUL-NOWON',
    '도봉구': 'SEOUL-DOBONG',
    '동대문구': 'SEOUL-DONGDAEMUN',
    '동작구': 'SEOUL-DONGJAK',
    '마포구': 'SEOUL-MAPO',
    '서대문구': 'SEOUL-SEODAEMUN',
    '서초구': 'SEOUL-SEOCHO',
    '성동구': 'SEOUL-SEONGDONG',
    '성북구': 'SEOUL-SEONGBUK',
    '송파구': 'SEOUL-SONGPA',
    '양천구': 'SEOUL-YANGCHEON',
    '영등포구': 'SEOUL-YEONGDEUNGPO',
    '용산구': 'SEOUL-YONGSAN',
    '은평구': 'SEOUL-EUNPYEONG',
    '종로구': 'SEOUL-JONGNO',
    '중구': 'SEOUL-JUNG',
    '중랑구': 'SEOUL-JUNGNANG',
  };
  List<Map<String, dynamic>> get branches => [
    for (final entry in districts.entries)
      {
        'branchId': districts.keys.toList().indexOf(entry.key) + 1,
        'branchName': 'SHOEPICK ${entry.key.replaceAll('구', '')}점',
        'districtCode': entry.value,
      },
  ];
  String branchName(int id) =>
      branches.firstWhere((b) => b['branchId'] == id)['branchName'] as String;
  Map<String, dynamic> variant(int id) =>
      variants.firstWhere((v) => v['product_variant_id'] == id);

  void reset() {
    orders.clear();
    returns.clear();
    requisitions.clear();
    inquiries.clear();
    customers.clear();
    variants.clear();
    refunds.clear();
    registeredStaff.clear();
    for (var i = 1; i <= 4; i++) {
      variants.add({
        'product_variant_id': i,
        'product_id': i,
        'product_name': [
          'City Runner',
          'Soft Walk',
          'Classic Loafer',
          'Daily Sneaker',
        ][i - 1],
        'product_code': 'MOCK-SHOE-00$i',
        'color_name': i.isEven ? 'WHITE' : 'BLACK',
        'size_mm': [250, 260, 270, 280][i - 1],
        'quantity': [8, 35, 4, 20][i - 1],
        'reserved_quantity': [3, 5, 1, 2][i - 1],
        'available_quantity': [5, 30, 3, 18][i - 1],
        'target_quantity': 30,
        'unit_price': [79000, 99000, 129000, 69000][i - 1],
      });
    }
    final now = DateTime.now();
    for (var i = 1; i <= 5; i++) {
      customers.add({
        'id': i,
        'name': ['김민준', '이서연', '박지훈', '최유진', '정하늘'][i - 1],
        'email': 'customer$i@example.com',
        'phone': '010-0000-000$i',
        'pointBalance': i * 1000,
        'orderCount': 0,
        'paidTotal': 0,
        'lastOrderedAt': now.subtract(Duration(days: i)).toIso8601String(),
      });
    }
    final statuses = [
      'PREPARING',
      'IN_TRANSIT',
      'READY_FOR_PICKUP',
      'COMPLETED',
      'COMPLETED',
      'COMPLETED',
      'IN_TRANSIT',
      'READY_FOR_PICKUP',
      'COMPLETED',
      'COMPLETED',
    ];
    for (var i = 1; i <= 10; i++) {
      final branchId = i <= 6 ? 1 : 16;
      final variantId = (i - 1) % 4 + 1;
      final item = variant(variantId);
      final customerId = (i - 1) % 5 + 1;
      final quantity = i % 3 == 0 ? 2 : 1;
      orders.add({
        'orderId': i,
        'orderNumber': 'MOCK-${1000 + i}',
        'orderStatus': statuses[i - 1],
        'orderedAt': now.subtract(Duration(days: i % 7)).toIso8601String(),
        'customerId': customerId,
        'customerName': customers[customerId - 1]['name'],
        'branchId': branchId,
        'branchName': branchName(branchId),
        'fulfillmentId': 100 + i,
        'fulfillmentStatus': statuses[i - 1],
        'products': [
          '${item['product_name']} · ${item['color_name']} / ${item['size_mm']} × $quantity',
        ],
        'variantId': variantId,
        'quantity': quantity,
        'paidTotal': (item['unit_price'] as int) * quantity,
        'pickedUpAt': now.subtract(Duration(days: 1)).toIso8601String(),
      });
    }
    for (final order in orders) {
      final customer = customers[(order['customerId'] as int) - 1];
      customer['orderCount'] = (customer['orderCount'] as int) + 1;
      customer['paidTotal'] =
          (customer['paidTotal'] as int) + (order['paidTotal'] as int);
    }
    for (var i = 1; i <= 3; i++) {
      final order = orders[[3, 4, 9][i - 1]];
      returns.add({
        'id': i,
        'orderId': order['orderId'],
        'orderNumber': order['orderNumber'],
        'customerName': order['customerName'],
        'branchId': order['branchId'],
        'branchName': order['branchName'],
        'status': ['REQUESTED', 'APPROVED', 'COMPLETED'][i - 1],
        'reason': '가상 고객의 사이즈 불일치 반품',
        'variantId': order['variantId'],
        'quantity': 1,
        'requestedAt': now.toIso8601String(),
      });
    }
    for (var i = 1; i <= 3; i++) {
      final item = variant(i);
      requisitions.add({
        'id': i,
        'requestedByEmployeeId': 1,
        'employeeName': '목업 사원',
        'title': '${item['product_name']} 재고 보충',
        'reason': '본사 안전 재고 확보를 위한 가상 품의',
        'status': ['PENDING_TEAM_LEAD', 'PENDING_DIRECTOR', 'APPROVED'][i - 1],
        'createdAt': now.toIso8601String(),
        'items': [
          {
            'productVariantId': i,
            'productName': item['product_name'],
            'colorName': item['color_name'],
            'sizeMm': item['size_mm'],
            'quantity': 20,
          },
        ],
      });
    }
    for (var i = 1; i <= 3; i++) {
      inquiries.add({
        'id': i,
        'customerId': i,
        'customerName': customers[i - 1]['name'],
        'type': ['DELIVERY', 'PRODUCT', 'OTHER'][i - 1],
        'title': ['픽업 가능 시간을 알고 싶어요', '사이즈 재입고 문의', '반품 진행 상황 문의'][i - 1],
        'body': '이 문의는 화면 검토를 위한 가상 데이터입니다.',
        'status': i == 3 ? 'ANSWERED' : 'OPEN',
        'answer': i == 3 ? '확인 후 안내드렸습니다.' : null,
        'createdAt': now.toIso8601String(),
      });
    }
  }
}
