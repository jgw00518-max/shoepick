import 'package:flutter/material.dart';
import '../model/staff_session.dart';
import '../vm/purchase_requisition_api.dart';

class PurchaseRequisitionEdit extends StatefulWidget {
  const PurchaseRequisitionEdit({
    super.key,
    required this.api,
    required this.id,
  });
  final PurchaseRequisitionApi api;
  final int id;
  @override
  State<PurchaseRequisitionEdit> createState() =>
      _PurchaseRequisitionEditState();
}

class _PurchaseRequisitionEditState extends State<PurchaseRequisitionEdit> {
  final title = TextEditingController();
  final reason = TextEditingController();
  Map<String, dynamic>? detail;
  List<Map<String, dynamic>> options = [];
  final items = <({int? variant, TextEditingController quantity})>[];
  int? manufacturerId;
  bool loading = true, saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    title.dispose();
    reason.dispose();
    for (final item in items) {
      item.quantity.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Future.wait<dynamic>([
        widget.api.detail(widget.id),
        widget.api.options(),
      ]);
      if (!mounted) return;
      final data = result[0] as Map<String, dynamic>;
      if (data['requisition_status'] != 'DRAFT') {
        throw const StaffAuthException('초안 상태의 품의만 수정할 수 있습니다.');
      }
      for (final item in items) {
        item.quantity.dispose();
      }
      items.clear();
      title.text = data['title'] as String;
      reason.text = data['reason'] as String;
      for (final raw in data['items'] as List<dynamic>) {
        items.add((
          variant: raw['product_variant_id'] as int,
          quantity: TextEditingController(text: '${raw['requested_quantity']}'),
        ));
      }
      final manufacturers = (data['items'] as List<dynamic>)
          .map((i) => i['manufacturer_id'])
          .toSet();
      setState(() {
        detail = data;
        options = result[1] as List<Map<String, dynamic>>;
        manufacturerId = manufacturers.length == 1
            ? manufacturers.first as int?
            : null;
      });
    } on StaffAuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (saving || detail == null) return;
    final quantities = [
      for (final item in items) int.tryParse(item.quantity.text.trim()),
    ];
    if (manufacturerId == null ||
        title.text.trim().isEmpty ||
        title.text.trim().length > 150 ||
        reason.text.trim().isEmpty ||
        reason.text.trim().length > 2000 ||
        items.isEmpty ||
        items.length > 100 ||
        items.any((i) => i.variant == null) ||
        quantities.any((q) => q == null || q <= 0 || q > 4294967295) ||
        items.map((i) => i.variant).toSet().length != items.length) {
      setState(() => error = '제조사·품목·양의 수량·제목·사유를 확인해주세요. 중복 품목은 합쳐주세요.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.update(widget.id, {
        'manufacturer_id': manufacturerId,
        'branch_id': detail!['branch_id'],
        'title': title.text.trim(),
        'reason': reason.text.trim(),
        'revision': detail!['revision'],
        'items': [
          for (var i = 0; i < items.length; i++)
            {
              'product_variant_id': items[i].variant,
              'requested_quantity': quantities[i],
            },
        ],
      });
      if (mounted) Navigator.pop(context, true);
    } on StaffAuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  List<Map<String, dynamic>> get selectable =>
      options.where((o) => o['manufacturer_id'] == manufacturerId).toList();

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text('품의 #${widget.id} 초안 수정'),
      content: SizedBox(
        width: 650,
        child: loading
            ? const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (detail != null) ...[
                      TextField(
                        key: const Key('edit-requisition-title'),
                        controller: title,
                        enabled: !saving,
                        maxLength: 150,
                        decoration: const InputDecoration(labelText: '품의 제목'),
                      ),
                      TextField(
                        key: const Key('edit-requisition-reason'),
                        controller: reason,
                        enabled: !saving,
                        maxLines: 3,
                        maxLength: 2000,
                        decoration: const InputDecoration(labelText: '구매 사유'),
                      ),
                      DropdownButtonFormField<int>(
                        key: ValueKey('edit-manufacturer-$manufacturerId'),
                        initialValue:
                            options.any(
                              (o) => o['manufacturer_id'] == manufacturerId,
                            )
                            ? manufacturerId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '제조사'),
                        items: [
                          for (final entry in {
                            for (final o in options)
                              o['manufacturer_id'] as int:
                                  o['manufacturer_name'] as String,
                          }.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) => setState(() {
                                if (value == manufacturerId) return;
                                manufacturerId = value;
                                for (var i = 0; i < items.length; i++) {
                                  items[i] = (
                                    variant: null,
                                    quantity: items[i].quantity,
                                  );
                                }
                              }),
                      ),
                      for (var i = 0; i < items.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<int>(
                                key: ValueKey(
                                  'edit-item-$i-$manufacturerId-${items[i].variant}',
                                ),
                                initialValue:
                                    selectable.any(
                                      (o) =>
                                          o['product_variant_id'] ==
                                          items[i].variant,
                                    )
                                    ? items[i].variant
                                    : null,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: '품목 ${i + 1}',
                                ),
                                items: [
                                  for (final o in selectable)
                                    DropdownMenuItem(
                                      value: o['product_variant_id'] as int,
                                      child: Text(
                                        '${o['product_name']} · ${o['color_name']} / ${o['size_mm']}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: saving
                                    ? null
                                    : (value) => setState(
                                        () => items[i] = (
                                          variant: value,
                                          quantity: items[i].quantity,
                                        ),
                                      ),
                              ),
                              if (items[i].variant != null &&
                                  !selectable.any(
                                    (o) =>
                                        o['product_variant_id'] ==
                                        items[i].variant,
                                  ))
                                const Text(
                                  '기존 옵션이 비활성 상태이거나 제조사가 다릅니다. 상품을 다시 선택해주세요.',
                                ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      key: ValueKey('edit-quantity-$i'),
                                      controller: items[i].quantity,
                                      enabled: !saving,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: '수량',
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '품목 삭제',
                                    onPressed: saving
                                        ? null
                                        : () => setState(() {
                                            items
                                                .removeAt(i)
                                                .quantity
                                                .dispose();
                                          }),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      TextButton.icon(
                        onPressed: saving || items.length >= 100
                            ? null
                            : () => setState(
                                () => items.add((
                                  variant: null,
                                  quantity: TextEditingController(text: '100'),
                                )),
                              ),
                        icon: const Icon(Icons.add),
                        label: const Text('품목 추가'),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: saving || loading ? null : load,
          child: const Text('다시 불러오기'),
        ),
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const Key('edit-requisition-save'),
          onPressed: saving || loading || detail == null ? null : save,
          child: Text(saving ? '저장 중…' : '수정 저장'),
        ),
      ],
    ),
  );
}
