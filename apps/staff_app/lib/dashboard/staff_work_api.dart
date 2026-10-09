import 'package:shupick_staff_mockup/auth/staff_session.dart';
import 'package:shupick_staff_mockup/mock/mock_store.dart';

/// In-memory UI simulation: this class performs no network or database calls.
class StaffWorkApi {
  final store = MockStore.instance;
  Future<Map<String, dynamic>> inventory({
    int? branchId,
    DateTime? asOf,
  }) async => {
    'scope': branchId == null ? 'HQ' : 'BRANCH',
    'branchName': branchId == null ? '본사' : store.branchName(branchId),
    'asOf': asOf?.toIso8601String(),
    'rows': [
      for (final v in store.variants)
        {...v, if (branchId != null) 'quantity': branchId == 1 ? 3 : 2},
    ],
  };
  Future<List<Map<String, dynamic>>> branches() async => store.branches;
  Future<List<Map<String, dynamic>>> requisitions() async =>
      List.of(store.requisitions.reversed);
  Future<Map<String, dynamic>> createRequisition({
    required int productVariantId,
    required int quantity,
    required String title,
    required String reason,
  }) async {
    final id = store.requisitions.length + 1;
    final v = store.variant(productVariantId);
    store.requisitions.add({
      'id': id,
      'requestedByEmployeeId': 1,
      'employeeName': '목업 사원',
      'title': title,
      'reason': reason,
      'status': 'DRAFT',
      'createdAt': DateTime.now().toIso8601String(),
      'items': [
        {
          'productVariantId': productVariantId,
          'productName': v['product_name'],
          'colorName': v['color_name'],
          'sizeMm': v['size_mm'],
          'quantity': quantity,
        },
      ],
    });
    return {'purchaseRequisitionId': id};
  }

  Future<void> submitRequisition(int id) async {
    store.requisitions.firstWhere((r) => r['id'] == id)['status'] =
        'PENDING_TEAM_LEAD';
  }

  Future<void> decideRequisition(
    int id,
    String decision,
    String comment,
  ) async {
    final row = store.requisitions.firstWhere((r) => r['id'] == id);
    if (!['PENDING_TEAM_LEAD', 'PENDING_DIRECTOR'].contains(row['status'])) {
      throw const StaffAuthException('결재 대기 상태를 확인해주세요.');
    }
    row['status'] = decision == 'REJECTED'
        ? 'REJECTED'
        : row['status'] == 'PENDING_TEAM_LEAD'
        ? 'PENDING_DIRECTOR'
        : 'APPROVED';
    row['comment'] = comment;
  }

  Future<List<Map<String, dynamic>>> inquiries() async =>
      List.of(store.inquiries);
  Future<void> answerInquiry(int id, String answer) async {
    final row = store.inquiries.firstWhere((r) => r['id'] == id);
    row['answer'] = answer;
    row['status'] = 'ANSWERED';
  }

  Future<List<Map<String, dynamic>>> customers() async =>
      List.of(store.customers);
  Future<Map<String, dynamic>> customerDetail(int id) async {
    final customer = store.customers.firstWhere((c) => c['id'] == id);
    final orders = store.orders.where((o) => o['customerId'] == id).toList();
    return {
      ...customer,
      'orders': [
        for (final o in orders)
          {
            'id': o['orderId'],
            'number': o['orderNumber'],
            'status': o['orderStatus'],
            'paidTotal': o['paidTotal'],
            'orderedAt': o['orderedAt'],
            'branchName': o['branchName'],
          },
      ],
      'returns': [
        for (final r in store.returns.where(
          (r) => orders.any((o) => o['orderId'] == r['orderId']),
        ))
          r,
      ],
    };
  }

  Future<List<Map<String, dynamic>>> returns({int? branchId}) async => [
    for (final r in store.returns.where(
      (r) => branchId == null || r['branchId'] == branchId,
    ))
      r,
  ];
  Future<void> inspectReturn(int id, Map<String, dynamic> details) async {
    final row = store.returns.firstWhere((r) => r['id'] == id);
    if (row['status'] != 'REQUESTED') {
      throw const StaffAuthException('이미 검수된 목업 반품입니다.');
    }
    if (details['accepted'] == true) {
      final good =
          details['hasWearMarks'] != true &&
          details['hasProductDamage'] != true &&
          details['hasCustomerFault'] != true &&
          details['componentsComplete'] == true &&
          details['packagingIntact'] == true;
      if (!good &&
          details['hasProductDefect'] != true &&
          details['isWrongItem'] != true) {
        throw const StaffAuthException('상품 상태를 확인해주세요.');
      }
      final v = store.variant(row['variantId'] as int);
      v['quantity'] = (v['quantity'] as int) + (row['quantity'] as int);
    }
    row['status'] = details['accepted'] == true ? 'APPROVED' : 'REJECTED';
    row['notes'] = details['notes'];
  }

