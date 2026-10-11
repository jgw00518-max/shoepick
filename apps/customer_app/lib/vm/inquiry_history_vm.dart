import 'package:get/get.dart';
import '../model/customer_inquiry.dart';

/// B의 인증 요청을 전달받고 목록과 상세의 늦은 응답을 폐기한다.
class InquiryHistoryVm extends GetxController {
  InquiryHistoryVm({required this.request});
  final Future<Map<String, dynamic>> Function(String) request;
  bool loading = false;
  bool detailLoading = false;
  String? error;
  String? detailError;
  List<CustomerInquiry> inquiries = [];
  CustomerInquiry? detail;
  int page = 1;
  int total = 0;
  int _detailVersion = 0;
  bool get hasNext => page * 20 < total;
  @override
  void onInit() {
    super.onInit();
    fetch();
  }

  Future<void> fetch({int targetPage = 1}) async {
    if (isClosed || loading) return;
    loading = true;
    error = null;
    inquiries = [];
    update();
    try {
      final response = await request(
        '/api/v1/order-history/inquiries/customer?page=$targetPage&page_size=20',
      );
      if (isClosed) return;
      inquiries = (response['data'] as List)
          .map((row) => CustomerInquiry(Map<String, dynamic>.from(row as Map)))
          .toList();
      page = response['pagination']['page'] as int;
      total = response['pagination']['total_count'] as int;
    } catch (e) {
      if (!isClosed) {
        error = e is StateError ? e.message.toString() : '문의 목록을 불러오지 못했습니다.';
      }
    } finally {
      if (!isClosed) {
        loading = false;
        update();
      }
    }
  }

  Future<void> fetchDetail(int id) async {
    if (isClosed || detailLoading) return;
    final version = ++_detailVersion;
    detailLoading = true;
    detailError = null;
    detail = null;
    update();
    try {
      final response = await request(
        '/api/v1/order-history/inquiries/customer/$id',
      );
      if (isClosed || version != _detailVersion) return;
      detail = CustomerInquiry(
        Map<String, dynamic>.from(response['data'] as Map),
      );
    } catch (e) {
      if (!isClosed && version == _detailVersion) {
        detailError = e is StateError
            ? e.message.toString()
            : '문의 상세를 불러오지 못했습니다.';
      }
    } finally {
      if (!isClosed && version == _detailVersion) {
        detailLoading = false;
        update();
      }
    }
  }

  void closeDetail() {
    _detailVersion++;
    detailLoading = false;
    detail = null;
    detailError = null;
  }
}
