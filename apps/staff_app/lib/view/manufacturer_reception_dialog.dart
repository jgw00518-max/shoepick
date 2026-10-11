import 'dart:math';
import 'package:flutter/material.dart';
import '../model/staff_session.dart';
import '../vm/manufacturer_order_api.dart';

class ManufacturerReceptionDialog extends StatefulWidget {
  const ManufacturerReceptionDialog({
    super.key,
    required this.api,
    required this.id,
    required this.accept,
    required this.quantity,
  });
  final ManufacturerOrderApi api;
  final int id;
  final bool accept;
  final int quantity;
  @override
  State<ManufacturerReceptionDialog> createState() =>
      _ManufacturerReceptionDialogState();
}

class _ManufacturerReceptionDialogState
    extends State<ManufacturerReceptionDialog> {
  final comment = TextEditingController();
  final requestId = List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String method = 'PHONE';
  bool saving = false;
  String? error;
  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (!widget.accept && comment.text.trim().isEmpty) {
      setState(() => error = '접수 거절 사유를 입력해주세요.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.api.recordReception(
        widget.id,
        decision: widget.accept ? 'ACCEPTED' : 'REJECTED',
        method: method,
        comment: comment.text,
        requestId: requestId,
      );
      if (mounted) Navigator.pop(context, result);
    } on StaffAuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text(widget.accept ? '접수 확인 및 전체 입고' : '제조사 접수 거절'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.accept
                    ? '확정하면 발주 수량 ${widget.quantity}켤레 전체가 본사에 입고되고 재고에 반영됩니다.'
                    : '제조사의 접수 거절을 기록합니다. 본사 재고는 변경되지 않습니다.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: '확인 방법'),
                items: const [
                  DropdownMenuItem(value: 'PHONE', child: Text('전화')),
                  DropdownMenuItem(value: 'EMAIL', child: Text('이메일')),
                  DropdownMenuItem(value: 'OTHER', child: Text('기타')),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => method = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: comment,
                enabled: !saving,
                minLines: 3,
                maxLines: 5,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: widget.accept ? '확인 메모 (선택)' : '접수 거절 사유 (필수)',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (saving) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(widget.accept ? '전체 입고 확정' : '기록 저장'),
        ),
      ],
    ),
  );
}
