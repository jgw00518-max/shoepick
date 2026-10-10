import 'package:flutter/material.dart';
import '../model/staff_session.dart';
import '../vm/purchase_approval_api.dart';

class ApprovalDecisionDialog extends StatefulWidget {
  const ApprovalDecisionDialog({
    super.key,
    required this.api,
    required this.id,
    required this.approve,
    required this.revision,
    required this.stage,
  });
  final PurchaseApprovalApi api;
  final int id;
  final bool approve;
  final String revision;
  final String stage;
  @override
  State<ApprovalDecisionDialog> createState() => _ApprovalDecisionDialogState();
}

class _ApprovalDecisionDialogState extends State<ApprovalDecisionDialog> {
  final comment = TextEditingController();
  bool saving = false;
  String? error;
  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (!widget.approve && comment.text.trim().isEmpty) {
      setState(() => error = '반려 사유를 입력해주세요.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.api.decide(
        widget.id,
        approve: widget.approve,
        revision: widget.revision,
        comment: comment.text,
        stage: widget.stage,
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
      title: Text(
        '${widget.stage == 'DIRECTOR' ? '이사' : '팀장'} ${widget.approve ? '승인' : '반려'}',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.stage == 'DIRECTOR'
                    ? (widget.approve
                          ? '최종 승인하면 제조사 발주가 자동 등록됩니다. 제조사 외부 전송은 별도입니다.'
                          : '반려하면 품의가 반려 처리됩니다.')
                    : widget.approve
                    ? '승인하면 이사 결재 대기로 넘어갑니다.'
                    : '반려하면 이사 결재를 진행하지 않습니다.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: comment,
                enabled: !saving,
                minLines: 3,
                maxLines: 5,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: widget.approve ? '결재 의견 (선택)' : '반려 사유 (필수)',
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
          child: Text(widget.approve ? '승인 확정' : '반려 확정'),
        ),
      ],
    ),
  );
}
