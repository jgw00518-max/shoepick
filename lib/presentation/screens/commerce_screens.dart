import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../domain/models.dart';
import '../shared/store_widgets.dart';
import 'review_sheet.dart';

const pickupDistricts = [
  '강남구',
  '강동구',
  '강북구',
  '강서구',
  '관악구',
  '광진구',
  '구로구',
  '금천구',
  '노원구',
  '도봉구',
  '동대문구',
  '동작구',
  '마포구',
  '서대문구',
  '서초구',
  '성동구',
  '성북구',
  '송파구',
  '양천구',
  '영등포구',
  '용산구',
  '은평구',
  '종로구',
  '중구',
  '중랑구',
];

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

/// 목업과 동일한 픽업·결제·완료 단계를 제공합니다.
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
  String district = '성동구';
  String payment = '카드';
  String coupon = '';
  int points = 0;
  bool agreed = false;
  bool submitting = false;
  StoreOrder? created;
  final pointsController = TextEditingController();
  @override
  void dispose() {
    pointsController.dispose();
    super.dispose();
  }

  int get subtotal => widget.lines.fold(0, (sum, item) => sum + item.total);
  bool get sneakers =>
      widget.lines.any((item) => item.product.category == '운동화');
  int get discount => coupon == 'welcome' && subtotal >= 30000
      ? 5000
      : coupon == 'sneakers' && subtotal >= 100000 && sneakers
      ? (subtotal * .1).round()
      : 0;
  int get validPoints => points.clamp(
    0,
    [32500, subtotal - discount].reduce((a, b) => a < b ? a : b),
  );
  int get total => (subtotal - discount - validPoints).clamp(0, subtotal);

  Future<void> _pay() async {
    if (!agreed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LText('결제 전 필수 동의 항목을 확인해주세요.')));
      return;
    }
    setState(() => submitting = true);
    try {
      final order = await widget.store.placeOrder(
        district,
        lines: widget.lines,
        paidTotal: total,
        couponDiscount: discount,
        pointsUsed: validPoints,
        fromCart: widget.fromCart,
      );
      if (mounted) {
        setState(() {
          created = order;
          step = 3;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: LText('목업 주문을 완료하지 못했습니다.')));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (step == 3) return _success();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SectionTitle('주문하기'),
        const LText('주문 상품과 픽업 대리점을 확인해주세요.'),
        const SizedBox(height: 14),
        LText(
          '1 픽업    ──    2 결제    ──    3 완료',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 18),
        SectionTitle(
          '주문 상품 ${widget.lines.fold(0, (sum, item) => sum + item.quantity)}개',
        ),
        for (final item in widget.lines)
          ListTile(
            leading: SizedBox(
              width: 64,
              child: ProductImage(item.product, height: 64, color: item.color),
            ),
            title: LText(item.product.name),
            subtitle: LText('${item.color} · ${item.size} · ${item.quantity}개'),
            trailing: LText(won(item.total)),
          ),
        const Divider(height: 30),
        if (step == 1) ...[
          const SectionTitle('픽업 대리점'),
          DropdownButtonFormField<String>(
            initialValue: district,
            decoration: const InputDecoration(
              labelText: '서울시 자치구',
              border: OutlineInputBorder(),
            ),
            items: pickupDistricts
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: LText(value)),
                )
                .toList(),
            onChanged: (value) => setState(() => district = value!),
          ),
          const SizedBox(height: 12),
          PickupStoreInfo(district: district),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => setState(() => step = 2),
            child: const LText('결제 수단 선택'),
          ),
        ] else ...[
          ListTile(
            title: LText('SOLE $district점'),
            subtitle: const LText('픽업 대리점'),
            trailing: TextButton(
              onPressed: () => setState(() => step = 1),
              child: const LText('수정'),
            ),
          ),
          PickupStoreInfo(district: district, compact: true),
          const SizedBox(height: 16),
          const SectionTitle('결제 수단'),
          for (final method in ['카드', '카카오페이', '네이버페이'])
            ListTile(
              title: LText(method),
              trailing: Icon(
                payment == method
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              onTap: () => setState(() => payment = method),
            ),
          const SizedBox(height: 10),
          const LText('쿠폰 선택'),
          DropdownButtonFormField<String>(
            initialValue: coupon,
            items: [
              const DropdownMenuItem(value: '', child: LText('쿠폰을 선택하세요')),
              DropdownMenuItem(
                value: 'welcome',
                enabled: subtotal >= 30000,
                child: const LText('앱 첫 구매 5,000원 할인 (3만원 이상)'),
              ),
              DropdownMenuItem(
                value: 'sneakers',
                enabled: subtotal >= 100000 && sneakers,
                child: const LText('운동화 10% 할인 (10만원 이상)'),
              ),
            ],
            onChanged: (value) => setState(() {
              coupon = value!;
              points = validPoints;
            }),
          ),
          const SizedBox(height: 12),
          const LText('적립금 사용 · 보유 32,500P'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: pointsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '0'),
                  onChanged: (value) => setState(
                    () => points =
                        int.tryParse(value.replaceAll(RegExp(r'\D'), '')) ?? 0,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  points = [
                    32500,
                    subtotal - discount,
                  ].reduce((a, b) => a < b ? a : b);
                  pointsController.text = '$points';
                }),
                child: const LText('전액 사용'),
              ),
            ],
          ),
          const Divider(height: 30),
          _amount('상품 금액', subtotal),
          if (discount > 0) _amount('쿠폰 할인', -discount),
          if (validPoints > 0) _amount('적립금 사용', -validPoints),
          _amount('최종 결제', total, bold: true),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: agreed,
            onChanged: (value) => setState(() => agreed = value ?? false),
            title: const LText('필수 · 개인정보 수집 및 구매 조건에 동의합니다.'),
          ),
          FilledButton(
            onPressed: submitting ? null : _pay,
            child: LText(submitting ? '처리 중...' : '$payment로 ${won(total)} 결제'),
          ),
        ],
      ],
    );
  }

  Widget _amount(String label, int value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        LText(label),
        const Spacer(),
        LText(
          value < 0 ? '-${won(-value)}' : won(value),
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    ),
  );

  Widget _success() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Icon(Icons.check_circle, size: 60, color: brandBlue),
      const Center(child: SectionTitle('주문이 완료되었습니다')),
      const Center(child: LText('감사합니다')),
      const SizedBox(height: 20),
      Center(child: LText('주문번호 ${created!.number}')),
      Center(
        child: LText(
          '주문 상품 ${widget.lines.fold(0, (sum, item) => sum + item.quantity)}개 · 결제 금액 ${won(total)}',
        ),
      ),
      const SizedBox(height: 14),
      LText(
        '사용 적립금 -${validPoints}P\n남은 적립금 ${32500 - validPoints}P\n구매 적립 예정 +${(total * .02).floor()}P',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: widget.onComplete,
        child: const LText('주문 내역 보기'),
      ),
    ],
  );
}

/// 자치구에 따른 목업 대리점 운영 정보를 제공합니다.
class PickupStoreInfo extends StatelessWidget {
  const PickupStoreInfo({
    super.key,
    required this.district,
    this.compact = false,
  });
  final String district;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final index = pickupDistricts
        .indexOf(district)
        .clamp(0, pickupDistricts.length - 1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact)
              LText(
                'SOLE $district점',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            LText(
              '픽업 가능 시간 · 평일 ${index.isEven ? '10:00–20:00' : '10:30–20:00'}',
            ),
            LText(
              '토·일요일 ${index % 3 == 0 ? '11:00–18:00' : '11:00–19:00'} · 공휴일 휴무',
            ),
            LText('대리점 연락처 · 02-0000-${1001 + index}'),
            const LText('운영시간과 연락처는 목업용 예시입니다.'),
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
