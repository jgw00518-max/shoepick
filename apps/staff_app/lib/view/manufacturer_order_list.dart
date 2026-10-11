import 'package:flutter/material.dart';
import '../model/manufacturer_order.dart';
import '../model/purchase_requisition.dart';
import '../model/staff_session.dart';
import '../vm/manufacturer_order_api.dart';
import 'list_order_dropdown.dart';
import 'manufacturer_reception_dialog.dart';

class ManufacturerOrderList extends StatefulWidget {
  const ManufacturerOrderList({super.key, required this.api});
  final ManufacturerOrderApi api;
  @override
  State<ManufacturerOrderList> createState() => _ManufacturerOrderListState();
}

class _ManufacturerOrderListState extends State<ManufacturerOrderList> {
  final search = TextEditingController();
  int page = 1, requestNumber = 0;
  String order = 'desc', keyword = '';
  bool loading = false;
  int? detailLoading;
  String? error;
  ManufacturerOrderPage? result;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final request = ++requestNumber;
    setState(() {
      loading = true;
      error = null;
      result = null;
    });
    try {
      final data = await widget.api.list(
        page: page,
        order: order,
        keyword: keyword,
      );
      if (mounted && request == requestNumber) {
        setState(() => result = data);
      }
    } on StaffAuthException catch (e) {
      if (mounted && request == requestNumber) {
        setState(() => error = e.message);
      }
    } finally {
      if (mounted && request == requestNumber) {
        setState(() => loading = false);
      }
    }
  }

  String date(dynamic value) => '$value'.replaceAll('T', ' ');
  String receptionLabel(dynamic status) => switch (status) {
    'ACCEPTED' => '접수 확인',
    'REJECTED' => '접수 거절',
    _ => '확인 대기',
  };
  Future<void> detail(int id) async {
    if (detailLoading != null) return;
    setState(() => detailLoading = id);
    try {
      final data = await widget.api.detail(id);
      if (!mounted) return;
      final changed = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${data['order_number']} · ${data['title']}'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('제조사: ${data['manufacturer_name']}'),
                  Text(
                    '근거 품의: #${data['purchase_requisition_id']} · ${requisitionStatusLabels[data['requisition_status']] ?? data['requisition_status']}',
                  ),
                  Text('품의 작성자: ${data['requested_by_name']}'),
                  Text(
                    '발주 등록: ${data['registered_by_name'] ?? '—'} · ${date(data['registered_at'])}',
                  ),
                  const Text('전달 상태: 외부 전송 전'),
                  Text('제조사 접수: ${receptionLabel(data['reception_status'])}'),
                  Text(
                    data['goods_receipt'] == null
                        ? '입고: 입고 기록 없음'
                        : '입고 완료: ${data['goods_receipt']['total_received_quantity']}켤레 · ${date(data['goods_receipt']['received_at'])}',
                  ),
                  if (data['goods_receipt'] != null)
                    for (final received
                        in data['goods_receipt']['items'] as List<dynamic>)
                      Text(
                        '옵션 #${received['product_variant_id']}: 입고 ${received['received_quantity']}켤레 · 입고 처리 후 본사 실물 재고 ${received['on_hand_after']}켤레',
                      ),
                  if (data['reception'] != null) ...[
                    Text(
                      '확인 직원: ${data['reception']['recorded_by_name'] ?? '—'} · ${date(data['reception']['recorded_at'])}',
                    ),
                    Text(
                      '확인 방법: ${const {'PHONE': '전화', 'EMAIL': '이메일', 'OTHER': '기타'}[data['reception']['confirmation_method']]}',
                    ),
                    if (data['reception']['comment'] != '')
                      Text('메모·사유: ${data['reception']['comment']}'),
                  ],
                  const SizedBox(height: 12),
                  Text('구매 사유: ${data['reason']}'),
                  const Divider(),
                  const Text(
                    '발주 당시 품목',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final item in data['items'] as List<dynamic>)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${item['product_code']} · ${item['product_name']} · ${item['color_name']} / ${item['size_mm']} · ${item['requested_quantity']}켤레',
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    '총 ${data['item_count']}개 품목 / ${data['total_requested_quantity']}켤레',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (data['can_record_reception'] == true)
              for (final accept in [false, true])
                FilledButton(
                  onPressed: () async {
                    final saved = await showDialog<Map<String, dynamic>>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => ManufacturerReceptionDialog(
                        api: widget.api,
                        id: id,
                        accept: accept,
                        quantity: data['total_requested_quantity'] as int,
                      ),
                    );
                    if (saved != null && context.mounted) {
                      Navigator.pop(context, saved);
                    }
                  },
                  child: Text(accept ? '접수 확인 및 전체 입고' : '접수 거절'),
                ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        ),
      );
      if (changed != null && mounted) {
        await refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                changed['goods_receipt'] == null
                    ? '제조사 접수 결과를 기록했습니다.'
                    : '접수 확인 및 전체 입고 완료: ${changed['goods_receipt']['total_received_quantity']}켤레가 본사 재고에 반영되었습니다.',
              ),
            ),
          );
        }
      }
    } on StaffAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() => detailLoading = null);
      }
    }
  }

  void applySearch() {
    keyword = search.text.trim();
    page = 1;
    refresh();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ListOrderDropdown(
            value: order,
            onChanged: (value) {
              order = value;
              page = 1;
              refresh();
            },
          ),
          SizedBox(
            width: 280,
            child: TextField(
              key: const Key('manufacturer-order-search'),
              controller: search,
              decoration: const InputDecoration(
                labelText: '제조사·품의 제목·발주번호 검색',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => applySearch(),
            ),
          ),
          OutlinedButton(
            onPressed: loading ? null : applySearch,
            child: const Text('검색'),
          ),
          OutlinedButton(
            onPressed: loading ? null : refresh,
            child: const Text('새로고침'),
          ),
          Text('총 ${result?.totalCount ?? 0}건 · $page페이지'),
        ],
      ),
      const SizedBox(height: 16),
      if (loading) const LinearProgressIndicator(),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (!loading && error == null && result?.rows.isEmpty == true)
        const Text('조회 가능한 발주 내역이 없습니다.'),
      for (final row in result?.rows ?? <Map<String, dynamic>>[])
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['order_number']} · ${row['title']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('제조사: ${row['manufacturer_name']}'),
                Text(
                  '${row['item_count']}개 품목 / ${row['total_requested_quantity']}켤레',
                ),
                Text(
                  '등록일: ${date(row['registered_at'])} · ${row['registered_by_name'] ?? '—'}',
                ),
                const Text('전달 상태: 외부 전송 전'),
                Text('제조사 접수: ${receptionLabel(row['reception_status'])}'),
                Text(
                  row['goods_receipt'] == null
                      ? '입고: 입고 기록 없음'
                      : '입고 완료: ${row['goods_receipt']['total_received_quantity']}켤레',
                ),
                TextButton(
                  key: ValueKey(
                    'manufacturer-order-detail-${row['audit_log_id']}',
                  ),
                  onPressed: detailLoading != null
                      ? null
                      : () => detail(row['audit_log_id'] as int),
                  child: const Text('상세 보기'),
                ),
              ],
            ),
          ),
        ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: loading || page <= 1
                ? null
                : () {
                    page--;
                    refresh();
                  },
            child: const Text('이전'),
          ),
          OutlinedButton(
            onPressed: loading || page * 20 >= (result?.totalCount ?? 0)
                ? null
                : () {
                    page++;
                    refresh();
                  },
            child: const Text('다음'),
          ),
        ],
      ),
    ],
  );
}
