import 'package:shoepick_staff_app/model/staff_analytics_data.dart';
import 'package:shoepick_staff_app/model/staff_order.dart';
import 'package:shoepick_staff_app/model/staff_overview.dart';
import 'package:shoepick_staff_app/model/staff_session.dart';
import 'package:shoepick_staff_app/model/staff_views.dart';
import 'package:shoepick_staff_app/vm/staff_order_api.dart';
import 'package:shoepick_staff_app/vm/staff_work_api.dart';

int _count<T>(Iterable<T> values, bool Function(T) matches) =>
    values.where(matches).length;

List<Map<String, dynamic>> _inventoryRows(Map<String, dynamic> inventory) =>
    (inventory['rows'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

List<Map<String, dynamic>> _lowStock(Map<String, dynamic> inventory) =>
    _inventoryRows(inventory).where((row) {
      final target = (row['target_quantity'] as num?) ?? 0;
      final available = (row['available_quantity'] as num?) ?? 0;
      return target > 0 && available / target < .3;
    }).toList();

String _money(num value) {
  final digits = value.round().toString();
  return '₩${digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';
}

OverviewSnapshot branchOverview(
  List<StaffOrder> orders,
  List<Map<String, dynamic>> returns,
  Map<String, dynamic> inventory,
) {
  final arriving = _count(
    orders,
    (order) => order.fulfillmentStatus == 'IN_TRANSIT',
  );
  final ready = _count(orders, (order) => order.status == 'READY_FOR_PICKUP');
  final requestedReturns = _count(
    returns,
    (row) => row['status'] == 'REQUESTED',
  );
  final held = _inventoryRows(inventory).fold<int>(
    0,
    (total, row) => total + (num.tryParse('${row['quantity']}') ?? 0).toInt(),
  );
  return OverviewSnapshot(
    [
      OverviewMetric('입고 확인 대기', '$arriving건', '최근 주문 100건 기준'),
      OverviewMetric('고객 수령 대기', '$ready건', '최근 주문 100건 기준'),
      OverviewMetric('반품 요청', '$requestedReturns건', '최근 반품 100건 기준'),
      OverviewMetric('현재 보관 수량', '$held켤레', '소속 지점 현재 기준'),
    ],
    [
      if (arriving > 0)
        OverviewAlert(
          '입고 확인 필요',
          '배송 중 주문 $arriving건의 실물 도착을 확인하세요.',
          StaffView.inbound,
        ),
      if (ready > 0)
        OverviewAlert(
          '고객 수령 대기',
          '수령 대기 주문 $ready건의 픽업 결제 코드를 확인하세요.',
          StaffView.pickup,
        ),
      if (requestedReturns > 0)
        OverviewAlert(
          '반품 요청 확인',
          '소속 지점 반품 요청 $requestedReturns건의 상태를 확인하세요.',
          StaffView.returns,
        ),
    ],
  );
}

OverviewSnapshot headquartersStaffOverview(
  List<StaffOrder> orders,
  List<Map<String, dynamic>> inquiries,
  List<Map<String, dynamic>> returns,
  Map<String, dynamic> inventory,
) {
  final preparing = _count(
    orders,
    (order) => order.fulfillmentStatus == 'PREPARING',
  );
  final unanswered = _count(inquiries, (row) => row['status'] != 'ANSWERED');
  final inspections = _count(returns, (row) => row['status'] == 'REQUESTED');
  final low = _lowStock(inventory);
  return OverviewSnapshot(
    [
      OverviewMetric('발송 대기', '$preparing건', '최근 주문 100건 기준'),
      OverviewMetric('미답변 문의', '$unanswered건', '최근 문의 100건 기준'),
      OverviewMetric('반품 검수 대기', '$inspections건', '최근 반품 100건 기준'),
      OverviewMetric('가용 재고 부족', '${low.length}종', '목표의 30% 미만'),
    ],
    [
      if (preparing > 0)
        OverviewAlert(
          '발송 처리 필요',
          '발송 대기 주문 $preparing건이 있습니다.',
          StaffView.shipping,
        ),
      if (unanswered > 0)
        OverviewAlert(
          '고객 문의 답변 필요',
          '미답변 문의 $unanswered건이 있습니다.',
          StaffView.customers,
        ),
      if (inspections > 0)
        OverviewAlert(
          '반품 검수 필요',
          '검수 대기 요청 $inspections건이 있습니다.',
          StaffView.returns,
        ),
      if (low.isNotEmpty)
        OverviewAlert(
          '가용 재고 부족',
          '${low.length}개 제품 옵션의 가용 재고가 목표의 30% 미만입니다.',
          StaffView.inventory,
        ),
    ],
  );
}

OverviewSnapshot approverOverview(
  String roleKey,
  List<Map<String, dynamic>> requisitions,
  Map<String, dynamic> inventory,
) {
  final pendingStatus = roleKey == 'teamLeader'
      ? 'PENDING_TEAM_LEAD'
      : 'PENDING_DIRECTOR';
  final pending = _count(requisitions, (row) => row['status'] == pendingStatus);
  final approved = _count(requisitions, (row) => row['status'] == 'APPROVED');
  final rejected = _count(requisitions, (row) => row['status'] == 'REJECTED');
  final low = _lowStock(inventory);
  final stage = roleKey == 'teamLeader' ? '1차' : '최종';
  return OverviewSnapshot(
    [
      OverviewMetric('$stage 결재 대기', '$pending건', '최근 품의 100건 기준'),
      OverviewMetric('승인 완료', '$approved건', '최근 품의 100건 기준'),
      OverviewMetric('반려', '$rejected건', '최근 품의 100건 기준'),
      OverviewMetric('가용 재고 부족', '${low.length}종', '목표의 30% 미만'),
    ],
    [
      if (pending > 0)
        OverviewAlert(
          '$stage 결재 필요',
          '검토 대기 품의 $pending건이 있습니다.',
          StaffView.approvals,
        ),
      if (low.isNotEmpty)
        OverviewAlert(
          '가용 재고 부족',
          '${low.length}개 제품 옵션의 가용 재고가 목표의 30% 미만입니다.',
          StaffView.inventory,
        ),
    ],
  );
}

OverviewSnapshot executiveOverview(
  Map<String, dynamic> analytics,
  List<Map<String, dynamic>> requisitions,
  Map<String, dynamic> inventory,
) {
  analytics = normalizeStaffAnalytics(analytics);
  final low = _lowStock(inventory);
  final pending = _count(
    requisitions,
    (row) =>
        row['status'] == 'PENDING_TEAM_LEAD' ||
        row['status'] == 'PENDING_DIRECTOR',
  );
  return OverviewSnapshot(
    [
      OverviewMetric('최근 28일 판매량', '${analytics['quantity']}켤레', '결제 완료 주문 기준'),
      OverviewMetric(
        '최근 28일 매출',
        _money(analytics['revenue'] as num),
        '주문 결제액 합계',
      ),
      OverviewMetric('최근 28일 주문', '${analytics['orderCount']}건', '결제 완료 주문 기준'),
      OverviewMetric('가용 재고 부족', '${low.length}종', '목표의 30% 미만'),
    ],
    [
      if (low.isNotEmpty)
        OverviewAlert(
          '가용 재고 부족',
          '${low.length}개 제품 옵션의 가용 재고가 목표의 30% 미만입니다.',
          StaffView.inventory,
        ),
      if (pending > 0)
        OverviewAlert(
          '결재 진행 중',
          '최근 품의 중 결재 대기 $pending건이 있습니다.',
          StaffView.approvals,
        ),
    ],
  );
}

class StaffOverviewVm {
  StaffOverviewVm({required this.orders, required this.work});
  final StaffOrderRepository orders;
  final StaffWorkApi work;

  Future<OverviewSnapshot> fetch({
    required String roleKey,
    required int? selectedBranchId,
  }) async {
    if (roleKey == 'branchStaff' || roleKey == 'branchManager') {
      final branchId = selectedBranchId;
      if (branchId == null) {
        throw const StaffAuthException('조회할 소속 지점이 없습니다.');
      }
      final warnings = <String>[];
      Future<T?> load<T>(String label, Future<T> Function() fetch) async {
        try {
          return await fetch();
        } on StaffAuthException catch (error) {
          warnings.add('$label: ${error.message}');
        } catch (_) {
          warnings.add('$label: 조회 결과를 처리하지 못했습니다.');
        }
        return null;
      }

      final results = await Future.wait<dynamic>([
        load('주문', () => orders.listOrders(branchId: branchId)),
        load('반품', () => work.returns(branchId: branchId)),
        load('보관 재고', () => work.inventory(branchId: branchId)),
      ]);
      final summary = branchOverview(
        results[0] as List<StaffOrder>? ?? [],
        results[1] as List<Map<String, dynamic>>? ?? [],
        results[2] as Map<String, dynamic>? ?? {'rows': []},
      );
      return OverviewSnapshot(
        [
          for (var index = 0; index < summary.metrics.length; index++)
            results[index < 2 ? 0 : index - 1] == null
                ? OverviewMetric(
                    summary.metrics[index].label,
                    '—',
                    '조회 실패 · 새로고침 필요',
                  )
                : summary.metrics[index],
        ],
        summary.alerts,
        warnings: warnings,
      );
    }
    if (roleKey == 'hqStaff') {
      final results = await Future.wait<dynamic>([
        orders.listOrders(),
        work.inquiries(),
        work.returns(),
        work.inventory(),
      ]);
      return headquartersStaffOverview(
        results[0] as List<StaffOrder>,
        results[1] as List<Map<String, dynamic>>,
        results[2] as List<Map<String, dynamic>>,
        results[3] as Map<String, dynamic>,
      );
    }
    if (roleKey == 'teamLeader' || roleKey == 'director') {
      final results = await Future.wait<dynamic>([
        work.requisitions(),
        work.inventory(),
      ]);
      return approverOverview(
        roleKey,
        results[0] as List<Map<String, dynamic>>,
        results[1] as Map<String, dynamic>,
      );
    }
    final results = await Future.wait<dynamic>([
      work.analytics(days: 28),
      work.requisitions(),
      work.inventory(),
    ]);
    return executiveOverview(
      results[0] as Map<String, dynamic>,
      results[1] as List<Map<String, dynamic>>,
      results[2] as Map<String, dynamic>,
    );
  }
}
