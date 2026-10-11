import 'dart:convert';

import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../domain/models.dart';
import '../shared/store_widgets.dart';
import 'review_sheet.dart';

import 'package:get/get.dart';
import '../../vm/product_options_vm.dart';

import '../../model/product_option.dart';

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
 late final String optionsTag;
late final ProductOptionsVm optionsVm;

String tab = '상품 정보';

String get color => optionsVm.selectedColor;

@override
void initState() {
  super.initState();

  optionsTag = 'product-options-${identityHashCode(this)}';

  optionsVm = Get.put(
    ProductOptionsVm(productId: widget.product.id),
    tag: optionsTag,
  );
}

@override
void dispose() {
  Get.delete<ProductOptionsVm>(tag: optionsTag);
  super.dispose();
}

List<Product> get recommendations {
  // 실제 조회된 상품 중 현재 상품을 제외하고 최대 4개 표시한다.
  // 추천 기준이 연결되기 전의 임시 표시 방식이다.
  return widget.store.products
      .where((product) => product.id != widget.product.id)
      .take(4)
      .toList();
}

      Future<void> openOptions() async {
      if (optionsVm.loading) {
        widget.onMessage('상품 옵션을 불러오는 중입니다.');
        return;
      }

      if (optionsVm.error != null) {
        widget.onMessage('상품 옵션을 불러오지 못했습니다. 다시 시도해주세요.');
        return;
      }

      if (optionsVm.options.isEmpty) {
        widget.onMessage('등록된 상품 옵션이 없습니다.');
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ProductOptionsSheet(
          product: widget.product,
          store: widget.store,
          options: List<ProductOption>.of(optionsVm.options),
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
  return GetBuilder<ProductOptionsVm>(
    tag: optionsTag,
    builder: (_) => _buildContent(context),
  );
}

Widget _buildContent(BuildContext context) {
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
                        for (final value in optionsVm.colors)
                          ChoiceChip(
                            label: LText(value),
                            selected: color == value,
                            onSelected: (_) {
                              setState(() {
                                optionsVm.selectColor(value);
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const LText(
                      '사이즈',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (optionsVm.loading)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(),
                    )
                  else if (optionsVm.error != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LText(optionsVm.error!),
                        TextButton(
                          onPressed: optionsVm.fetchOptions,
                          child: const LText('다시 시도'),
                        ),
                      ],
                    )
                  else if (optionsVm.colorOptions.isEmpty)
                    const LText('등록된 옵션이 없습니다.')
                  else
                     Wrap(
                      spacing: 8,
                      children: [
                        for (final option in optionsVm.colorOptions)
                          Chip(
                            label: LText(
                              option.availableQuantity > 0
                                  ? '${option.sizeMm}mm'
                                  : '${option.sizeMm}mm · 품절',
                            ),
                          ),
                      ],
                    ),
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
      LText(
        widget.product.description.trim().isEmpty
            ? '등록된 상품 설명이 없습니다.'
            : widget.product.description,
      ),
      const SizedBox(height: 18),
      const SectionTitle('상품 이미지'),
      if (widget.product.imageFor(color).trim().isEmpty)
        const LText('등록된 상품 이미지가 없습니다.')
      else
        ProductImage(
          widget.product,
          height: 190,
          color: color,
        ),
      const SizedBox(height: 10),
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
    required this.options,
    required this.initialColor,
    required this.onCart,
    required this.onBuy,
    required this.onMessage,
  });

  final Product product;
  final StoreController store;
  final List<ProductOption> options;
  final String initialColor;
  final void Function(List<CartItem>) onCart;
  final void Function(List<CartItem>) onBuy;
  final void Function(String) onMessage;

  @override
  State<ProductOptionsSheet> createState() =>
      _ProductOptionsSheetState();
}

class _ProductOptionsSheetState extends State<ProductOptionsSheet> {
  late String selectedColor;
  final List<CartItem> selected = [];
  String? error;

  // API에서 받은 실제 색상만 표시한다.
  List<String> get colors =>
      widget.options.map((option) => option.colorName).toSet().toList();

  String get color => selectedColor;

  // 선택한 색상의 실제 사이즈만 표시한다.
  List<ProductOption> get colorOptions {
    final result = widget.options
        .where((option) => option.colorName == selectedColor)
        .toList();

    result.sort((a, b) => a.sizeMm.compareTo(b.sizeMm));
    return result;
  }

  @override
  void initState() {
    super.initState();

    selectedColor = colors.contains(widget.initialColor)
        ? widget.initialColor
        : colors.isEmpty
            ? ''
            : colors.first;
  }

  void addOption(ProductOption option) {
    if (option.availableQuantity <= 0) {
      setState(() => error = '품절된 옵션입니다.');
      return;
    }

    final index = selected.indexWhere(
      (item) => item.productVariantId == option.id,
    );

    final nextQuantity = index >= 0
        ? selected[index].quantity + 1
        : 1;

    // 재고 개수는 화면에 표시하지 않고 구매 가능 여부만 확인한다.
    if (nextQuantity > option.availableQuantity) {
      setState(() => error = '선택한 옵션의 구매 가능한 수량을 초과했습니다.');
      return;
    }

    setState(() {
      if (index >= 0) {
        selected[index] = selected[index].copyWith(
          quantity: nextQuantity,
        );
      } else {
        selected.add(
          CartItem(
            product: widget.product,
            size: '${option.sizeMm}',
            color: option.colorName,
            quantity: 1,
            productVariantId: option.id,
            unitPrice: widget.product.price + option.additionalPrice,
          ),
        );
      }

      error = null;
    });
  }

  void increaseQuantity(CartItem item) {
    for (final option in widget.options) {
      if (option.id == item.productVariantId) {
        addOption(option);
        return;
      }
    }

    setState(() => error = '상품 옵션을 다시 선택해주세요.');
  }

  void submit(bool buy) {
    if (selected.isEmpty) {
      setState(() => error = '색상과 사이즈를 선택해 옵션을 추가해주세요.');
      return;
    }

    final lines = List<CartItem>.of(selected);

    Navigator.pop(context);

    if (buy) {
      widget.onBuy(lines);
    } else {
      widget.onCart(lines);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                  child: ProductImage(
                    widget.product,
                    height: 64,
                    color: color,
                  ),
                ),
                title: LText(widget.product.name),
                subtitle: LText(won(widget.product.price)),
              ),
              const SizedBox(height: 12),
              const LText('색상'),
              Wrap(
                spacing: 6,
                children: [
                  for (final value in colors)
                    ChoiceChip(
                      label: LText(value),
                      selected: selectedColor == value,
                      onSelected: (_) {
                        setState(() {
                          selectedColor = value;
                          error = null;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              LText('사이즈 · $selectedColor'),
              Wrap(
                spacing: 6,
                children: [
                  for (final option in colorOptions)
                    OutlinedButton(
                      onPressed: () {
                        if (option.availableQuantity <= 0) {
                          setState(() {
                            error =
                                '품절된 옵션입니다. 재입고 알림 신청 기능은 아직 연결되지 않았습니다.';
                          });
                          return;
                        }

                        addOption(option);
                      },
                      child: LText(
                        option.availableQuantity <= 0
                            ? '${option.sizeMm}\n재입고 알림'
                            : '${option.sizeMm}',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const LText('색상과 사이즈를 선택해주세요.'),
              const SizedBox(height: 12),
              LText(
                '선택한 옵션 ${selected.length}개',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
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
                                  : () {
                                      setState(() {
                                        final index =
                                            selected.indexOf(item);

                                        selected[index] = item.copyWith(
                                          quantity: item.quantity - 1,
                                        );

                                        error = null;
                                      });
                                    },
                              icon: const Icon(Icons.remove),
                            ),
                            LText('${item.quantity}'),
                            IconButton(
                              onPressed: () => increaseQuantity(item),
                              icon: const Icon(Icons.add),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  selected.remove(item);
                                  error = null;
                                });
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (error != null)
                LText(
                  error!,
                  style: const TextStyle(color: Colors.red),
                ),
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
}