import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../vm/dispatch_vm.dart';
import '../model/dispatch_order.dart';

/// 화면이 컨트롤러를 소유하여 직급·대리점 변경과 로그아웃 시 목록을 정리한다.
class DispatchView extends StatefulWidget {
  const DispatchView({
    super.key,
    required this.request,
    this.branchId,
    this.submit,
  });
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  submit;
  final Future<Map<String, dynamic>> Function(String) request;
  final int? branchId;

  @override
  State<DispatchView> createState() => _DispatchViewState();
}

class _DispatchViewState extends State<DispatchView> {
  bool _isReviewOpen = false;
  late final DispatchVm _vm;
  @override
  void initState() {
    super.initState();
    _vm = DispatchVm(
      request: widget.request,
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

  /// 주문 확인 창은 하나만 열고 서버 실행 권한은 별도로 검사한다.
  Future<void> _reviewOrder(DispatchOrder order) async {
    if (_isReviewOpen) return;
    setState(() => _isReviewOpen = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => _DispatchReviewDialog(order: order, vm: _vm),
      );
    } finally {
      if (mounted) setState(() => _isReviewOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) => GetBuilder<DispatchVm>(
    init: _vm,
    autoRemove: false,
    global: false,
    builder: (vm) => Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('출고 대상 조회')),
                IconButton(
                  tooltip: '새로고침',
                  onPressed: vm.isLoading ? null : () => vm.fetchOrders(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (vm.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (vm.error != null) ...[
              Text(vm.error!),
              TextButton(
                onPressed: () => vm.fetchOrders(),
                child: const Text('다시 시도'),
              ),
            ] else if (vm.orders.isEmpty)
              const Text('출고 대상 주문이 없습니다.')
            else ...[
              for (final order in vm.orders)
                ListTile(
                  title: Text(order.orderNumber),
                  subtitle: Text(order.branchName),
                  trailing: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text('${order.paidTotal}원'),
                      TextButton(
                        onPressed: _isReviewOpen
                            ? null
                            : () => _reviewOrder(order),
                        child: const Text('출고 내용 확인'),
                      ),
                    ],
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: vm.page > 1
                        ? () => vm.fetchOrders(requestedPage: vm.page - 1)
                        : null,
                    child: const Text('이전'),
                  ),
                  Text('${vm.page}페이지 · 총 ${vm.totalCount}건'),
                  TextButton(
                    onPressed: vm.hasNext
                        ? () => vm.fetchOrders(requestedPage: vm.page + 1)
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

/// 확인 여부는 창이 소유하며, 닫으면 폐기한다. 서버의 실행 권한을 대신하지 않는다.
class _DispatchReviewDialog extends StatefulWidget {
  const _DispatchReviewDialog({required this.order, required this.vm});
  final DispatchVm vm;
  final DispatchOrder order;

  @override
  State<_DispatchReviewDialog> createState() => _DispatchReviewDialogState();
}

class _DispatchReviewDialogState extends State<_DispatchReviewDialog> {
  bool _isAcknowledged = false;
  bool _saving = false;
  String? _error;
  Future<void> _confirm() async {
    if (_saving || !_isAcknowledged) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final success = await widget.vm.confirmDispatch(widget.order.orderId);
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = widget.vm.submitError;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('출고 확인 준비'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('주문 번호: ${widget.order.orderNumber}'),
            Text('수령 대리점: ${widget.order.branchName}'),
            Text('결제 금액: ${widget.order.paidTotal}원'),
            const SizedBox(height: 16),
            const Text(
              '주문 전체를 한 번에 출고하는 기준입니다. 일부 상품만 출고하거나 재출고하는 작업은 지원하지 않습니다.',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _isAcknowledged,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _isAcknowledged = value ?? false),
              title: Text(
                widget.vm.submit == null
                    ? '전체 출고 기준을 확인했습니다.'
                    : '주문 전체 상품의 실제 출고를 확인했습니다.',
              ),
            ),
            if (widget.vm.submit == null)
              const Text('출고 실행 연결을 준비 중입니다. 지금은 주문 상태와 재고가 변경되지 않습니다.')
            else
              const Text('확인하면 주문 상태와 재고가 함께 변경됩니다.'),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('닫기'),
      ),
      FilledButton(
        onPressed: widget.vm.submit != null && _isAcknowledged && !_saving
            ? _confirm
            : null,
        child: Text(
          widget.vm.submit == null
              ? '출고 실행 준비 중'
              : _saving
              ? '처리 중'
              : '출고 확인',
        ),
      ),
    ],
  );
}
