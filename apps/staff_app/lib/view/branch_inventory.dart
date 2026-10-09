import 'package:flutter/material.dart';
import 'package:shoepick_staff_app/model/branch_inventory.dart';
import 'package:shoepick_staff_app/model/staff_session.dart';
import 'package:shoepick_staff_app/vm/branch_inventory_api.dart';

class BranchInventoryView extends StatefulWidget {
  const BranchInventoryView({super.key, required this.branchId, this.api});

  final int? branchId;
  final BranchInventoryApi? api;

  @override
  State<BranchInventoryView> createState() => _BranchInventoryViewState();
}

class _BranchInventoryViewState extends State<BranchInventoryView> {
  late final BranchInventoryApi api;
  final searchController = TextEditingController();
  BranchInventoryPage? result;
  bool loading = false;
  String? error;
  int page = 1;
  int requestNumber = 0;
  String keyword = '';
  String status = 'READY_FOR_PICKUP';
  String sort = 'updated_at';

  @override
  void initState() {
    super.initState();
    api = widget.api ?? BranchInventoryApi();
    refresh();
  }

  @override
  void didUpdateWidget(covariant BranchInventoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId) {
      page = 1;
      keyword = '';
      searchController.clear();
      refresh();
    }
  }

  Future<void> refresh() async {
    final request = ++requestNumber;
    final branchId = widget.branchId;
    setState(() {
      loading = true;
      error = null;
      result = null;
    });
    try {
      if (branchId == null) {
        throw const StaffAuthException('조회할 소속 대리점을 선택해주세요.');
      }
      final response = await api.fetch(
        branchId: branchId,
        page: page,
        keyword: keyword,
        holdingStatus: status.isEmpty ? null : status,
        sort: sort,
      );
      if (!mounted || request != requestNumber) return;
      setState(() => result = response);
    } on StaffAuthException catch (exception) {
      if (mounted && request == requestNumber) {
        setState(() => error = exception.message);
      }
    } catch (_) {
      if (mounted && request == requestNumber) {
        setState(() => error = '대리점 보관 현황을 불러오지 못했습니다. 다시 시도해주세요.');
      }
    } finally {
      if (mounted && request == requestNumber) setState(() => loading = false);
    }
  }

  void search() {
    page = 1;
    keyword = searchController.text.trim();
    refresh();
  }

  String dateLabel(dynamic value) {
    final date = value is String ? DateTime.tryParse(value) : null;
    if (date == null) return '-';
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
  }

  @override
  void dispose() {
    searchController.dispose();
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = result?.rows ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('대리점 보관 현황', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('본사에서 받은 주문 상품을 상태별로 조회합니다.'),
            const SizedBox(height: 16),
            TextField(
              key: const Key('branch-inventory-search'),
              controller: searchController,
              decoration: InputDecoration(
                labelText: '상품명 또는 상품 코드',
                suffixIcon: IconButton(
                  tooltip: '검색',
                  icon: const Icon(Icons.search),
                  onPressed: loading ? null : search,
                ),
              ),
              onSubmitted: (_) => search(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  key: const Key('branch-inventory-status'),
                  value: status,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('전체 이력')),
                    for (final entry in branchHoldingStatusLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: loading
                      ? null
                      : (value) {
                          if (value == null) return;
                          status = value;
                          page = 1;
                          refresh();
                        },
                ),
                DropdownButton<String>(
                  value: sort,
                  items: const [
                    DropdownMenuItem(
                      value: 'updated_at',
                      child: Text('최근 변경순'),
                    ),
                    DropdownMenuItem(
                      value: 'received_at',
                      child: Text('최근 입고순'),
                    ),
                    DropdownMenuItem(
                      value: 'product_name',
                      child: Text('상품명순'),
                    ),
                    DropdownMenuItem(
                      value: 'product_code',
                      child: Text('상품 코드순'),
                    ),
                  ],
                  onChanged: loading
                      ? null
                      : (value) {
                          if (value == null) return;
                          sort = value;
                          page = 1;
                          refresh();
                        },
                ),
                OutlinedButton.icon(
                  onPressed: loading ? null : refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('새로고침'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (loading) const Center(child: CircularProgressIndicator()),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (result != null) ...[
              Text('조회 결과 ${result!.totalCount}건 · $page페이지'),
              if (status.isEmpty) const Text('전체 이력에는 입고 대기·수령 완료 기록도 포함됩니다.'),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Text('검색 조건에 맞는 보관 상품이 없습니다.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      for (final label in [
                        '대리점',
                        '제품',
                        '옵션',
                        '상품 코드',
                        '수량',
                        '상태',
                        '주문 번호',
                        '출고 번호',
                        '입고 시각',
                        '수령 시각',
                      ])
                        DataColumn(label: Text(label)),
                    ],
                    rows: [
                      for (final row in rows)
                        DataRow(
                          cells: [
                            for (final value in [
                              row['branch_name'],
                              row['product_name'],
                              '${row['color_name']} / ${row['size_mm']}',
                              row['product_code'],
                              row['quantity'],
                              branchHoldingStatusLabels[row['holding_status']] ??
                                  row['holding_status'],
                              row['order_number'],
                              row['fulfillment_number'],
                              dateLabel(row['received_at']),
                              dateLabel(row['picked_up_at']),
                            ])
                              DataCell(Text('$value')),
                          ],
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
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
                    onPressed:
                        loading || page * result!.pageSize >= result!.totalCount
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
          ],
        ),
      ),
    );
  }
}
