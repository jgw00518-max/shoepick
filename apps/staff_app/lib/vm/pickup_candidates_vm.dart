import 'package:get/get.dart';
import 'dart:math';
import '../model/pickup_candidate.dart';

/// 입고·수령 조회와 도착·정상 검수 기록을 담당한다. 재고·수령 완료는 별도다.
class PickupCandidatesVm extends GetxController {
  PickupCandidatesVm({
    required this.read,
    required this.arrival,
    this.branchId,
    this.submit,
  });
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  submit;
  bool saving = false;
  String? saveError;
  final Map<int, String> _arrivalKeys = {};
  final Map<int, String> _inspectionKeys = {};
  final Map<int, String> _readyKeys = {};

  /// 검수 기록 후 서버의 D 보관·C/A 상태 전이를 실행한다. 전달 완료는 별도다.
  Future<bool> confirmReady(int id) async {
    if (isClosed ||
        saving ||
        !arrival ||
        !inspection ||
        submit == null ||
        detail?['fulfillment_id'] != id ||
        detail?['fulfillment_status'] != 'INSPECTING' ||
        detail?['inspected_at'] == null) {
      return false;
    }
    saving = true;
    saveError = null;
    update();
    final key = _readyKeys.putIfAbsent(
      id,
      () =>
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
    );
    try {
      final result = await submit!(
        '/api/v1/order-history/staff/fulfillments/$id/ready',
        {'request_id': key, 'confirmed': true},
      );
      if (isClosed) return false;
      if (result['fulfillment_id'] != id ||
          result['order_status'] != 'READY_FOR_PICKUP' ||
          result['completed'] != true) {
        throw StateError('수령 준비 응답을 확인하지 못했습니다.');
      }
      _readyKeys.remove(id);
      await fetch(targetPage: page);
      return !isClosed;
    } catch (_) {
      if (!isClosed) saveError = '수령 준비 결과를 확인하지 못했습니다. 같은 배송으로 재시도해주세요.';
      return false;
    } finally {
      if (!isClosed) {
        saving = false;
        update();
      }
    }
  }

  /// 정상 검수 관찰만 저장한다. 보관 재고와 수령 가능 상태는 변경하지 않는다.
  Future<bool> confirmInspection(int id) async {
    if (isClosed ||
        saving ||
        !arrival ||
        !inspection ||
        submit == null ||
        detail?['fulfillment_status'] != 'ARRIVED') {
      return false;
    }
    saving = true;
    saveError = null;
    update();
    final key = _inspectionKeys.putIfAbsent(
      id,
      () =>
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
    );
    try {
      final result = await submit!(
        '/api/v1/order-history/staff/fulfillments/$id/inspection',
        {'request_id': key, 'all_items_normal': true},
      );
      if (isClosed) return false;
      if (result['fulfillment_id'] != id ||
          result['fulfillment_status'] != 'INSPECTING') {
        throw StateError('검수 응답을 확인하지 못했습니다.');
      }
      _inspectionKeys.remove(id);
      await fetch(targetPage: page);
      return !isClosed;
    } catch (_) {
      if (!isClosed) saveError = '검수 결과를 확인하지 못했습니다. 같은 배송으로 재시도해주세요.';
      return false;
    } finally {
      if (!isClosed) {
        saving = false;
        update();
      }
    }
  }

  /// 실제 도착 확인만 실행한다. 검수·수령 가능 처리는 별도다.
  Future<bool> confirmArrival(int id) async {
    if (isClosed || saving || !arrival || inspection || submit == null) {
      return false;
    }
    saving = true;
    saveError = null;
    update();
    final key = _arrivalKeys.putIfAbsent(
      id,
      () =>
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
    );
    try {
      final result = await submit!(
        '/api/v1/order-history/staff/fulfillments/$id/arrival',
        {'request_id': key, 'received_product': true},
      );
      if (isClosed) return false;
      if (result['fulfillment_id'] != id ||
          result['fulfillment_status'] != 'ARRIVED') {
        throw StateError('도착 응답을 확인하지 못했습니다.');
      }
      _arrivalKeys.remove(id);
      await fetch(targetPage: page);
      return !isClosed;
    } catch (_) {
      if (!isClosed) saveError = '도착 결과를 확인하지 못했습니다. 같은 배송으로 재시도해주세요.';
      return false;
    } finally {
      if (!isClosed) {
        saving = false;
        update();
      }
    }
  }

  final Future<Map<String, dynamic>> Function(String) read;
  final bool arrival;
  final int? branchId;
  bool inspection = false;
  int _listVersion = 0;

  /// 단계가 바뀌면 이전 조회 응답과 상세를 폐기하고 첫 페이지를 조회한다.
  Future<void> selectInspection(bool value) async {
    if (!arrival || saving || isClosed || inspection == value) return;
    inspection = value;
    _listVersion++;
    loading = false;
    page = 1;
    total = 0;
    rows = [];
    saveError = null;
    closeDetail();
    await fetch();
  }

  String get _detailPath => !arrival
      ? 'pickup-candidates'
      : inspection
      ? 'inspection-candidates'
      : 'arrival-candidates';
  bool loading = false;
  String? error;
  List<PickupCandidate> rows = [];
  int page = 1;
  int total = 0;
  bool get hasNext => page * 20 < total;
  bool detailLoading = false;
  String? detailError;
  Map<String, dynamic>? detail;
  int _detailVersion = 0;
  Future<void> fetchDetail(int id) async {
    if (detailLoading || isClosed) return;
    final version = ++_detailVersion;
    detailLoading = true;
    detail = null;
    detailError = null;
    update();
    try {
      final response = await read(
        '/api/v1/order-history/staff/$_detailPath/$id',
      );
      if (!isClosed && version == _detailVersion) {
        detail = Map<String, dynamic>.from(response['data'] as Map);
      }
    } catch (e) {
      if (!isClosed && version == _detailVersion) {
        detailError = e is StateError
            ? e.message.toString()
            : '상세 정보를 불러오지 못했습니다.';
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

  @override
  void onInit() {
    super.onInit();
    fetch();
  }

  Future<void> fetch({int targetPage = 1}) async {
    if (loading || isClosed) return;
    final version = ++_listVersion;
    loading = true;
    rows = [];
    error = null;
    update();
    try {
      final response = await read(
        '/api/v1/order-history/staff/${arrival ? 'arrival-candidates' : 'pickup-candidates'}?page=$targetPage&page_size=20${branchId == null ? '' : '&branch_id=$branchId'}${arrival && inspection ? '&stage=inspection' : ''}',
      );
      if (isClosed || version != _listVersion) return;
      rows = (response['data'] as List)
          .map((r) => PickupCandidate(Map<String, dynamic>.from(r as Map)))
          .toList();
      page = response['pagination']['page'] as int;
      total = response['pagination']['total_count'] as int;
    } catch (e) {
      if (!isClosed && version == _listVersion) {
        error = e is StateError ? e.message.toString() : '목록을 불러오지 못했습니다.';
      }
    } finally {
      if (!isClosed && version == _listVersion) {
        loading = false;
        update();
      }
    }
  }
}
