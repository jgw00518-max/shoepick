import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../vm/staff_product_vm.dart';

import '../model/staff_product.dart';

class StaffProductForm extends StatefulWidget {
  const StaffProductForm({
    super.key,
    required this.vm,
    this.product,
  });

  final StaffProductVm vm;
  final StaffProduct? product;

  @override
  State<StaffProductForm> createState() => _StaffProductFormState();
}

class _StaffProductFormState extends State<StaffProductForm> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final codeController = TextEditingController();
  final priceController = TextEditingController();
  final descriptionController = TextEditingController();

  List<Map<String, dynamic>> brands = [];
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> manufacturers = [];

  int? brandId;
  int? categoryId;
  int? manufacturerId;
  String genderCode = 'U';
  bool isActive = false;

  bool loading = true;
  bool saving = false;
  bool uncertain = false;
  String? error;

    @override
  void initState() {
    super.initState();

    final product = widget.product;
    if (product != null) {
      nameController.text = product.name;
      codeController.text = product.modelCode;
      priceController.text = product.price.toString();
      descriptionController.text = product.description ?? '';

      brandId = product.brandId;
      categoryId = product.categoryId;
      manufacturerId = product.manufacturerId;
      genderCode = product.genderCode;
      isActive = product.isActive;
    }

    loadOptions();
  }

  @override
  void dispose() {
    nameController.dispose();
    codeController.dispose();
    priceController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> loadOptions() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final data = await widget.vm.fetchFormOptions();
      if (!mounted) return;

      setState(() {
        brands = List<Map<String, dynamic>>.from(data['brands'] as List);
        categories =
            List<Map<String, dynamic>>.from(data['categories'] as List);
        manufacturers =
            List<Map<String, dynamic>>.from(data['manufacturers'] as List);
      });
    } on StateError catch (exception) {
      if (!mounted) return;
      setState(() => error = exception.message.toString());
    } catch (_) {
      if (!mounted) return;
      setState(() => error = '선택 목록을 불러오지 못했습니다.');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
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
      await widget.vm.saveProduct(
        {
          'product_name': nameController.text.trim(),
          'model_code': codeController.text.trim(),
          'brand_id': brandId,
          'category_id': categoryId,
          'manufacturer_id': manufacturerId,
          'gender_code': genderCode,
          'product_description': descriptionController.text.trim(),
          'price': int.parse(priceController.text),
          // 신규 등록은 판매 중지, 수정은 화면에서 선택한 상태를 저장한다.
          'is_active': widget.product == null ? false : isActive,
        },
        productId: widget.product?.id,
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
            '창을 닫고 상품 목록을 새로고침하여 확인해주세요.';
      });
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Widget choice({
    required String label,
    required List<Map<String, dynamic>> rows,
    required String idKey,
    required String nameKey,
    required int? value,
    required ValueChanged<int?> onChanged,
    bool requiredValue = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<int>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          if (!requiredValue)
            const DropdownMenuItem<int>(
              value: null,
              child: Text('선택 안 함'),
            ),
          for (final row in rows)
            DropdownMenuItem<int>(
              value: (row[idKey] as num).toInt(),
              child: Text(row[nameKey] as String),
            ),
        ],
        onChanged: saving ? null : onChanged,
        validator: (value) {
          if (requiredValue && value == null) {
            return '$label 항목을 선택해주세요.';
          }
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(widget.product == null ? '상품 등록' : '상품 수정'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : Form(
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
                        if (brands.isEmpty || categories.isEmpty) ...[
                          const Text(
                            '등록된 브랜드와 카테고리가 필요합니다.',
                          ),
                          TextButton(
                            onPressed: loadOptions,
                            child: const Text('선택 목록 다시 조회'),
                          ),
                        ],
                        TextFormField(
                          controller: nameController,
                          enabled: !saving,
                          maxLength: 150,
                          decoration:
                              const InputDecoration(labelText: '상품명'),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? '상품명을 입력해주세요.'
                                  : null,
                        ),
                        TextFormField(
                          controller: codeController,
                          enabled: !saving,
                          maxLength: 40,
                          decoration:
                              const InputDecoration(labelText: '모델 코드'),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? '모델 코드를 입력해주세요.'
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        choice(
                          label: '브랜드',
                          rows: brands,
                          idKey: 'brand_id',
                          nameKey: 'brand_name',
                          value: brandId,
                          onChanged: (value) =>
                              setState(() => brandId = value),
                        ),
                        choice(
                          label: '카테고리',
                          rows: categories,
                          idKey: 'category_id',
                          nameKey: 'category_name',
                          value: categoryId,
                          onChanged: (value) =>
                              setState(() => categoryId = value),
                        ),
                        choice(
                          label: '제조사',
                          rows: manufacturers,
                          idKey: 'manufacturer_id',
                          nameKey: 'manufacturer_name',
                          value: manufacturerId,
                          requiredValue: false,
                          onChanged: (value) =>
                              setState(() => manufacturerId = value),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: genderCode,
                          decoration:
                              const InputDecoration(labelText: '성별'),
                          items: const [
                            DropdownMenuItem(value: 'M', child: Text('남성')),
                            DropdownMenuItem(value: 'W', child: Text('여성')),
                            DropdownMenuItem(value: 'U', child: Text('공용')),
                            DropdownMenuItem(value: 'K', child: Text('키즈')),
                          ],
                          onChanged: saving
                              ? null
                              : (value) => setState(
                                    () => genderCode = value ?? 'U',
                                  ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: priceController,
                          enabled: !saving,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration:
                              const InputDecoration(labelText: '가격(원)'),
                          validator: (value) {
                            final price = int.tryParse(value ?? '');
                            if (price == null || price < 0) {
                              return '0 이상의 정수 금액을 입력해주세요.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: descriptionController,
                          enabled: !saving,
                          minLines: 3,
                          maxLines: 6,
                          decoration:
                              const InputDecoration(labelText: '상품 설명'),
                        ),
                        const SizedBox(height: 16),
                        if (widget.product != null)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('판매 상태'),
                            subtitle: Text(
                              isActive ? '판매 중' : '판매 중지',
                            ),
                            value: isActive,
                            onChanged: saving
                                ? null
                                : (value) {
                                    setState(() => isActive = value);
                                  },
                          ),
                        Text(
                          widget.product == null
                              ? '새 상품은 판매 중지 상태로 등록됩니다.'
                              : '판매 중지 상품은 고객 상품 목록에서 제외됩니다. '
                                  '판매를 시작해도 재고 수량은 변경되지 않습니다.',
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
            onPressed: loading ||
                    saving ||
                    uncertain ||
                    brands.isEmpty ||
                    categories.isEmpty
                ? null
                : save,
            child: Text(
              saving
                  ? '저장 중...'
                  : widget.product == null
                      ? '등록'
                      : '수정 저장',
            ),
          ),
        ],
      ),
    );
  }
}