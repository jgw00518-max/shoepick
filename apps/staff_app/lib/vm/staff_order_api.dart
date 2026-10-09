import 'package:shupick_staff_mockup/model/mock_store.dart';
import 'package:shupick_staff_mockup/model/staff_session.dart';

import 'package:shupick_staff_mockup/model/staff_order.dart';

abstract class StaffOrderRepository {
  Future<List<StaffOrder>> listOrders({int? branchId});
  Future<StaffOrder> verifyPickup(String code);
  Future<void> completePickup(StaffOrder order, String code);
  Future<void> markArrived(int fulfillmentId);
  Future<void> shipFulfillment(int fulfillmentId);
}

/// Local substitute retaining the original UI repository contract.
class MockStaffOrderRepository implements StaffOrderRepository {
  final store = MockStore.instance;
  @override
  Future<List<StaffOrder>> listOrders({int? branchId}) async => [
    for (final row in store.orders.where(
      (row) => branchId == null || row['branchId'] == branchId,
    ))
      StaffOrder.fromJson(row),
  ];
  @override
  Future<StaffOrder> verifyPickup(String code) async {
    final row = store.orders
        .where(
          (o) =>
              o['orderNumber'] == code.trim().toUpperCase() &&
              o['orderStatus'] == 'READY_FOR_PICKUP',
        )
        .firstOrNull;
    if (row == null) {
      throw const StaffAuthException(
        '목업 수령 대기 코드 MOCK-1003 또는 MOCK-1008을 입력하세요.',
      );
    }
    return StaffOrder.fromJson(row);
  }

  @override
  Future<void> completePickup(StaffOrder order, String code) async {
    final row = store.orders.firstWhere((o) => o['orderId'] == order.id);
    if (row['orderStatus'] != 'READY_FOR_PICKUP' ||
        row['orderNumber'] != code) {
      throw const StaffAuthException('수령 대기 주문과 코드를 확인해주세요.');
    }
    row['orderStatus'] = 'COMPLETED';
    row['fulfillmentStatus'] = 'COMPLETED';
    row['pickedUpAt'] = DateTime.now().toIso8601String();
  }

  @override
  Future<void> markArrived(int fulfillmentId) async {
    final row = store.orders.firstWhere(
      (o) => o['fulfillmentId'] == fulfillmentId,
    );
    if (row['orderStatus'] != 'IN_TRANSIT') {
      throw const StaffAuthException('배송 중인 목업 주문만 입고할 수 있습니다.');
    }
    row['orderStatus'] = 'READY_FOR_PICKUP';
    row['fulfillmentStatus'] = 'READY_FOR_PICKUP';
  }

  @override
  Future<void> shipFulfillment(int fulfillmentId) async {
    final row = store.orders.firstWhere(
      (o) => o['fulfillmentId'] == fulfillmentId,
    );
    row['orderStatus'] = 'IN_TRANSIT';
    row['fulfillmentStatus'] = 'IN_TRANSIT';
  }
}
