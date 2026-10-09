import 'package:flutter/material.dart';
import 'package:shupick_staff_mockup/auth/staff_session.dart';
import 'package:shupick_staff_mockup/dashboard/staff_order_api.dart';
import 'package:shupick_staff_mockup/dashboard/staff_views.dart';
import 'package:shupick_staff_mockup/dashboard/staff_work_api.dart';
import 'package:shupick_staff_mockup/dashboard/staff_analytics_data.dart';

const _blue = Color(0xFF2563C6);
const _ink = Color(0xFF1B2B40);
const _muted = Color(0xFF66768B);
const _line = Color(0xFFE2E8F0);
const _red = Color(0xFFCF3948);

class OverviewMetric {
  const OverviewMetric(this.label, this.value, this.caption);

  final String label;
  final String value;
  final String caption;
}

class OverviewAlert {
  const OverviewAlert(this.title, this.description, this.view);

  final String title;
  final String description;
  final StaffView view;
}

class OverviewSnapshot {
  const OverviewSnapshot(this.metrics, this.alerts, {this.warnings = const []});

  final List<OverviewMetric> metrics;
  final List<OverviewAlert> alerts;
  final List<String> warnings;
}

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

class StaffOverview extends StatefulWidget {
  const StaffOverview({
    super.key,
    required this.roleKey,
    required this.selectedBranchId,
    required this.onOpenView,
    this.orderRepository,
    this.workApi,
  });

  final String roleKey;
  final int? selectedBranchId;
  final ValueChanged<StaffView> onOpenView;
  final StaffOrderRepository? orderRepository;
  final StaffWorkApi? workApi;

  @override
  State<StaffOverview> createState() => _StaffOverviewState();
}

class _StaffOverviewState extends State<StaffOverview> {
  late final StaffOrderRepository _orders;
  late final StaffWorkApi _work;
  OverviewSnapshot? _snapshot;
  String? _error;
  bool _loading = false;
  int _requestNumber = 0;

  @override
  void initState() {
    super.initState();
    _orders = widget.orderRepository ?? MockStaffOrderRepository();
    _work = widget.workApi ?? StaffWorkApi();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant StaffOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roleKey != widget.roleKey ||
        oldWidget.selectedBranchId != widget.selectedBranchId) {
      _refresh();
    }
  }

  Future<OverviewSnapshot> _fetch() async {
    if (widget.roleKey == 'branchStaff' || widget.roleKey == 'branchManager') {
      final branchId = widget.selectedBranchId;
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
        load('주문', () => _orders.listOrders(branchId: branchId)),
        load('반품', () => _work.returns(branchId: branchId)),
        load('보관 재고', () => _work.inventory(branchId: branchId)),
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
    if (widget.roleKey == 'hqStaff') {
      final results = await Future.wait<dynamic>([
        _orders.listOrders(),
        _work.inquiries(),
        _work.returns(),
        _work.inventory(),
      ]);
      return headquartersStaffOverview(
        results[0] as List<StaffOrder>,
        results[1] as List<Map<String, dynamic>>,
        results[2] as List<Map<String, dynamic>>,
        results[3] as Map<String, dynamic>,
      );
    }
    if (widget.roleKey == 'teamLeader' || widget.roleKey == 'director') {
      final results = await Future.wait<dynamic>([
        _work.requisitions(),
        _work.inventory(),
      ]);
      return approverOverview(
        widget.roleKey,
        results[0] as List<Map<String, dynamic>>,
        results[1] as Map<String, dynamic>,
      );
    }
    final results = await Future.wait<dynamic>([
      _work.analytics(days: 28),
      _work.requisitions(),
      _work.inventory(),
    ]);
    return executiveOverview(
      results[0] as Map<String, dynamic>,
      results[1] as List<Map<String, dynamic>>,
      results[2] as Map<String, dynamic>,
    );
  }

  Future<void> _refresh() async {
    final request = ++_requestNumber;
    setState(() {
      _loading = true;
      _snapshot = null;
      _error = null;
    });
    try {
      final result = await _fetch();
      if (mounted && request == _requestNumber) {
        setState(() => _snapshot = result);
      }
    } on StaffAuthException catch (error) {
      if (mounted && request == _requestNumber) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted && request == _requestNumber) {
        setState(() => _error = '대시보드 데이터를 불러오지 못했습니다.');
      }
    } finally {
      if (mounted && request == _requestNumber) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final branch =
        widget.roleKey == 'branchStaff' || widget.roleKey == 'branchManager';
    final snapshot =
        _snapshot ??
        (branch
            ? OverviewSnapshot([
                for (final label in [
                  '입고 확인 대기',
                  '고객 수령 대기',
                  '반품 요청',
                  '현재 보관 수량',
                ])
                  OverviewMetric(label, '—', _loading ? '조회 중' : '조회할 수 없음'),
              ], const [])
            : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '업무 현황',
                style: TextStyle(
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('새로고침'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: _red)),
          ),
        if (snapshot != null) ...[
          if (snapshot.warnings.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5E5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                snapshot.warnings.join('\n'),
                style: const TextStyle(color: _red),
              ),
            ),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 440
                  ? 2
                  : 1;
              const gap = 12.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final metric in snapshot.metrics)
                    SizedBox(
                      width: width,
                      child: _OverviewCard(metric: metric),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            '빠른 업무',
            style: const TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final menu in menusForRole(
                widget.roleKey,
              ).where((menu) => menu.view != StaffView.overview))
                OutlinedButton.icon(
                  onPressed: () => widget.onOpenView(menu.view),
                  icon: Icon(menu.icon, size: 18),
                  label: Text(menu.label),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '업무 알림 · ${snapshot.alerts.length}건',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                if (snapshot.alerts.isEmpty)
                  Text(
                    _loading || _error != null || snapshot.warnings.isNotEmpty
                        ? '조회가 완료된 데이터의 업무 알림이 표시됩니다.'
                        : '현재 확인할 업무 알림이 없습니다.',
                    style: const TextStyle(color: _muted),
                  ),
                for (final alert in snapshot.alerts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: const Color(0xFFF8FBFF),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: _line),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        title: Text(alert.title),
                        subtitle: Text(alert.description),
                        trailing: const Icon(Icons.chevron_right, color: _blue),
                        onTap: () => widget.onOpenView(alert.view),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.metric});

  final OverviewMetric metric;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 120),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(metric.label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 12),
        Text(
          metric.value,
          style: const TextStyle(
            color: _ink,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          metric.caption,
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    ),
  );
}