  Future<Map<String, dynamic>> lookupReturnOrder(
    int branchId,
    String orderNumber,
  ) async {
    final order = store.orders
        .where(
          (o) =>
              o['branchId'] == branchId &&
              o['orderNumber'] == orderNumber.trim().toUpperCase(),
        )
        .firstOrNull;
    if (order == null) {
      throw const StaffAuthException('해당 목업 지점의 주문을 찾지 못했습니다.');
    }
    if (order['orderStatus'] != 'COMPLETED') {
      throw const StaffAuthException('수령 완료 주문만 반품 접수할 수 있습니다.');
    }
    if (store.returns.any(
      (r) =>
          r['orderId'] == order['orderId'] &&
          !['REJECTED', 'CANCELED'].contains(r['status']),
    )) {
      throw const StaffAuthException('이미 접수된 반품입니다.');
    }
    final v = store.variant(order['variantId'] as int);
    return {
      'orderId': order['orderId'],
      'orderNumber': order['orderNumber'],
      'customerName': order['customerName'],
      'branchName': order['branchName'],
      'pickedUpAt': order['pickedUpAt'],
      'returnDeadlineAt': DateTime.parse(
        order['pickedUpAt'] as String,
      ).add(const Duration(days: 7)).toIso8601String(),
      'items': [
        {
          'itemKey': 'SKU-${order['variantId']}',
          'name': v['product_name'],
          'color': v['color_name'],
          'size': v['size_mm'],
          'quantity': order['quantity'],
        },
      ],
    };
  }

  Future<Map<String, dynamic>> registerReturn(
    int orderId,
    Map<String, dynamic> details,
  ) async {
    final order = store.orders.firstWhere((o) => o['orderId'] == orderId);
    await lookupReturnOrder(
      order['branchId'] as int,
      order['orderNumber'] as String,
    );
    final selection =
        (details['items'] as List<dynamic>).single as Map<String, dynamic>;
    final quantity = selection['quantity'] as int;
    if (selection['itemKey'] != 'SKU-${order['variantId']}' ||
        quantity < 1 ||
        quantity > (order['quantity'] as int)) {
      throw const StaffAuthException('반품 상품·수량을 확인해주세요.');
    }
    final id = store.returns.length + 1;
    store.returns.add({
      'id': id,
      'orderId': orderId,
      'orderNumber': order['orderNumber'],
      'customerName': order['customerName'],
      'branchId': order['branchId'],
      'branchName': order['branchName'],
      'status': 'REQUESTED',
      'reason': details['reason'],
      'variantId': order['variantId'],
      'quantity': quantity,
      'requestedAt': DateTime.now().toIso8601String(),
    });
    return {'id': id, 'status': 'REQUESTED'};
  }

  Future<Map<String, dynamic>> returnRefund(int id) async {
    final row = store.returns.firstWhere((r) => r['id'] == id);
    final v = store.variant(row['variantId'] as int);
    final quantity = row['quantity'] as int;
    final amount = (v['unit_price'] as int) * quantity;
    final refunded =
        store.refunds[id] ??
        (row['status'] == 'COMPLETED'
            ? {
                'refundStatus': 'SUCCEEDED',
                'refundNumber': 'MOCK-RF-$id',
                'refundAmount': amount,
              }
            : null);
    return {
      'returnId': id,
      'orderNumber': row['orderNumber'],
      'customerName': row['customerName'],
      'returnStatus': row['status'],
      'testPayment': true,
      'refundAmount': amount,
      'allocatedPoints': 0,
      'refund': refunded,
      'items': [
        {
          'name': v['product_name'],
          'color': v['color_name'],
          'size': v['size_mm'],
          'quantity': quantity,
          'refundAmount': amount,
          'allocatedPoints': 0,
        },
      ],
    };
  }

  Future<Map<String, dynamic>> processTestReturnRefund(
    int id,
    int amount,
  ) async {
    final existing = store.refunds[id];
    if (existing != null) return existing;
    final row = store.returns.firstWhere((r) => r['id'] == id);
    final quote = await returnRefund(id);
    if (row['status'] != 'APPROVED' || amount != quote['refundAmount']) {
      throw const StaffAuthException('승인 상태와 목업 환불 금액을 확인해주세요.');
    }
    final result = {
      'refundStatus': 'SUCCEEDED',
      'refundNumber': 'MOCK-RF-$id',
      'refundAmount': amount,
    };
    store.refunds[id] = result;
    row['status'] = 'COMPLETED';
    return result;
  }

  Future<Map<String, dynamic>> analytics({
    required int days,
    int? branchId,
    int? productId,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final rows = store.orders
        .where(
          (o) =>
              DateTime.parse(o['orderedAt'] as String).isAfter(cutoff) &&
              (branchId == null || o['branchId'] == branchId) &&
              (productId == null || o['variantId'] == productId),
        )
        .toList();
    final daily = <String, int>{};
    final byProduct = <int, int>{};
    var revenue = 0;
    for (final o in rows) {
      final day = (o['orderedAt'] as String).substring(0, 10);
      final quantity = o['quantity'] as int;
      daily[day] = (daily[day] ?? 0) + quantity;
      byProduct[o['variantId'] as int] =
          (byProduct[o['variantId']] ?? 0) + quantity;
      revenue += o['paidTotal'] as int;
    }
    final sortedDays = daily.keys.toList()..sort();
    return {
      'quantity': daily.values.fold<int>(0, (a, b) => a + b),
      'revenue': revenue,
      'orderCount': rows.length,
      'byDay': [
        for (final day in sortedDays) {'day': day, 'quantity': daily[day]},
      ],
      'byProduct': [
        for (final entry in byProduct.entries)
          {
            'productId': entry.key,
            'productName': store.variant(entry.key)['product_name'],
            'quantity': entry.value,
          },
      ],
      'products': [
        for (final v in store.variants)
          {'id': v['product_id'], 'name': v['product_name']},
      ],
      'branches': [
        for (final b in store.branches)
          {'id': b['branchId'], 'name': b['branchName']},
      ],
    };
  }
}
