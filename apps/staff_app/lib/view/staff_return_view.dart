import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../model/staff_return.dart';
import '../vm/staff_return_vm.dart';
import '../vm/auth_api.dart';

/// 반품 조회·검수·결정과 정상 재판매 반품 모의 완료를 제공한다.
class StaffReturnView extends StatefulWidget {
  const StaffReturnView({
    super.key,
    required this.read,
    this.branchId,
    this.write,
  });
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  write;
  final Future<Map<String, dynamic>> Function(String) read;
  final int? branchId;
  @override
  State<StaffReturnView> createState() => _StaffReturnViewState();
}

class _StaffReturnViewState extends State<StaffReturnView> {
  late final StaffReturnVm _vm;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    _vm = StaffReturnVm(
      read: widget.read,
      branchId: widget.branchId,
      write: widget.write ?? (path, body) => AuthApi().post(path, body),
    );
    _vm.onStart();
  }

  @override
  void dispose() {
    _vm.onDelete();
    super.dispose();
  }

  Future<void> _open(int id) async {
    if (_opening || _vm.isClosed) return;
    _opening = true;
    _vm.fetchDetail(id);
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => GetBuilder<StaffReturnVm>(
          init: _vm,
          global: false,
          autoRemove: false,
          builder: (vm) => AlertDialog(
            title: const Text('반품 상세'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: vm.detailLoading
                    ? const CircularProgressIndicator()
                    : vm.detailError != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(vm.detailError!),
                          TextButton(
                            onPressed: () => vm.fetchDetail(id),
                            child: const Text('상세 다시 시도'),
                          ),
                        ],
                      )
                    : vm.detail == null
                    ? const Text('상세 정보가 없습니다.')
                    : _detail(vm.detail!),
              ),
            ),
            actions: [
              if (vm.detail?.data['request_status'] == 'APPROVED')
                FilledButton(
                  onPressed: vm.saving
                      ? null
                      : () async {
                          final accepted = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('정상 반품 모의 환불 완료'),
                              content: const Text(
                                '본사에서 전체 반환 상품을 실제로 받았고 정상 재판매가 가능함을 확인했습니까? 정상 재고 복원과 모의 환불을 함께 처리합니다. 파손·불량이나 혜택 사용 주문은 처리할 수 없습니다. 본사 사원만 실행할 수 있습니다.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('취소'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('회수·재판매 확인 후 처리'),
                                ),
                              ],
                            ),
                          );
                          if (accepted != true ||
                              !context.mounted ||
                              vm.isClosed) {
                            return;
                          }
                          await vm.completeMock(id);
                        },
                  child: Text(vm.saving ? '처리 중' : '정상 반품 모의 환불 완료'),
                ),
              if (vm.detail != null &&
                  [
                    'REQUESTED',
                    'COLLECTING',
                    'INSPECTING',
                  ].contains(vm.detail!.data['request_status']))
                TextButton(
                  onPressed: vm.saving
                      ? null
                      : () => _inspectionForm(context, id),
                  child: const Text('검수 관찰 기록'),
                ),
              if (vm.saveError != null) Text(vm.saveError!),
              if (vm.detail?.data['request_status'] == 'INSPECTING' &&
                  (vm.detail!.data['inspections'] as List? ?? []).any(
                    (record) =>
                        record['inspection_stage'] == 'HEADQUARTERS' &&
                        record['inspection_decision'] == 'PENDING',
                  ))
                TextButton(
                  onPressed: vm.saving
                      ? null
                      : () => _decisionForm(context, id),
                  child: const Text('최종 승인·거절 (본사 사원 전용)'),
                ),
              TextButton(
                onPressed: vm.saving ? null : () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _vm.closeDetail();
      _opening = false;
    }
  }

  Future<void> _inspectionForm(BuildContext context, int id) async {
    final pending = _vm.pendingInspection(id);
    var stage = pending?['inspection_stage'] as String? ?? 'BRANCH';
    var received = pending?['received_product'] as bool? ?? false;
    var notes = pending?['inspection_notes'] as String? ?? '';
    final flags = <String, bool>{
      'has_wear_marks': false,
      'has_product_damage': false,
      'has_customer_fault': false,
      'components_complete': true,
      'packaging_intact': true,
      'has_product_defect': false,
      'is_wrong_item': false,
    };
    final labels = {
      'has_wear_marks': '착용 흔적',
      'has_product_damage': '상품 파손',
      'has_customer_fault': '고객 과실 관찰',
      'components_complete': '구성품 완비',
      'packaging_intact': '포장 정상',
      'has_product_defect': '상품 하자',
      'is_wrong_item': '오배송',
    };
    if (pending != null) {
      for (final key in flags.keys) {
        flags[key] = pending[key] as bool;
      }
    }
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('검수 관찰 기록'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('단계별 최초 1건만 저장합니다. 단계 권한은 서버에서 검사합니다.'),
                  DropdownButton<String>(
                    value: stage,
                    items: const [
                      DropdownMenuItem(value: 'BRANCH', child: Text('대리점 검수')),
                      DropdownMenuItem(
                        value: 'HEADQUARTERS',
                        child: Text('본사 검수'),
                      ),
                    ],
                    onChanged: (value) => setState(() => stage = value!),
                  ),
                  CheckboxListTile(
                    title: const Text('실제로 반환된 상품을 받았습니다'),
                    value: received,
                    onChanged: (value) => setState(() => received = value!),
                  ),
                  for (final entry in flags.entries)
                    CheckboxListTile(
                      title: Text(labels[entry.key]!),
                      value: entry.value,
                      onChanged: (value) =>
                          setState(() => flags[entry.key] = value!),
                    ),
                  TextFormField(
                    initialValue: notes,
                    decoration: const InputDecoration(labelText: '검수 메모'),
                    onChanged: (value) => setState(() => notes = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
            TextButton(
              onPressed: !received || notes.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, {
                      'inspection_stage': stage,
                      'received_product': true,
                      ...flags,
                      'inspection_notes': notes.trim(),
                    }),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    if (body != null && context.mounted && !_vm.isClosed) {
      final saved = await _vm.saveInspection(id, body);
      if (saved && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('검수 관찰 결과가 저장되었습니다. 승인·환불 완료가 아닙니다.')),
        );
      }
    }
  }

  Future<void> _decisionForm(BuildContext context, int id) async {
    final pending = _vm.pendingDecision(id);
    var decision = pending?['decision'] as String? ?? 'APPROVED';
    var reason = pending?['rejection_reason'] as String? ?? '';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('반품 최종 결정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '본사 사원만 결정할 수 있습니다. 저장 후 결정을 변경할 수 없으며, 승인해도 환불은 실행되지 않습니다.',
              ),
              DropdownButton<String>(
                value: decision,
                items: const [
                  DropdownMenuItem(value: 'APPROVED', child: Text('최종 승인')),
                  DropdownMenuItem(value: 'REJECTED', child: Text('거절')),
                ],
                onChanged: (value) => setState(() => decision = value!),
              ),
              if (decision == 'REJECTED')
                TextFormField(
                  initialValue: reason,
                  decoration: const InputDecoration(labelText: '거절 사유 (필수)'),
                  onChanged: (value) => setState(() => reason = value),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('돌아가기'),
            ),
            TextButton(
              onPressed: decision == 'REJECTED' && reason.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, {
                      'decision': decision,
                      'rejection_reason': decision == 'REJECTED'
                          ? reason.trim()
                          : null,
                    }),
              child: const Text('결정 저장'),
            ),
          ],
        ),
      ),
    );
    if (result != null && context.mounted && !_vm.isClosed) {
      final saved = await _vm.saveDecision(
        id,
        result['decision'] as String,
        result['rejection_reason'] as String?,
      );
      if (saved && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('반품 최종 결정이 기록되었습니다. 환불 완료가 아닙니다.')),
        );
      }
    }
  }

  Widget _detail(StaffReturn row) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('주문 번호: ${row.number}'),
      Text('수령 대리점: ${row.branch}'),
      Text(row.statusLabel),
      Text('사유: ${row.data['return_reason'] ?? '정보 없음'}'),
      Text('접수 시각 (서버 기록): ${row.data['requested_at'] ?? '정보 없음'}'),
      if (row.data['rejection_reason'] != null)
        Text('거절 이유: ${row.data['rejection_reason']}'),
      const Divider(),
      const Text('반품 상품'),
      for (final item in row.data['items'] as List? ?? [])
        Text(
          '${item['product_name']} / ${item['color_name']} / ${item['size_mm']} mm · ${item['quantity']}개',
        ),
      const Divider(),
      const Text('검수 기록'),
      if ((row.data['inspections'] as List? ?? []).isEmpty)
        const Text('검수 기록이 없습니다.'),
      for (final item in row.data['inspections'] as List? ?? [])
        Text(
          '${item['inspection_stage']} · ${const {'PENDING': '판정 대기', 'ACCEPTED': '수락', 'REJECTED': '거절'}[item['inspection_decision']] ?? '확인되지 않은 상태'}\n${item['inspected_at']}\n${item['inspection_notes'] ?? ''}',
        ),
      const Divider(),
      const Text('환불 기록'),
      if ((row.data['refunds'] as List? ?? []).isEmpty)
        const Text('환불 기록이 없습니다.'),
      for (final item in row.data['refunds'] as List? ?? [])
        Text(
          '${const {'REQUESTED': '환불 요청', 'PROCESSING': '환불 진행 중', 'SUCCEEDED': '환불 완료', 'FAILED': '환불 실패', 'CANCELED': '환불 취소'}[item['refund_status']] ?? '확인되지 않은 상태'} · ${item['refund_amount']}원${item['completed_at'] == null ? '' : '\n완료 시각 (서버 기록): ${item['completed_at']}'}',
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => GetBuilder<StaffReturnVm>(
    init: _vm,
    global: false,
    autoRemove: false,
    builder: (vm) {
      if (vm.loading) return const Center(child: CircularProgressIndicator());
      if (vm.error != null) {
        return Column(
          children: [
            Text(vm.error!),
            TextButton(
              onPressed: () => vm.fetch(targetPage: vm.page),
              child: const Text('다시 시도'),
            ),
          ],
        );
      }
      return ListView(
        shrinkWrap: true,
        children: [
          const Text('반품 접수 조회 · 검수·환불 실행은 준비 중입니다.'),
          if (vm.rows.isEmpty) const Text('반품 접수가 없습니다.'),
          for (final row in vm.rows)
            ListTile(
              title: Text(row.number),
              subtitle: Text('${row.branch} · ${row.statusLabel}'),
              onTap: () => _open(row.id),
            ),
          Row(
            children: [
              TextButton(
                onPressed: vm.page > 1
                    ? () => vm.fetch(targetPage: vm.page - 1)
                    : null,
                child: const Text('이전'),
              ),
              Text('${vm.page}'),
              TextButton(
                onPressed: vm.hasNext
                    ? () => vm.fetch(targetPage: vm.page + 1)
                    : null,
                child: const Text('다음'),
              ),
            ],
          ),
        ],
      );
    },
  );
}
