import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/vm/auth_api.dart';
import 'package:shupick/vm/order_history_vm.dart';

class TestAuth extends Fake implements FirebaseAuth {}

class TestApi extends AuthApi {
  TestApi() : super(auth: TestAuth());
  bool fail = false;
  String? requested;
  @override
  Future<Map<String, dynamic>> getResponse(String path) async {
    requested = path;
    if (fail) throw StateError('offline');
    return {
      'data': [
        {
          'order_id': 101,
          'order_number': 'test',
          'order_status': 'PAID',
          'paid_total': 59000,
        },
      ],
      'pagination': {'total_count': 21},
    };
  }
}

void main() {
  test('구매 목록은 API 응답과 페이지를 반영하고 실패하면 기존 개인 목록을 비운다', () async {
    final api = TestApi();
    final vm = OrderHistoryVm(api: api);
    await vm.fetchOrders(targetPage: 2);
    expect(vm.orders.single.id, 101);
    expect(vm.page, 2);
    expect(vm.totalCount, 21);
    expect(api.requested, contains('page=2'));
    api.fail = true;
    await vm.fetchOrders();
    expect(vm.orders, isEmpty);
    expect(vm.error, isNotNull);
    expect(vm.loading, isFalse);
  });
}
