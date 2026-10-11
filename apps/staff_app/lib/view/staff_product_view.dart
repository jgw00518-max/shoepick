import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../vm/staff_product_vm.dart';

import 'staff_product_form.dart';

import '../model/staff_product.dart';

import 'staff_product_options_view.dart';

class StaffProductView extends StatefulWidget {
  const StaffProductView({super.key});

  @override
  State<StaffProductView> createState() => _StaffProductViewState();
}

class _StaffProductViewState extends State<StaffProductView> {
  late final String tag;

  @override
  void initState() {
    super.initState();

    tag = 'staff-products-${identityHashCode(this)}';
    Get.put(StaffProductVm(), tag: tag);
  }

  @override
  void dispose() {
    Get.delete<StaffProductVm>(tag: tag);
    super.dispose();
  }

  String genderLabel(String code) {
    return switch (code) {
      'M' => '남성',
      'W' => '여성',
      'U' => '공용',
      'K' => '키즈',
      _ => code,
    };
  }

    Future<void> openCreateForm(StaffProductVm controller) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StaffProductForm(vm: controller),
    );

    if (!mounted) return;

    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품이 등록되었습니다.')),
      );
    }

    // 통신이 끊겼어도 저장됐을 수 있으므로 닫은 뒤 재조회한다.
    await controller.fetchProducts();
  }


    Future<void> openEditForm(
    StaffProductVm controller,
    StaffProduct product,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StaffProductForm(
        vm: controller,
        product: product,
      ),
    );

    if (!mounted) return;

    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품이 수정되었습니다.')),
      );
    }

    await controller.fetchProducts();
  }

    Future<void> openOptions(StaffProduct product) async {
    await showDialog<void>(
      context: context,
      builder: (_) => StaffProductOptionsView(
        product: product,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<StaffProductVm>(
      tag: tag,
      builder: (controller) {
        if (controller.loading) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (controller.error != null) {
          return Column(
            children: [
              Text(controller.error!),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: controller.fetchProducts,
                child: const Text('다시 시도'),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '등록된 상품 ${controller.products.length}개',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: controller.fetchProducts,
                  icon: const Icon(Icons.refresh),
                  label: const Text('새로고침'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => openCreateForm(controller),
                  icon: const Icon(Icons.add),
                  label: const Text('상품 등록'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (controller.products.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('등록된 상품이 없습니다.'),
                ),
              ),
            for (final product in controller.products)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              product.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              product.isActive ? '판매 중' : '판매 중지',
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => openEditForm(controller, product),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('수정'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => openOptions(product),
                            icon: const Icon(Icons.tune),
                            label: const Text('옵션 관리'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('상품 ID: ${product.id}'),
                      Text('모델 코드: ${product.modelCode}'),
                      Text('브랜드: ${product.brandName}'),
                      Text('카테고리: ${product.categoryName}'),
                      Text(
                        '제조사: ${product.manufacturerName ?? '미등록'}',
                      ),
                      Text('성별: ${genderLabel(product.genderCode)}'),
                      Text('가격: ${product.price}원'),
                      const SizedBox(height: 8),
                      Text(
                        product.description?.trim().isNotEmpty == true
                            ? product.description!
                            : '등록된 상품 설명이 없습니다.',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}