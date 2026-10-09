import 'package:flutter/material.dart';
import 'package:shoepick_staff_app/model/staff_session.dart';
import 'package:shoepick_staff_app/vm/staff_work_api.dart';

class BranchReturnRegistration extends StatefulWidget {
  const BranchReturnRegistration({
    super.key,
    required this.branchId,
    required this.api,
    required this.onRegistered,
  });
  final int? branchId;
  final StaffWorkApi api;
  final Future<void> Function() onRegistered;

  @override
  State<BranchReturnRegistration> createState() =>
      _BranchReturnRegistrationState();
}

class _BranchReturnRegistrationState extends State<BranchReturnRegistration> {
  final code = TextEditingController();
  final reason = TextEditingController();
  Map<String, dynamic>? order;
  final quantities = <String, int>{};
  String reasonCode = 'CUSTOMER_CHANGE';
  bool unworn = false;
  bool undamaged = false;
  bool completePackaging = false;
  bool busy = false;
  String? error;
  String? receipt;

  @override
  void dispose() {
    code.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> lookup() async {
    if (busy) return;
    if (widget.branchId == null || code.text.trim().isEmpty) {
      setState(() => error = '소속 지점을 선택하고 주문번호를 입력해주세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      order = null;
      receipt = null;
      quantities.clear();
    });
    try {
      final result = await widget.api.lookupReturnOrder(
        widget.branchId!,
        code.text,
      );
      if (!mounted) return;
      setState(() {
        order = result;
        reason.clear();
        reasonCode = 'CUSTOMER_CHANGE';
        unworn = false;
        undamaged = false;
        completePackaging = false;
      });
    } on StaffAuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = '주문을 조회하지 못했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy || order == null) return;
    if (quantities.isEmpty || reason.text.trim().isEmpty) {
      setState(() => error = '반품 상품·수량을 선택하고 사유를 입력해주세요.');
      return;
    }
    if (reasonCode == 'CUSTOMER_CHANGE' &&
        !(unworn && undamaged && completePackaging)) {
      setState(() => error = '단순변심 반품은 미착용·훼손 없음·구성품 및 포장 유지 조건을 확인해주세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await widget.api.registerReturn(
        order!['orderId'] as int,
        {
          'reason': reason.text.trim(),
          'reasonCode': reasonCode,
          'unworn': unworn,
          'undamaged': undamaged,
          'completePackaging': completePackaging,
          'items': [
            for (final entry in quantities.entries)
              {'itemKey': entry.key, 'quantity': entry.value},
          ],
        },
      );
      if (!mounted) return;
      setState(() {
        receipt = '반품 #${response['id']} 접수 완료 · 본사 검수 대기';
        order = null;
        quantities.clear();
        code.clear();
        reason.clear();
      });
      await widget.onRegistered();
    } on StaffAuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = '접수 결과를 확인하지 못했습니다. 반품 현황을 확인한 뒤 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = order;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('return-order-code'),
          controller: code,
          enabled: !busy,
          onChanged: (_) {
            if (order != null) {
              setState(() {
                order = null;
                quantities.clear();
                error = null;
              });
            }
          },
          onSubmitted: (_) => lookup(),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: '주문번호 / 픽업 결제 코드',
            hintText: '고객이 제시한 코드를 입력하세요',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('return-order-lookup'),
            onPressed: busy ? null : lookup,
            icon: const Icon(Icons.search),
            label: const Text('주문 조회'),
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: const TextStyle(color: Color(0xFFB52638)),
            ),
          ),
        if (receipt != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              receipt!,
              style: const TextStyle(
                color: Color(0xFF126D66),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (selected != null) ...[
          const Divider(height: 32),
          Text(
            '${selected['customerName']} · ${selected['orderNumber']}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '${selected['branchName']}\n수령일 ${selected['pickedUpAt'].toString().split('T').first}\n단순변심 접수 기한 ${selected['returnDeadlineAt'].toString().replaceFirst('T', ' ')}',
          ),
          const SizedBox(height: 16),
          const Text(
            '반품할 상품과 수량',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final raw in selected['items'] as List<dynamic>) ...[
            Builder(
              builder: (context) {
                final item = raw as Map<String, dynamic>;
                final key = item['itemKey'] as String;
                final maximum = (item['quantity'] as num).toInt();
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item['name'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${item['color']} / ${item['size']} · 구매 $maximum켤레',
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        key: Key('return-quantity-$key'),
                        initialValue: quantities[key] ?? 0,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '반품 수량',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (
                            var quantity = 0;
                            quantity <= maximum;
                            quantity++
                          )
                            DropdownMenuItem(
                              value: quantity,
                              child: Text(
                                quantity == 0 ? '선택 안 함' : '$quantity켤레',
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) => setState(() {
                                if (value == null || value == 0) {
                                  quantities.remove(key);
                                } else {
                                  quantities[key] = value;
                                }
                              }),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            key: const Key('return-reason-code'),
            initialValue: reasonCode,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '반품 구분',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'CUSTOMER_CHANGE',
                child: Text('단순변심 / 사이즈 불일치'),
              ),
              DropdownMenuItem(value: 'PRODUCT_DEFECT', child: Text('상품 하자')),
              DropdownMenuItem(value: 'WRONG_ITEM', child: Text('오배송')),
            ],
            onChanged: busy
                ? null
                : (value) => setState(() => reasonCode = value!),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('return-reason'),
            controller: reason,
            enabled: !busy,
            maxLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: '접수 사유',
              hintText: '고객의 반품 사유와 현장 확인 내용을 입력하세요',
              border: OutlineInputBorder(),
            ),
          ),
          if (reasonCode == 'CUSTOMER_CHANGE') ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('미착용 확인'),
              value: unworn,
              onChanged: busy
                  ? null
                  : (v) => setState(() => unworn = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('상품 훼손 없음 확인'),
              value: undamaged,
              onChanged: busy
                  ? null
                  : (v) => setState(() => undamaged = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('구성품 및 포장 유지 확인'),
              value: completePackaging,
              onChanged: busy
                  ? null
                  : (v) => setState(() => completePackaging = v ?? false),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('branch-return-submit'),
            onPressed: busy ? null : submit,
            icon: const Icon(Icons.assignment_return_outlined),
            label: const Text('반품 접수'),
          ),
          const SizedBox(height: 8),
          const Text(
            '접수 후 본사에서 실물 검수합니다. 접수만으로 환불되거나 재고가 복구되지는 않습니다.',
            style: TextStyle(color: Color(0xFF66768B), fontSize: 12),
          ),
        ],
      ],
    );
  }
}
