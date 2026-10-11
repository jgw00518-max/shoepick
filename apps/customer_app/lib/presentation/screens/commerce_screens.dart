import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../domain/models.dart';
import '../shared/store_widgets.dart';
import 'review_sheet.dart';

import 'package:get/get.dart';

import '../../model/pickup_branch.dart';
import '../../vm/pickup_branch_vm.dart';

import '../../vm/checkout_vm.dart';

/// 선택 주문과 옵션 변경이 가능한 목업 장바구니입니다.
class CartScreen extends StatefulWidget {
  const CartScreen({
    super.key,
    required this.store,
    required this.onOpen,
    required this.onCheckout,
    required this.onMessage,
  });
  final StoreController store;
  final void Function(Product) onOpen;
  final void Function(List<CartItem>) onCheckout;
  final void Function(String) onMessage;
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late Set<String> selected;
  @override
  void initState() {
    super.initState();
    selected = widget.store.cart.map((item) => item.key).toSet();
  }

  List<CartItem> get selectedItems =>
      widget.store.cart.where((item) => selected.contains(item.key)).toList();
  int get selectedTotal =>
      selectedItems.fold(0, (sum, item) => sum + item.total);

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: LText(title),
          content: LText(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LText('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const LText('삭제'),
            ),
          ],
        ),
      ) ??
      false;

  void _updateOption(CartItem item, {String? size, String? color}) {
    final nextKey =
        '${item.product.id}-${size ?? item.size}-${color ?? item.color}';
    widget.store.updateCartOption(item, size: size, color: color);
    if (selected.remove(item.key)) selected.add(nextKey);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.store.cart;
    selected.removeWhere((key) => !items.any((item) => item.key == key));
    if (items.isEmpty) {
      return const EmptyState('장바구니가 비어 있어요\n마음에 드는 신발을 발견하면 이곳에 담아두세요.');
    }
    final all = selected.length == items.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Checkbox(
                value: all,
                onChanged: (_) => setState(() {
                  if (all) {
                    selected.clear();
                  } else {
                    selected = items.map((item) => item.key).toSet();
                  }
                }),
              ),
              LText('전체 선택 (${selected.length})'),
              const Spacer(),
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () async {
                        if (!await _confirm(
                          '선택 상품 삭제',
                          '선택한 상품을 장바구니에서 삭제할까요?',
                        )) {
                          return;
                        }
                        widget.store.removeCartKeys(Set.of(selected));
                        setState(selected.clear);
                      },
                child: const LText('선택 삭제'),
              ),
              TextButton(
                onPressed: () async {
                  if (!await _confirm('장바구니 비우기', '장바구니의 모든 상품을 삭제할까요?')) {
                    return;
                  }
                  widget.store.removeCartKeys(
                    items.map((item) => item.key).toSet(),
                  );
                  setState(selected.clear);
                },
                child: const LText('전체 삭제'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final item in items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: selected.contains(item.key),
                          onChanged: (_) => setState(() {
                            if (!selected.remove(item.key)) {
                              selected.add(item.key);
                            }
                          }),
                        ),
                        InkWell(
                          onTap: () => widget.onOpen(item.product),
                          child: SizedBox(
                            width: 74,
                            child: ProductImage(
                              item.product,
                              height: 82,
                              color: item.color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LText(
                                item.product.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              LText(won(item.product.price)),
                              Row(
                                children: [
                                  Flexible(
                                    child: DropdownButton<String>(
                                      value: item.size,
                                      items:
                                          [
                                                '230',
                                                '240',
                                                '250',
                                                '260',
                                                '270',
                                                '280',
                                              ]
                                              .map(
                                                (v) => DropdownMenuItem(
                                                  value: v,
                                                  child: LText(v),
                                                ),
                                              )
                                              .toList(),
                                      onChanged: (v) =>
                                          _updateOption(item, size: v),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: DropdownButton<String>(
                                      value: item.color,
                                      items:
                                          {...item.product.colors, item.color}
                                              .map(
                                                (v) => DropdownMenuItem(
                                                  value: v,
                                                  child: LText(v),
                                                ),
                                              )
                                              .toList(),
                                      onChanged: (v) =>
                                          _updateOption(item, color: v),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: item.quantity <= 1
                                        ? null
                                        : () => widget.store.changeQuantity(
                                            item,
                                            item.quantity - 1,
                                          ),
                                    icon: const Icon(Icons.remove),
                                  ),
                                  LText('${item.quantity}'),
                                  IconButton(
                                    onPressed: item.quantity >= 99
                                        ? null
                                        : () => widget.store.changeQuantity(
                                            item,
                                            item.quantity + 1,
                                          ),
                                    icon: const Icon(Icons.add),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    onPressed: () {
                                      widget.store.removeCartKeys({item.key});
                                      selected.remove(item.key);
                                      widget.onMessage('장바구니에서 상품을 삭제했어요.');
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const LText('선택 상품'),
                    const Spacer(),
                    LText(
                      '${selectedItems.fold(0, (sum, item) => sum + item.quantity)}개',
                    ),
                  ],
                ),
                Row(
                  children: [
                    const LText('상품 금액'),
                    const Spacer(),
                    LText(won(selectedTotal)),
                  ],
                ),
                const Row(children: [LText('배송비'), Spacer(), LText('무료')]),
                const Divider(),
                Row(
                  children: [
                    const LText('결제 예정'),
                    const Spacer(),
                    LText(
                      won(selectedTotal),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const LText('쿠폰과 적립금은 다음 결제 단계에서 적용할 수 있어요.'),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => widget.onCheckout(selectedItems),
                    child: LText(
                      selected.isEmpty
                          ? '주문할 상품을 선택하세요'
                          : '${won(selectedTotal)} 주문하기',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 실제 API로 수령 대리점 선택, 주문 생성, 모의 결제를 진행합니다.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.store,
    required this.lines,
    required this.fromCart,
    required this.onComplete,
  });
  final StoreController store;
  final List<CartItem> lines;
  final bool fromCart;
  final VoidCallback onComplete;
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  int step = 1;
  bool agreed = false;

  late final String branchTag;
  late final String checkoutTag;
  late final PickupBranchVm branchVm;
  late final CheckoutVm checkoutVm;

  int get subtotal =>
      widget.lines.fold(0, (sum, item) => sum + item.total);

  @override
  void initState() {
    super.initState();

    branchTag = 'pickup-${identityHashCode(this)}';
    checkoutTag = 'checkout-${identityHashCode(this)}';

    branchVm = Get.put(
      PickupBranchVm(),
      tag: branchTag,
    );

    checkoutVm = Get.put(
      CheckoutVm(),
      tag: checkoutTag,
    );
  }

  @override
  void dispose() {
    Get.delete<PickupBranchVm>(tag: branchTag);
    Get.delete<CheckoutVm>(tag: checkoutTag);
    super.dispose();
  }

  Future<void> _pay() async {
    if (!agreed || checkoutVm.submitting) return;

    final branchId = branchVm.selectedBranchId;
    if (branchId == null) return;

    final completed = await checkoutVm.pay(
      branchId: branchId,
      lines: widget.lines,
      expectedTotal: subtotal,
    );

    if (!mounted || !completed) return;

    if (widget.fromCart) {
      widget.store.removeCartKeys(
        widget.lines.map((item) => item.key).toSet(),
      );
    }

    setState(() => step = 3);
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<PickupBranchVm>(
      tag: branchTag,
      builder: (_) => GetBuilder<CheckoutVm>(
        tag: checkoutTag,
        builder: (_) => _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (step == 3) return _success();

    // 요청 중 화면을 나가 중복 주문하는 실수를 줄인다.
    return PopScope(
      canPop: !checkoutVm.submitting,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionTitle('주문하기'),
          const LText('주문 상품과 픽업 대리점을 확인해주세요.'),
          const SizedBox(height: 14),
          const LText(
            '1 픽업    ──    2 결제    ──    3 완료',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),
          SectionTitle(
            '주문 상품 ${widget.lines.fold(0, (sum, item) => sum + item.quantity)}개',
          ),
          for (final item in widget.lines)
            ListTile(
              leading: SizedBox(
                width: 64,
                child: ProductImage(
                  item.product,
                  height: 64,
                  color: item.color,
                ),
              ),
              title: LText(item.product.name),
              subtitle: LText(
                '${item.color} · ${item.size} · ${item.quantity}개',
              ),
              trailing: LText(won(item.total)),
            ),
          const Divider(height: 30),

          if (step == 1) ...[
            const SectionTitle('픽업 대리점'),
            if (branchVm.loading)
              const Center(child: CircularProgressIndicator())
            else if (branchVm.error != null)
              Column(
                children: [
                  LText(branchVm.error!),
                  TextButton(
                    onPressed: branchVm.fetchBranches,
                    child: const LText('다시 시도'),
                  ),
                ],
              )
            else if (branchVm.branches.isEmpty)
              const LText('선택 가능한 대리점이 없습니다.')
            else
              DropdownButtonFormField<int>(
                key: ValueKey(branchVm.selectedBranchId),
                initialValue: branchVm.selectedBranchId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '수령 대리점',
                  border: OutlineInputBorder(),
                ),
                items: branchVm.branches
                    .map(
                      (branch) => DropdownMenuItem<int>(
                        value: branch.id,
                        child: LText(branch.name),
                      ),
                    )
                    .toList(),
                onChanged: branchVm.selectBranch,
              ),
            const SizedBox(height: 12),
            if (branchVm.selectedBranch != null)
              PickupStoreInfo(branch: branchVm.selectedBranch!),
            const SizedBox(height: 18),
            FilledButton(
              onPressed:
                  branchVm.loading || branchVm.selectedBranch == null
                      ? null
                      : () => setState(() => step = 2),
              child: const LText('결제 수단 선택'),
            ),
          ],

          if (step == 2) ...[
            ListTile(
              title: LText(branchVm.selectedBranch?.name ?? ''),
              subtitle: const LText('픽업 대리점'),
              trailing: TextButton(
                // 주문 요청을 시작한 뒤에는 같은 주문으로 재시도한다.
                onPressed: checkoutVm.submitting ||
                        checkoutVm.orderId != null ||
                        checkoutVm.error != null
                    ? null
                    : () => setState(() => step = 1),
                child: const LText('수정'),
              ),
            ),
            if (branchVm.selectedBranch != null)
              PickupStoreInfo(
                branch: branchVm.selectedBranch!,
                compact: true,
              ),
            const SizedBox(height: 16),
            const SectionTitle('결제 수단'),
            const ListTile(
              title: LText('모의 결제'),
              subtitle: LText('테스트용 · 실제 금액이 청구되지 않습니다.'),
              trailing: Icon(Icons.radio_button_checked),
            ),
            const SizedBox(height: 10),

            const LText('쿠폰 선택'),
            DropdownButtonFormField<String>(
              initialValue: '',
              items: const [
                DropdownMenuItem(
                  value: '',
                  child: LText('쿠폰 API 연결 후 사용할 수 있습니다.'),
                ),
              ],
              onChanged: null,
            ),
            const SizedBox(height: 12),
            const LText('적립금 사용'),
            const TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: '적립금 API 연결 후 사용할 수 있습니다.',
              ),
            ),

            const Divider(height: 30),
            _amount('상품 금액', subtotal),
            _amount('최종 결제', subtotal, bold: true),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: agreed,
              onChanged: checkoutVm.submitting
                  ? null
                  : (value) => setState(() => agreed = value ?? false),
              title: const LText(
                '필수 · 개인정보 수집 및 구매 조건에 동의합니다.',
              ),
            ),
            if (checkoutVm.error != null) ...[
              LText(
                checkoutVm.error!,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: checkoutVm.submitting || !agreed
                  ? null
                  : _pay,
              child: LText(
                checkoutVm.submitting
                    ? '처리 중...'
                    : '${won(subtotal)} 모의 결제',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _amount(
    String label,
    int value, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          LText(label),
          const Spacer(),
          LText(
            won(value),
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _success() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(
          Icons.check_circle,
          size: 60,
          color: brandBlue,
        ),
        const Center(
          child: SectionTitle('모의 결제가 완료되었습니다'),
        ),
        const Center(child: LText('감사합니다')),
        const SizedBox(height: 20),
        Center(
          child: LText('주문번호 ${checkoutVm.orderNumber ?? ''}'),
        ),
        Center(
          child: LText(
            '주문 상품 ${widget.lines.fold(0, (sum, item) => sum + item.quantity)}개'
            ' · 결제 금액 ${won(checkoutVm.paidTotal ?? subtotal)}',
          ),
        ),
        const SizedBox(height: 14),
        const Center(child: LText('결제 상태: PAID')),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: widget.onComplete,
          child: const LText('주문 내역 보기'),
        ),
      ],
    );
  }
}

class PickupStoreInfo extends StatelessWidget {
  const PickupStoreInfo({
    super.key,
    required this.branch,
    this.compact = false,
  });

  final PickupBranch branch;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact)
              LText(
                branch.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            LText(branch.address),
            LText('대리점 연락처 · ${branch.phone}'),
          ],
        ),
      ),
    );
  }
}

/// 주문 상세·픽업 QR·리뷰·배송 조회를 연결합니다.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({
    super.key,
    required this.store,
    required this.onMessage,
    required this.onShipping,
  });
  final StoreController store;
  final void Function(String) onMessage;
  final void Function(StoreOrder) onShipping;

  void _detail(BuildContext context, StoreOrder order) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const LText('주문 상세'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              '${order.number} · ${order.date.year}.${order.date.month}.${order.date.day}',
            ),
            const Divider(),
            for (final item in order.items)
              ListTile(
                title: LText(item.product.name),
                subtitle: LText(
                  '${item.color} · ${item.size} · ${item.quantity}켤레',
                ),
                trailing: LText(won(item.total)),
              ),
            LText(
              '총 주문 수량 ${order.items.fold(0, (sum, item) => sum + item.quantity)}켤레',
            ),
            LText('최종 결제 금액 ${won(order.total)}'),
            LText('픽업 대리점 SOLE ${order.district}점'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const LText('확인'),
        ),
      ],
    ),
  );

  void _qr(BuildContext context, StoreOrder order) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const LText('주문 QR 코드'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LText('매장 픽업용'),
          LText(order.number),
          SizedBox(
            width: 180,
            height: 180,
            child: GridView.count(
              crossAxisCount: 9,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 81; i++)
                  ColoredBox(
                    color: i.isEven || i % 5 == 0 || i % 11 == 0
                        ? Colors.black
                        : Colors.white,
                  ),
              ],
            ),
          ),
          LText('SOLE ${order.district}점 직원에게 보여주세요.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const LText('닫기'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const SectionTitle('주문 내역'),
      const LText('주문과 배송 상태를 확인하세요.'),
      const SizedBox(height: 16),
      for (final order in store.orders)
        Card(
          child: InkWell(
            onTap: () => _detail(context, order),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LText(
                    order.canceled ? '취소 완료' : '배송 중',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  LText(
                    '${order.date.year}.${order.date.month.toString().padLeft(2, '0')}.${order.date.day.toString().padLeft(2, '0')} · ${order.number}',
                  ),
                  const Divider(),
                  for (final item in order.items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                        width: 58,
                        child: ProductImage(item.product, height: 58),
                      ),
                      title: LText(item.product.name),
                      subtitle: LText(
                        '${item.color} · ${item.size} · ${item.quantity}개',
                      ),
                      trailing: LText(won(item.total)),
                    ),
                  if (!order.canceled) ...[
                    for (final item in order.items)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: store.hasReview(order, item)
                              ? null
                              : () {
                                  showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    showDragHandle: true,
                                    builder: (_) => ReviewSheet(
                                      order: order,
                                      item: item,
                                      store: store,
                                      onSaved: () => onMessage('리뷰가 저장되었어요.'),
                                    ),
                                  );
                                },
                          child: LText(
                            store.hasReview(order, item) ? '작성 완료' : '리뷰 작성',
                          ),
                        ),
                      ),
                    const LText('결제 완료  ›  상품 준비  ›  배송 중  ›  픽업 완료'),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => onShipping(order),
                          child: const LText('배송 조회'),
                        ),
                        TextButton(
                          onPressed: () => _qr(context, order),
                          child: const LText('QR 확인'),
                        ),
                      ],
                    ),
                    const LText('대리점 픽업 시 주문 QR 코드를 보여주세요.'),
                  ] else
                    const LText('주문이 취소되었습니다. 결제 수단에 따라 영업일 기준 2~5일 이내 환불됩니다.'),
                ],
              ),
            ),
          ),
        ),
      Card(
        child: ListTile(
          title: const LText('반품 완료 · SS0903-0711'),
          subtitle: const LText(
            'Coast Sandal · 화이트 · 250 · 1개\n9월 11일 환불이 완료되었습니다.',
          ),
          trailing: LText(won(79000)),
        ),
      ),
    ],
  );
}
