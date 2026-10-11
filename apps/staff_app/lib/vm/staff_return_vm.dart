import 'package:get/get.dart';
import 'dart:convert';
import 'dart:math';
import '../model/staff_return.dart';

/// 지점별 조회 상태를 소유하며 화면 종료·상세 닫힘 후 응답은 버린다.
class StaffReturnVm extends GetxController {
  StaffReturnVm({required this.read, this.branchId, this.write});
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  write;
  bool saving = false;
  String? saveError;
  Map<String, dynamic>? _pending;
  int? _pendingId;
  String? _pendingAction;
  Map<String, dynamic>? pendingInspection(int id) =>
      _pendingId == id && _pendingAction == 'inspection' && _pending != null
      ? ({..._pending!}..remove('request_id'))
      : null;
  Future<bool> saveInspection(int id, Map<String, dynamic> body) async {
    return _saveAction(id, body, 'inspection', 'after_sales_inspection_id');
  }

  Map<String, dynamic>? pendingDecision(int id) =>
      _pendingId == id && _pendingAction == 'decision' && _pending != null
      ? ({..._pending!}..remove('request_id'))
      : null;

  Future<bool> saveDecision(int id, String decision, String? rejectionReason) =>
      _saveAction(
        id,
        {'decision': decision, 'rejection_reason': rejectionReason},
        'decision',
        'return_request_id',
      );

  /// 정상 재판매 확인만 전달한다. 권한·금액·재고·최종 상태는 서버가 결정한다.
  Future<bool> completeMock(int id) {
    if (detail?.id != id || detail?.data['request_status'] != 'APPROVED') {
      return Future.value(false);
    }
    return _saveAction(
      id,
      {'resale_confirmed': true},
      'complete-mock',
      'return_request_id',
    );
  }

  /// 검수와 최종 결정이 동시에 전송되지 않도록 동일 저장 상태를 공유한다.
  Future<bool> _saveAction(
    int id,
    Map<String, dynamic> body,
    String action,
    String resultField,
  ) async {
    if (isClosed || saving || write == null) return false;
    if (_pending != null &&
        (_pendingId != id ||
            _pendingAction != action ||
            jsonEncode({..._pending!}..remove('request_id')) !=
                jsonEncode(body))) {
      saveError = '이전 요청 결과가 불명확합니다. 같은 내용으로 재시도해주세요.';
      update();
      return false;
    }
    _pendingId = id;
    _pendingAction = action;
    _pending ??= {
      ...body,
      'request_id':
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
    };
    saving = true;
    saveError = null;
    update();
    final detailVersion = _detailVersion;
    try {
      final result = await write!(
        '/api/v1/order-history/staff/returns/$id/$action',
        _pending!,
      );
      if (result[resultField] is! int) {
        throw StateError('Invalid response');
      }
      if (action == 'complete-mock' &&
          (result['return_request_id'] != id ||
              result['request_status'] != 'COMPLETED' ||
              result['completed'] != true ||
              result['is_mock'] != true)) {
        throw StateError('Invalid completion response');
      }
      if (isClosed) return false;
      _pending = null;
      _pendingId = null;
      _pendingAction = null;
      if (detailVersion == _detailVersion) await fetchDetail(id);
      await fetch(targetPage: page);
      return true;
    } catch (_) {
      if (!isClosed) saveError = '저장 결과를 확인하지 못했습니다. 같은 내용으로 재시도해주세요.';
      return false;
    } finally {
      if (!isClosed) {
        saving = false;
        update();
      }
    }
  }

  final Future<Map<String, dynamic>> Function(String) read;
  final int? branchId;
  bool loading = false;
  String? error;
  List<StaffReturn> rows = [];
  int page = 1;
  int total = 0;
  bool get hasNext => page * 20 < total;
  bool detailLoading = false;
  String? detailError;
  StaffReturn? detail;
  int _detailVersion = 0;
  @override
  void onInit() {
    super.onInit();
    fetch();
  }

  Future<void> fetch({int targetPage = 1}) async {
    if (isClosed || loading) return;
    loading = true;
    error = null;
    rows = [];
    update();
    try {
      final response = await read(
        '/api/v1/order-history/staff/returns?page=$targetPage&page_size=20${branchId == null ? '' : '&branch_id=$branchId'}',
      );
      if (isClosed) return;
      rows = (response['data'] as List)
          .map((row) => StaffReturn(Map<String, dynamic>.from(row as Map)))
          .toList();
      page = response['pagination']['page'] as int;
      total = response['pagination']['total_count'] as int;
    } catch (_) {
      if (!isClosed) error = '반품 목록을 불러오지 못했습니다.';
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
    detail = null;
    detailError = null;
    update();
    try {
      final response = await read('/api/v1/order-history/staff/returns/$id');
      if (!isClosed && version == _detailVersion) {
        detail = StaffReturn(
          Map<String, dynamic>.from(response['data'] as Map),
        );
      }
    } catch (_) {
      if (!isClosed && version == _detailVersion) {
        detailError = '반품 상세를 불러오지 못했습니다.';
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
    detail = null;
    detailError = null;
    detailLoading = false;
  }
}
