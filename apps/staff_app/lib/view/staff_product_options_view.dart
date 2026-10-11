import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../model/staff_product.dart';
import '../vm/staff_product_options_vm.dart';

import 'staff_product_option_form.dart';

import '../model/staff_product_option.dart';

class StaffProductOptionsView extends StatefulWidget {
  const StaffProductOptionsView({
    super.key,
    required this.product,
  });

  final StaffProduct product;

  @override
  State<StaffProductOptionsView> createState() =>
      _StaffProductOptionsViewState();
}

class _StaffProductOptionsViewState
    extends State<StaffProductOptionsView> {
  late final String tag;

  @override
  void initState() {
    super.initState();

    tag = 'staff-options-${identityHashCode(this)}';
    Get.put(
      StaffProductOptionsVm(productId: widget.product.id),
      tag: tag,
    );
  }

  @override
  void dispose() {
    Get.delete<StaffProductOptionsVm>(tag: tag);
    super.dispose();
  }

    Future<void> openCreateForm(
    StaffProductOptionsVm controller,
  ) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StaffProductOptionForm(vm: controller),
    );

    if (!mounted) return;

    // 통신 실패 때도 저장됐을 수 있으므로 닫은 뒤 재조회한다.
    await controller.fetchOptions();
  }

    Future<void> openEditForm(
    StaffProductOptionsVm controller,
    StaffProductOption option,
  ) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StaffProductOptionForm(
        vm: controller,
        option: option,
      ),
    );

    if (!mounted) return;
    await controller.fetchOptions();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.product.name} · 옵션 관리'),
      content: SizedBox(
        width: 680,
        height: 420,
        child: GetBuilder<StaffProductOptionsVm>(
          tag: tag,
          builder: (controller) {
            if (controller.loading) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (controller.error != null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(controller.error!),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: controller.fetchOptions,
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '등록된 옵션 ${controller.options.length}개',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: controller.fetchOptions,
                      icon: const Icon(Icons.refresh),
                      label: const Text('새로고침'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => openCreateForm(controller),
                      icon: const Icon(Icons.add),
                      label: const Text('옵션 등록'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: controller.options.isEmpty
                      ? const Center(
                          child: Text('등록된 옵션이 없습니다.'),
                        )
                      : ListView.builder(
                          itemCount: controller.options.length,
                          itemBuilder: (context, index) {
                            final option = controller.options[index];

                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${option.colorName} · '
                                            '${option.sizeMm}mm',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Chip(
                                          label: Text(
                                            option.isActive ? '옵션 활성' : '옵션 비활성',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed: () => openEditForm(controller, option),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: const Text('수정'),
                                        ),
                                      ],
                                    ),
                                    Text('옵션 ID: ${option.id}'),
                                    Text('상품 코드: ${option.productCode}'),
                                    Text('색상 코드: ${option.colorCode}'),
                                    Text(
                                      '추가금액: ${option.additionalPrice}원',
                                    ),
                                    Text(
                                      '옵션 적용 가격: '
                                      '${widget.product.price + option.additionalPrice}원',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}