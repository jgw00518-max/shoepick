import 'package:flutter/material.dart';
import 'package:shupick_staff_mockup/auth/staff_session.dart';
import 'package:shupick_staff_mockup/dashboard/staff_work_api.dart';

class ReturnRefundPanel extends StatefulWidget {
  const ReturnRefundPanel({
    super.key,
    required this.returns,
    required this.api,
    required this.onProcessed,
  });
  final List<Map<String, dynamic>> returns;
  final StaffWorkApi api;
  final Future<void> Function() onProcessed;
  @override
  State<ReturnRefundPanel> createState() => _ReturnRefundPanelState();
}

class _ReturnRefundPanelState extends State<ReturnRefundPanel> {
  int? selectedId;
  Map<String, dynamic>? detail;
  bool busy = false;
  bool confirming = false;
  String? error;
  String? result;
  String money(dynamic number) => (num.tryParse('$number') ?? 0)
      .round()
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  Future<void> select(int id) async {
    if (busy) return;
    setState(() {
      selectedId = id;
      detail = null;
      error = null;
      result = null;
      busy = true;
    });
    try {
      final response = await widget.api.returnRefund(id);
      if (mounted) setState(() => detail = response);
    } on StaffAuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = '환불 내역을 불러오지 못했습니다. 다시 선택해주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> process() async {
    final quote = detail;
    if (busy || quote == null || quote['testPayment'] != true) return;
    setState(() {
      busy = true;
      confirming = true;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('테스트 환불 처리'),
          content: Text(
            '${quote['customerName']} · ${quote['orderNumber']}\n환불 금액 ${money(quote['refundAmount'])}원\n\n테스트 결제의 환불 완료를 기록합니다. 실제 결제사로 금액을 송금하지 않습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              key: const Key('confirm-return-refund'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('처리 확인'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() {
        error = null;
        result = null;
        confirming = false;
      });
      final response = await widget.api.processTestReturnRefund(
        quote['returnId'] as int,
        (quote['refundAmount'] as num).toInt(),
      );
      if (response['refundStatus'] != 'SUCCEEDED') {
        throw const StaffAuthException('환불이 아직 완료되지 않았습니다. 내역을 다시 조회해주세요.');
      }
      if (!mounted) return;
      setState(() {
        detail = {...quote, 'refund': response, 'returnStatus': 'COMPLETED'};
        result = '테스트 환불 완료 · ${response['refundNumber']}';
      });
      await widget.onProcessed();
    } on StaffAuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = '처리 결과를 확인하지 못했습니다. 내역을 다시 선택해 상태를 확인해주세요.');
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.returns
        .where(
          (row) => row['status'] == 'APPROVED' || row['status'] == 'COMPLETED',
        )
        .toList();
    final quote = detail;
    final completed = quote?['refund']?['refundStatus'] == 'SUCCEEDED';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entries.isEmpty) const Text('환불 가능한 승인 반품이 없습니다.'),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              elevation: 0,
              color: selectedId == entry['id']
                  ? const Color(0xFFEAF2FF)
                  : const Color(0xFFF7F9FC),
              child: ListTile(
                key: Key('refund-return-${entry['id']}'),
                title: Text('반품 #${entry['id']} · ${entry['orderNumber']}'),
                subtitle: Text(
                  '${entry['customerName']} · ${entry['status'] == 'COMPLETED' || (entry['id'] == selectedId && completed) ? '환불 완료' : '승인 · 환불 대기'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : () => select(entry['id'] as int),
              ),
            ),
          ),
        if (busy && !confirming) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: const TextStyle(color: Color(0xFFB52638)),
            ),
          ),
        if (result != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              result!,
              style: const TextStyle(
                color: Color(0xFF126D66),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (quote != null) ...[
          const Divider(height: 32),
          Text(
            '${quote['customerName']} · ${quote['orderNumber']}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          for (final item in quote['items'] as List<dynamic>)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${item['name']} · ${item['color']} / ${item['size']} × ${item['quantity']}\n현금 환불 ${money(item['refundAmount'])}원 · 배분 적립금 ${money(item['allocatedPoints'])}P',
              ),
            ),
          Text(
            '환불 금액 ${money(quote['refundAmount'])}원',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '배분된 사용 적립금 ${money(quote['allocatedPoints'])}P · 만료되지 않은 적립금은 기존 정책에 따라 복원됩니다.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF66768B)),
          ),
          const SizedBox(height: 8),
          const Text(
            '쿠폰 할인 금액은 현금 환불에 포함되지 않습니다.',
            style: TextStyle(fontSize: 12, color: Color(0xFF66768B)),
          ),
          const SizedBox(height: 16),
          if (completed)
            Text(
              '환불 완료 · ${quote['refund']['refundNumber']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            )
          else if (quote['testPayment'] != true)
            const Text('실제 결제사 연동이 필요한 결제입니다. 현재 화면의 테스트 환불 대상이 아닙니다.')
          else
            FilledButton.icon(
              key: const Key('process-return-refund'),
              onPressed: busy ? null : process,
              icon: const Icon(Icons.currency_exchange),
              label: const Text('테스트 환불 처리'),
            ),
        ],
      ],
    );
  }
}
