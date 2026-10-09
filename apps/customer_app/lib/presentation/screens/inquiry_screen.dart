import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../domain/models.dart';
import '../shared/store_widgets.dart';

const faqItems = <(String, String)>[
  (
    '상품은 어디에서 받나요?',
    '주문할 때 선택한 서울 지역 대리점에서 수령합니다. 본사에서 대리점으로 배송되며 자택으로 배송되지 않습니다.',
  ),
  (
    '언제 픽업할 수 있나요?',
    '주문 내역의 픽업 배송 조회에서 대리점 도착 여부를 확인해주세요. 픽업 가능 상태가 되면 영업시간 내 방문할 수 있습니다.',
  ),
  ('수령할 때 무엇이 필요한가요?', '주문 내역의 주문번호와 주문자 정보를 직원에게 보여주세요.'),
  (
    '쿠폰과 적립금을 같이 사용할 수 있나요?',
    '결제 화면에서 조건에 맞는 쿠폰 한 장과 적립금을 함께 사용할 수 있습니다. 보유 적립금과 결제 금액을 초과할 수 없습니다.',
  ),
  ('사이즈가 품절이면 주문할 수 있나요?', '품절된 사이즈는 선택할 수 없습니다. 재입고 일정은 상품 상세의 문의하기로 확인해주세요.'),
  ('대리점 운영시간은 어떻게 확인하나요?', '주문 내역의 픽업 배송 조회 화면에서 운영시간과 대리점 연락처를 확인할 수 있습니다.'),
];

/// FAQ와 문의 접수·목록·답변을 모두 목업 Repository에 연결합니다.
class InquiryScreen extends StatefulWidget {
  const InquiryScreen({
    super.key,
    required this.store,
    required this.onMessage,
    this.product,
  });
  final StoreController store;
  final Product? product;
  final void Function(String) onMessage;
  @override
  State<InquiryScreen> createState() => _InquiryScreenState();
}

class _InquiryScreenState extends State<InquiryScreen> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final body = TextEditingController();
  late String kind;
  @override
  void initState() {
    super.initState();
    kind = widget.product == null ? '배송 문의' : '상품 문의';
    if (widget.product != null) title.text = '${widget.product!.name} 상품 문의';
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    await widget.store.addInquiry(kind, title.text.trim(), body.text.trim());
    title.clear();
    body.clear();
    widget.onMessage('문의가 접수되었습니다. 답변 등록 시 알려드릴게요.');
  }

  void _openEntry(InquiryEntry entry) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: LText(entry.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            '${entry.answered ? '답변 완료' : '답변 대기'} · ${entry.date} · ${entry.kind}',
          ),
          const SizedBox(height: 12),
          LText('Q  ${entry.body}'),
          const SizedBox(height: 12),
          LText(
            'A  ${entry.answer ?? '담당자가 문의 내용을 확인하고 있습니다. 답변이 등록되면 알림으로 알려드릴게요.'}',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const LText('닫기'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const SectionTitle('문의 사항'),
      LText(
        widget.product == null
            ? '궁금한 점을 남기면 빠르게 답변해드려요.'
            : '${widget.product!.name}에 대해 문의해보세요.',
      ),
      const SizedBox(height: 18),
      const SectionTitle('자주 묻는 질문'),
      for (final faq in faqItems)
        ExpansionTile(
          title: LText(faq.$1),
          children: [
            Padding(padding: const EdgeInsets.all(14), child: LText(faq.$2)),
          ],
        ),
      const SizedBox(height: 20),
      Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('1:1 문의'),
            DropdownButtonFormField<String>(
              initialValue: kind,
              decoration: const InputDecoration(
                labelText: '문의 유형',
                border: OutlineInputBorder(),
              ),
              items: ['상품 문의', '배송 문의', '결제 문의', '기타 문의']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: LText(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => kind = value!),
            ),
            if (widget.product != null)
              ListTile(
                leading: SizedBox(
                  width: 56,
                  child: ProductImage(widget.product!, height: 56),
                ),
                title: LText(widget.product!.name),
                subtitle: const LText('문의 상품'),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: title,
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '문의 제목을 입력하세요',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? '문의 제목을 입력해주세요.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: body,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '내용',
                hintText: '문의 내용을 자세히 입력해주세요',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? '문의 내용을 입력해주세요.' : null,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const LText('문의 접수'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      SectionTitle('문의 목록 · ${widget.store.inquiries.length}건'),
      for (final entry in widget.store.inquiries)
        ListTile(
          title: LText(entry.title),
          subtitle: LText(
            '${entry.answered ? '답변 완료' : '답변 대기'} · ${entry.date} · ${entry.kind}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openEntry(entry),
        ),
    ],
  );
}
