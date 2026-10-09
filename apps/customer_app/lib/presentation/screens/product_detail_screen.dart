import 'dart:convert';

import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../domain/models.dart';
import '../shared/store_widgets.dart';
import 'review_sheet.dart';

/// 상품 정보·배송 정책·리뷰와 구매 옵션을 원본 흐름대로 분리합니다.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.store,
    required this.onCart,
    required this.onBuy,
    required this.onOpenProduct,
    required this.onInquiry,
    required this.onMessage,
  });
  final Product product;
  final StoreController store;
  final VoidCallback onCart;
  final void Function(List<CartItem>) onBuy;
  final void Function(Product) onOpenProduct;
  final VoidCallback onInquiry;
  final void Function(String) onMessage;
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late String color;
  String tab = '상품 정보';
  @override
  void initState() {
    super.initState();
    color = widget.product.color;
  }

  List<Product> get recommendations {
    const next = <int, List<int>>{
      1: [5, 6, 16, 2],
      2: [7, 9, 3, 1],
      3: [12, 13, 2, 11],
      4: [14, 15, 16, 5],
      5: [1, 6, 17, 16],
    };
    final ids = next[widget.product.id];
    if (ids != null) {
      return ids
          .map((id) => widget.store.products.firstWhere((p) => p.id == id))
          .toList();
    }
    return widget.store.products
        .where(
          (p) =>
              p.id != widget.product.id &&
              p.category == widget.product.category,
        )
        .take(4)
        .toList();
  }

  Future<void> openOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ProductOptionsSheet(
        product: widget.product,
        store: widget.store,
        initialColor: color,
        onCart: (lines) {
          widget.store.addCartItems(lines);
          widget.onMessage('장바구니에 상품을 담았어요.');
        },
        onBuy: widget.onBuy,
        onMessage: widget.onMessage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ownReviews = widget.store.reviews
        .where((r) => r.itemKey.startsWith('${widget.product.id}-'))
        .toList();
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              Stack(
                children: [
                  ProductImage(widget.product, height: 340, color: color),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: IconButton(
                      onPressed: () => widget.store.toggleWish(widget.product),
                      icon: Icon(
                        widget.store.wishedIds.contains(widget.product.id)
                            ? Icons.favorite
                            : Icons.favorite_border,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(widget.product.category),
                    LText(
                      widget.product.name,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    LText(
                      won(widget.product.price),
                      style: const TextStyle(fontSize: 21),
                    ),
                    LText(
                      '★★★★★  4.8 · 리뷰 ${widget.product.reviewCount + ownReviews.length}개',
                    ),
                    const Divider(height: 32),
                    const LText(
                      '색상',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final value in widget.product.colors)
                          ChoiceChip(
                            label: LText(value),
                            selected: color == value,
                            onSelected: (_) => setState(() => color = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const LText(
                      '사이즈',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const LText('240    250    260    270    280'),
                    const LText('장바구니 또는 구매하기를 누르면 옵션을 선택할 수 있어요.'),
                    const SizedBox(height: 14),
                    const LText('무료 배송    ·    30일 무료 교환'),
                    const SizedBox(height: 28),
                    const SectionTitle('이 상품을 본 고객이 다음으로 본 상품'),
                    const LText('예시 탐색 데이터 기반 추천'),
                    SizedBox(
                      height: 220,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final product in recommendations)
                            SizedBox(
                              width: 130,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ProductCard(
                                  product: product,
                                  store: widget.store,
                                  onOpen: () => widget.onOpenProduct(product),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        for (final value in ['상품 정보', '배송·교환 안내', '리뷰'])
                          Expanded(
                            child: TextButton(
                              onPressed: () => setState(() => tab = value),
                              child: LText(
                                value,
                                style: TextStyle(
                                  fontWeight: tab == value
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Divider(),
                    if (tab == '상품 정보') _information(),
                    if (tab == '배송·교환 안내') _delivery(),
                    if (tab == '리뷰') _reviews(ownReviews),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: openOptions,
                child: const LText('구매하기'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _information() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionTitle('상품 설명'),
      const LText(
        '일상에 자연스럽게 어울리는 디자인과 편안한 착화감의 신발입니다. 상품 종류와 선택한 사이즈를 확인해주세요.',
      ),
      const SizedBox(height: 12),
      const LText('소재  리사이클 메시, 합성가죽\n굽 높이  35mm\n제조국  대한민국'),
      const SizedBox(height: 18),
      const SectionTitle('상세 사진'),
      for (final label in ['전체 실루엣', '소재와 마감', '착용 예시']) ...[
        ProductImage(widget.product, height: 190, color: color),
        LText(label),
        const SizedBox(height: 10),
      ],
      OutlinedButton(
        onPressed: widget.onInquiry,
        child: const LText('이 상품 문의하기'),
      ),
    ],
  );

  Widget _delivery() => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionTitle('배송 안내'),
      LText('평일 오후 2시 이전 주문은 당일 출고됩니다. 기본 배송비는 무료입니다.'),
      SizedBox(height: 20),
      SectionTitle('교환 안내'),
      LText('수령 후 30일 이내 미착용 상품은 사이즈 교환이 가능합니다. 사용 흔적 또는 포장 훼손 시 제한될 수 있습니다.'),
    ],
  );

  Widget _reviews(List<ProductReview> ownReviews) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionTitle('사이즈 추천'),
      const LText('사이즈 · 정사이즈 74%\n발볼 · 적당함 78%\n착화감 · 편함 82%'),
      const SizedBox(height: 20),
      SectionTitle('리뷰 ${widget.product.reviewCount + ownReviews.length}'),
      const LText('리뷰는 주문 내역에서 작성할 수 있어요.'),
      for (final review in ownReviews)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: LText('내 리뷰')),
                    TextButton(
                      onPressed: () => _editReview(review),
                      child: const LText('수정'),
                    ),
                    TextButton(
                      onPressed: () => _deleteReview(review),
                      child: const LText('삭제'),
                    ),
                  ],
                ),
                LText(
                  '사이즈 · ${review.fitSize}   발볼 · ${review.fitWidth}   착화감 · ${review.fitComfort}',
                ),
                LText(review.content),
                if (review.photos.isNotEmpty)
                  SizedBox(
                    height: 84,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final photo in review.photos)
                          GestureDetector(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (context) => Dialog(
                                child: Stack(
                                  children: [
                                    InteractiveViewer(
                                      child: Image.memory(base64Decode(photo)),
                                    ),
                                    Positioned(
                                      right: 0,
                                      child: IconButton(
                                        onPressed: () => Navigator.pop(context),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Image.memory(
                                base64Decode(photo),
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      for (final entry in [
        ('착화감이 가볍고 좋아요', '김** · 260 구매', '정사이즈로 잘 맞고 오래 걸어도 발이 편했습니다.'),
        ('색상이 화면 그대로예요', '이** · 250 구매', '사진과 실제 색상이 비슷해서 코디하기 좋습니다.'),
      ])
        Card(
          child: ListTile(
            title: LText(entry.$1),
            subtitle: LText('${entry.$2}\n${entry.$3}'),
          ),
        ),
    ],
  );

  Future<void> _editReview(ProductReview review) async {
    final order = widget.store.orders
        .where((o) => o.number == review.orderNumber)
        .firstOrNull;
    final item = order?.items
        .where((item) => item.key == review.itemKey)
        .firstOrNull;
    if (order == null || item == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReviewSheet(
        order: order,
        item: item,
        store: widget.store,
        existing: review,
        onSaved: () => widget.onMessage('리뷰가 수정되었어요.'),
      ),
    );
  }

  Future<void> _deleteReview(ProductReview review) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('리뷰 삭제'),
        content: const LText('작성한 리뷰를 삭제하시겠어요?'),
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
    );
    if (yes == true) {
      await widget.store.deleteReview(review);
      widget.onMessage('리뷰가 삭제되었어요.');
    }
  }
}

/// 한 상품에서 여러 색상·사이즈 조합을 장바구니 또는 바로 구매로 보냅니다.
class ProductOptionsSheet extends StatefulWidget {
  const ProductOptionsSheet({
    super.key,
    required this.product,
    required this.store,
    required this.initialColor,
    required this.onCart,
    required this.onBuy,
    required this.onMessage,
  });
  final Product product;
  final StoreController store;
  final String initialColor;
  final void Function(List<CartItem>) onCart;
  final void Function(List<CartItem>) onBuy;
  final void Function(String) onMessage;
  @override
  State<ProductOptionsSheet> createState() => _ProductOptionsSheetState();
}

class _ProductOptionsSheetState extends State<ProductOptionsSheet> {
  String? selectedColor;
  final List<CartItem> selected = [];
  String? error;

  String get color => selectedColor ?? widget.initialColor;
  String _restockKey(String size) => '${widget.product.id}:$color:$size';
  List<String> get restockable => color == '블랙'
      ? ['260']
      : color == '베이지'
      ? ['240']
      : ['250'];
  List<String> get unavailable => color == '베이지' ? ['270'] : ['280'];

  void addOption(String size) {
    final key = '${widget.product.id}-$size-$color';
    final index = selected.indexWhere((item) => item.key == key);
    setState(() {
      if (index >= 0) {
        selected[index] = selected[index].copyWith(
          quantity: selected[index].quantity + 1,
        );
      } else {
        selected.add(
          CartItem(product: widget.product, size: size, color: color),
        );
      }
      selectedColor = null;
      error = null;
    });
  }

  void submit(bool buy) {
    if (selected.isEmpty) {
      setState(() => error = '색상과 사이즈를 선택해 옵션을 추가해주세요.');
      return;
    }
    Navigator.pop(context);
    if (buy) {
      widget.onBuy(List.of(selected));
    } else {
      widget.onCart(List.of(selected));
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('옵션 선택'),
            const LText('여러 옵션을 한 번에 선택할 수 있어요'),
            const SizedBox(height: 12),
            ListTile(
              leading: SizedBox(
                width: 64,
                child: ProductImage(widget.product, height: 64, color: color),
              ),
              title: LText(widget.product.name),
              subtitle: LText(won(widget.product.price)),
            ),
            const SizedBox(height: 12),
            const LText('색상'),
            Wrap(
              spacing: 6,
              children: [
                for (final value in widget.product.colors)
                  ChoiceChip(
                    label: LText(value),
                    selected: selectedColor == value,
                    onSelected: (_) => setState(() {
                      selectedColor = value;
                      error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LText(
              selectedColor == null
                  ? '사이즈 · 색상 선택 후 가능'
                  : '사이즈 · $selectedColor',
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final size in ['240', '250', '260', '270', '280'])
                  OutlinedButton(
                    onPressed:
                        selectedColor == null || unavailable.contains(size)
                        ? null
                        : () async {
                            if (restockable.contains(size)) {
                              await widget.store.toggleRestock(
                                _restockKey(size),
                              );
                              widget.onMessage(
                                widget.store.restockKeys.contains(
                                      _restockKey(size),
                                    )
                                    ? '재입고 알림 신청을 저장했어요.'
                                    : '재입고 알림 신청을 취소했어요.',
                              );
                              if (mounted) setState(() {});
                            } else if (!unavailable.contains(size)) {
                              addOption(size);
                            }
                          },
                    child: LText(
                      restockable.contains(size)
                          ? '$size\n${widget.store.restockKeys.contains(_restockKey(size)) ? '알림 신청됨' : '재입고 알림'}'
                          : unavailable.contains(size)
                          ? '$size\n품절'
                          : size,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const LText('선택한 색상에 따라 사이즈별 재고와 재입고 가능 여부가 달라집니다.'),
            const SizedBox(height: 12),
            LText(
              '선택한 옵션 ${selected.length}개',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final item in selected)
                    ListTile(
                      title: LText('${item.color} · ${item.size}'),
                      subtitle: LText(won(item.total)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: item.quantity <= 1
                                ? null
                                : () => setState(() {
                                    final index = selected.indexOf(item);
                                    selected[index] = item.copyWith(
                                      quantity: item.quantity - 1,
                                    );
                                  }),
                            icon: const Icon(Icons.remove),
                          ),
                          LText('${item.quantity}'),
                          IconButton(
                            onPressed: () => setState(() {
                              final index = selected.indexOf(item);
                              selected[index] = item.copyWith(
                                quantity: item.quantity + 1,
                              );
                            }),
                            icon: const Icon(Icons.add),
                          ),
                          IconButton(
                            onPressed: () =>
                                setState(() => selected.remove(item)),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (error != null)
              LText(error!, style: const TextStyle(color: Colors.red)),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => submit(false),
                    child: const LText('장바구니'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => submit(true),
                    child: const LText('바로 구매'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
