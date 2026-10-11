import 'package:get/get.dart';
import 'dart:math';

/// 직원 문의 상태는 화면 범위로 소유하며 인증·역할 검사는 서버에 맡긴다.
class StaffInquiryVm extends GetxController {
  StaffInquiryVm({required this.read, this.write});
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  write;
  bool saving = false;
  String? answerError;
  Map<String, dynamic>? _pendingAnswer;
  int? _pendingInquiry;
  final Future<Map<String, dynamic>> Function(String) read;
  bool loading = false;
  bool detailLoading = false;
  String? error;
  String? detailError;
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? detail;
  String? status;
  int page = 1;
  int total = 0;
  int _version = 0;
  bool get hasNext => page * 20 < total;
  String pendingAnswer(int id) => _pendingInquiry == id
      ? (_pendingAnswer?['response_content'] as String? ?? '')
      : '';

  /// 실패 후 같은 답변 재전송은 요청 ID를 유지한다. 미확인 결과를 새 답변으로 덮지 않는다.
  Future<bool> answer(int id, String content) async {
    if (isClosed || saving || write == null) return false;
    final text = content.trim();
    if (text.isEmpty) {
      answerError = '답변 내용을 입력해주세요.';
      update();
      return false;
    }
    if (_pendingAnswer != null &&
        (_pendingInquiry != id ||
            _pendingAnswer!['response_content'] != text)) {
      answerError = '이전 답변의 결과가 확인되지 않았습니다. 같은 내용으로 다시 시도해주세요.';
      update();
      return false;
    }
    _pendingInquiry = id;
    _pendingAnswer ??= {
      'response_content': text,
      'request_id':
          'answer-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
    };
    saving = true;
    answerError = null;
    update();
    try {
      final result = await write!(
        '/api/v1/order-history/inquiries/staff/$id/responses',
        Map.of(_pendingAnswer!),
      );
      if (isClosed) return false;
      if (result['inquiry_response_id'] is! int) {
        throw StateError('답변 저장 결과를 확인하지 못했습니다.');
      }
      _pendingAnswer = null;
      _pendingInquiry = null;
      await loadDetail(id);
      await fetch(targetPage: page);
      return !isClosed;
    } catch (e) {
      if (!isClosed) {
        answerError = e is StateError
            ? e.message.toString()
            : '답변 저장 결과를 확인하지 못했습니다. 같은 내용으로 다시 시도해주세요.';
      }
      return false;
    } finally {
      if (!isClosed) {
        saving = false;
        update();
      }
    }
  }

  @override
  void onInit() {
    super.onInit();
    fetch();
  }

  Future<void> fetch({int targetPage = 1}) async {
    if (loading || isClosed) return;
    loading = true;
    rows = [];
    error = null;
    update();
    try {
      final response = await read(
        '/api/v1/order-history/inquiries/staff?page=$targetPage&page_size=20${status == null ? '' : '&inquiry_status=$status'}',
      );
      if (isClosed) return;
      rows = (response['data'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      page = response['pagination']['page'] as int;
      total = response['pagination']['total_count'] as int;
    } catch (e) {
      if (!isClosed) {
        error = e is StateError ? e.message.toString() : '문의 조회에 실패했습니다.';
      }
    } finally {
      if (!isClosed) {
        loading = false;
        update();
      }
    }
  }

  Future<void> loadDetail(int id) async {
    if (detailLoading || isClosed) return;
    final version = ++_version;
    detailLoading = true;
    detail = null;
    detailError = null;
    update();
    try {
      final response = await read('/api/v1/order-history/inquiries/staff/$id');
      if (!isClosed && version == _version) {
        detail = Map<String, dynamic>.from(response['data'] as Map);
      }
    } catch (e) {
      if (!isClosed && version == _version) {
        detailError = e is StateError
            ? e.message.toString()
            : '문의 상세 조회에 실패했습니다.';
      }
    } finally {
      if (!isClosed && version == _version) {
        detailLoading = false;
        update();
      }
    }
  }

  void closeDetail() {
    _version++;
    detail = null;
    detailLoading = false;
    detailError = null;
  }
}
