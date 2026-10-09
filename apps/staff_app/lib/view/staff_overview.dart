import 'package:flutter/material.dart';
import 'package:shupick_staff_mockup/model/staff_overview.dart';
import 'package:shupick_staff_mockup/model/staff_session.dart';
import 'package:shupick_staff_mockup/model/staff_views.dart';
import 'package:shupick_staff_mockup/vm/staff_order_api.dart';
import 'package:shupick_staff_mockup/vm/staff_overview_vm.dart';
import 'package:shupick_staff_mockup/vm/staff_work_api.dart';

const _blue = Color(0xFF2563C6);
const _ink = Color(0xFF1B2B40);
const _muted = Color(0xFF66768B);
const _line = Color(0xFFE2E8F0);
const _red = Color(0xFFCF3948);

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

  Future<OverviewSnapshot> _fetch() => StaffOverviewVm(
    orders: _orders,
    work: _work,
  ).fetch(roleKey: widget.roleKey, selectedBranchId: widget.selectedBranchId);

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
