import 'package:get/get.dart';

import '../model/staff_payment.dart';
import 'auth_api.dart';

class StaffPaymentsVm extends GetxController {
  late final AuthApi api = AuthApi();

  List<StaffPayment> payments = [];
  bool loading = true;
  String? error;

  int page = 1;
  final int pageSize = 20;
  int totalCount = 0;
  int _request = 0;

  bool get hasPrevious => page > 1;
  bool get hasNext => page * pageSize < totalCount;

  @override
  void onInit() {
    super.onInit();
    fetchPayments();
  }

  Future<void> fetchPayments({int? targetPage}) async {
    final requestedPage = targetPage ?? page;
    final request = ++_request;

    loading = true;
    error = null;
    update();

    try {
      final response = await api.getResponse(
        '/api/v1/staff/payments'
        '?page=$requestedPage&page_size=$pageSize',
      );

      final loaded = (response['data'] as List<dynamic>)
          .map(
            (row) => StaffPayment.fromJson(
              row as Map<String, dynamic>,
            ),
          )
          .toList();

      final pagination =
          response['pagination'] as Map<String, dynamic>;

      if (isClosed || request != _request) return;

      payments = loaded;
      page = (pagination['page'] as num).toInt();
      totalCount = (pagination['total_count'] as num).toInt();
    } on StateError catch (exception) {
      if (isClosed || request != _request) return;
      error = exception.message.toString();
    } catch (_) {
      if (isClosed || request != _request) return;
      error = '결제 기록을 불러오지 못했습니다. 서버 연결을 확인해주세요.';
    } finally {
      if (!isClosed && request == _request) {
        loading = false;
        update();
      }
    }
  }
}