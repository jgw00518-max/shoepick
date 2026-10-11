import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../vm/staff_product_options_vm.dart';

import '../model/staff_product_option.dart';

class StaffProductOptionForm extends StatefulWidget {
  const StaffProductOptionForm({
    super.key,
    required this.vm,
    this.option,
  });

  final StaffProductOptionsVm vm;
  final StaffProductOption? option;

  @override
  State<StaffProductOptionForm> createState() =>
      _StaffProductOptionFormState();
}

class _StaffProductOptionFormState
    extends State<StaffProductOptionForm> {
  final formKey = GlobalKey<FormState>();
  final productCodeController = TextEditingController();
  final colorCodeController = TextEditingController();
  final colorNameController = TextEditingController();
  final sizeController = TextEditingController();
  final additionalPriceController = TextEditingController(text: '0');

  bool isActive = true;
  bool saving = false;
  bool uncertain = false;
  String? error;

    @override
  void initState() {
    super.initState();

    final option = widget.option;
    if (option != null) {
      productCodeController.text = option.productCode;
      colorCodeController.text = option.colorCode;
      colorNameController.text = option.colorName;
      sizeController.text = option.sizeMm.toString();
      additionalPriceController.text =
          option.additionalPrice.toString();
    }
  }

  @override
  void dispose() {
    productCodeController.dispose();
    colorCodeController.dispose();
    colorNameController.dispose();
    sizeController.dispose();
    additionalPriceController.dispose();
    super.dispose();
  }

    Future<void> save() async {
    if (saving || uncertain || !formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      saving = true;
      error = null;
    });

    try {
      await widget.vm.saveOption(
        {
          'product_code': productCodeController.text.trim(),
          'color_code': colorCodeController.text.trim(),
          'color_name': colorNameController.text.trim(),
          'size_mm': int.parse(sizeController.text),
          'additional_price': int.parse(additionalPriceController.text),
          'is_active': isActive,
        },
        optionId: widget.option?.id,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } on StateError catch (exception) {
      if (!mounted) return;
      setState(() => error = exception.message.toString());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        uncertain = true;
        error = '저장 결과를 확인하지 못했습니다. '
            '창을 닫고 옵션 목록을 새로고침하여 확인해주세요.';
      });
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Widget textInput({
    required TextEditingController controller,
    required String label,
    required int maxLength,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !saving,
      maxLength: maxLength,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '$label 항목을 입력해주세요.';
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(widget.option == null ? '옵션 등록' : '옵션 수정'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null) ...[
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  textInput(
                    controller: productCodeController,
                    label: '상품 코드(SKU)',
                    maxLength: 64,
                  ),
                  textInput(
                    controller: colorCodeController,
                    label: '색상 코드',
                    maxLength: 20,
                  ),
                  textInput(
                    controller: colorNameController,
                    label: '색상명',
                    maxLength: 50,
                  ),
                  TextFormField(
                    controller: sizeController,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration:
                        const InputDecoration(labelText: '사이즈(mm)'),
                    validator: (value) {
                      final size = int.tryParse(value ?? '');
                      if (size == null || size <= 0 || size > 65535) {
                        return '1~65535 사이의 정수를 입력해주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: additionalPriceController,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration:
                        const InputDecoration(labelText: '추가금액(원)'),
                    validator: (value) {
                      final price = int.tryParse(value ?? '');
                      if (price == null ||
                          price < 0 ||
                          price > 2147483647) {
                        return '0~2147483647 사이의 정수를 입력해주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  if (widget.option != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('옵션 사용 상태'),
                      subtitle: Text(
                        isActive ? '옵션 활성' : '옵션 비활성',
                      ),
                      value: isActive,
                      onChanged: saving
                          ? null
                          : (value) {
                              setState(() => isActive = value);
                            },
                    ),
                  Text(
                    widget.option == null
                        ? '새 옵션은 활성 상태로 등록됩니다.'
                        : '비활성 옵션은 고객 옵션 목록에서 제외됩니다. '
                            '재고 수량은 변경되지 않습니다.',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: saving || uncertain ? null : save,
            child: Text(
              saving
                  ? '저장 중...'
                  : widget.option == null
                      ? '등록'
                      : '수정 저장',
            ),
          ),
        ],
      ),
    );
  }
}