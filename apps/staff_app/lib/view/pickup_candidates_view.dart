import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../vm/pickup_candidates_vm.dart';

/// 실조회와 미연결 실행을 구분한다. 메뉴가 바뀌면 컨트롤러를 폐기한다.
class PickupCandidatesView extends StatefulWidget {
  const PickupCandidatesView({
    super.key,
    required this.read,
    required this.arrival,
    this.branchId,
    this.submit,
  });
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  submit;
  final Future<Map<String, dynamic>> Function(String) read;
  final bool arrival;
  final int? branchId;
  @override
  State<PickupCandidatesView> createState() => _PickupCandidatesViewState();
}

class _PickupCandidatesViewState extends State<PickupCandidatesView> {
  late final PickupCandidatesVm _vm;
  @override
  void initState() {
    super.initState();
    _vm = PickupCandidatesVm(
      read: widget.read,
      arrival: widget.arrival,
      branchId: widget.branchId,
      submit: widget.submit,
    );
    _vm.onStart();
  }

  @override
  void dispose() {
    _vm.onDelete();
    super.dispose();
  }

  bool _opening = false;
  Future<void> _open(PickupCandidatesVm vm, int id) async {
    if (_opening || vm.isClosed) return;
    _opening = true;
    vm.fetchDetail(id);
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => GetBuilder<PickupCandidatesVm>(
          init: vm,
          global: false,
          autoRemove: false,
          builder: (state) => AlertDialog(
            title: Text(state.detail?['order_number'] as String? ?? '상품 상세'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: state.detailLoading
                    ? const Center(child: CircularProgressIndicator())
                    : state.detailError != null
                    ? Column(
                        children: [
                          Text(state.detailError!),
                          TextButton(
                            onPressed: () => state.fetchDetail(id),
                            child: const Text('상세 다시 시도'),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '수령 대리점: ${state.detail?['branch_name'] ?? '정보 없음'}',
                          ),
                          Text(
                            state.inspection
                                ? (state.detail?['inspected_at'] != null
                                      ? '정상 검수 기록이 있습니다. 수령 준비 완료를 누르면 보관 기록과 주문 상태를 함께 처리합니다. 인증·실제 전달은 별도입니다.'
                                      : '전체 상품·옵션·수량과 정상 상태를 실제로 확인한 경우에만 검수를 저장하세요. 재고 보관과 수령 가능 처리는 별도입니다.')
                                : widget.arrival
                                ? (widget.submit == null
                                      ? '주문 당시 상품과 도착 수량을 확인하세요. 입고·재고 변경은 아직 연결되지 않았습니다.'
                                      : '실제 도착을 확인할 수 있습니다. 정상 검수·재고 보관·수령 가능 처리는 별도입니다.')
                                : '주문 상품을 확인하세요. 이메일·바코드 수령 인증과 실제 전달 처리는 아직 연결되지 않았습니다.',
                          ),
                          if ((state.detail?['items'] as List? ?? []).isEmpty)
                            const Text('상품 정보가 없습니다.'),
                          if (state.saveError != null) Text(state.saveError!),
                          for (final item
                              in state.detail?['items'] as List? ?? []) ...[
                            const Divider(),
                            Text(
                              '${item['product_name']} · ${item['product_code']}',
                            ),
                            Text(
                              '옵션: ${item['color_name']} / ${item['size_mm']}',
                            ),
                            Text(
                              '${widget.arrival ? '배송' : '주문'} 수량: ${item['quantity']}',
                            ),
                            Text(
                              '단가: ${item['unit_price']}원 · 주문 항목 금액: ${item['line_total']}원',
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            actions: [
              if (widget.arrival &&
                  state.inspection &&
                  state.detail?['fulfillment_status'] == 'INSPECTING' &&
                  state.detail?['inspected_at'] != null &&
                  widget.submit != null)
                FilledButton(
                  onPressed: state.saving
                      ? null
                      : () async {
                          final accepted = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('수령 준비 완료 확인'),
                              content: const Text(
                                '정상 검수한 전체 상품을 고객 수령용으로 보관 준비했습니까? 보관 기록과 주문을 수령 가능 상태로 저장합니다. 실제 전달 완료는 아닙니다.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('닫기'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('준비 완료 확인'),
                                ),
                              ],
                            ),
                          );
                          if (accepted != true ||
                              !context.mounted ||
                              state.isClosed) {
                            return;
                          }
                          final success = await state.confirmReady(id);
                          if (success && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  child: Text(state.saving ? '처리 중' : '수령 준비 완료'),
                ),
              TextButton(
                onPressed:
                    widget.arrival &&
                        (!state.inspection ||
                            state.detail?['fulfillment_status'] == 'ARRIVED') &&
                        widget.submit != null &&
                        !state.saving &&
                        state.detail != null
                    ? () async {
                        final accepted = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(
                              state.inspection ? '전체 상품 정상 검수 확인' : '실제 도착 확인',
                            ),
                            content: Text(
                              state.inspection
                                  ? '목록의 모든 상품·옵션·수량이 일치하고 정상임을 실제로 확인했습니까? 파손·부족이 있으면 저장하지 마세요. 저장 후에도 재고 보관 연결 전까지 수령할 수 없습니다.'
                                  : '해당 배송의 상품이 소속 대리점에 실제로 도착했습니까? 정상 검수와 수령 가능 처리는 별도입니다.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('닫기'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(
                                  state.inspection ? '정상 검수 저장' : '도착 확인',
                                ),
                              ),
                            ],
                          ),
                        );
                        if (accepted != true ||
                            !context.mounted ||
                            state.isClosed) {
                          return;
                        }
                        final success = state.inspection
                            ? await state.confirmInspection(id)
                            : await state.confirmArrival(id);
                        if (success && context.mounted) Navigator.pop(context);
                      }
                    : null,
                child: Text(
                  state.inspection
                      ? (state.detail?['fulfillment_status'] == 'ARRIVED' &&
                                widget.submit != null
                            ? (state.saving ? '처리 중' : '정상 검수 저장')
                            : '검수·보관 연결 준비 중')
                      : widget.arrival && widget.submit != null
                      ? (state.saving ? '처리 중' : '도착 확인')
                      : widget.arrival
                      ? '입고 실행 준비 중'
                      : '수령 인증·완료 준비 중',
                ),
              ),
              TextButton(
                onPressed: state.saving ? null : () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      );
    } finally {
      vm.closeDetail();
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => GetBuilder<PickupCandidatesVm>(
    init: _vm,
    global: false,
    autoRemove: false,
    builder: (vm) => Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.arrival ? '대리점 입고 대상' : '고객 수령 대기'),
            const Text('정상 검수 저장 후 수령 준비 완료를 별도로 처리합니다. 수령 인증과 실제 전달은 별도입니다.'),
            if (widget.arrival)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('도착 전')),
                  ButtonSegment(value: true, label: Text('검수 대기')),
                ],
                selected: {vm.inspection},
                onSelectionChanged: vm.saving
                    ? null
                    : (values) => vm.selectInspection(values.single),
              ),
            TextButton(
              onPressed: vm.loading
                  ? null
                  : () => vm.fetch(targetPage: vm.page),
              child: const Text('새로고침'),
            ),
            if (vm.loading)
              const Center(child: CircularProgressIndicator())
            else if (vm.error != null) ...[
              Text(vm.error!),
              TextButton(
                onPressed: () => vm.fetch(targetPage: vm.page),
                child: const Text('다시 시도'),
              ),
            ] else ...[
              if (vm.rows.isEmpty) const Text('대상 주문이 없습니다.'),
              for (final row in vm.rows)
                ListTile(
                  title: Text(row.number),
                  subtitle: Text('${row.branch} · ${row.time}'),
                  trailing: Text(
                    row.data['inspected_at'] != null
                        ? '검수 기록 완료 · 보관 연결 대기'
                        : '실행 준비 중',
                  ),
                  onTap: () => _open(vm, row.id),
                ),
              Row(
                children: [
                  TextButton(
                    onPressed: vm.page > 1
                        ? () => vm.fetch(targetPage: vm.page - 1)
                        : null,
                    child: const Text('이전'),
                  ),
                  Text('${vm.page}페이지 · 총 ${vm.total}건'),
                  TextButton(
                    onPressed: vm.hasNext
                        ? () => vm.fetch(targetPage: vm.page + 1)
                        : null,
                    child: const Text('다음'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
