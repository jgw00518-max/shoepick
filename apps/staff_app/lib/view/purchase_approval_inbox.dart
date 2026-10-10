import 'package:flutter/material.dart';
import '../model/purchase_approval.dart';
import '../model/purchase_requisition.dart';
import '../model/staff_session.dart';
import '../vm/purchase_approval_api.dart';
import 'list_order_dropdown.dart';
import 'approval_decision_dialog.dart';

class PurchaseApprovalInbox extends StatefulWidget {
  const PurchaseApprovalInbox({
    super.key,
    required this.api,
    required this.stage,
  });
  final PurchaseApprovalApi api;
  final String stage;
  @override
  State<PurchaseApprovalInbox> createState() => _PurchaseApprovalInboxState();
}

class _PurchaseApprovalInboxState extends State<PurchaseApprovalInbox> {
  bool get monitor => widget.stage == 'EXECUTIVE';
  final searchController = TextEditingController();
  String? status;
  String keyword = '';
  DateTime? submittedFrom, submittedTo;
  String view = 'pending';
  String order = 'desc';
  int page = 1, requestNumber = 0;
  bool loading = false;
  int? detailLoading;
  String? error;
  PurchaseApprovalPage? result;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void search() {
    setState(() {
      keyword = searchController.text.trim();
      page = 1;
    });
    refresh();
  }

  Future<void> selectDate(bool start) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: (start ? submittedFrom : submittedTo) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        submittedFrom = selected;
      } else {
        submittedTo = selected;
      }
      page = 1;
    });
    refresh();
  }

  String monitorResult(
    dynamic decision,
    dynamic current,
    String pendingStatus,
  ) {
    if (decision == null) return '미배정';
    if (decision == 'PENDING') {
      return current == pendingStatus ? '결재 대기' : '미진행';
    }
    return approvalStatusLabels[decision] ?? '$decision';
  }

  @override
  void didUpdateWidget(covariant PurchaseApprovalInbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage) {
      page = 1;
      view = 'pending';
      refresh();
    }
  }

  Future<void> refresh() async {
    final request = ++requestNumber;
    setState(() {
      loading = true;
      error = null;
      result = null;
    });
    try {
      if (monitor &&
          submittedFrom != null &&
          submittedTo != null &&
          submittedFrom!.isAfter(submittedTo!)) {
        throw const StaffAuthException('조회 시작일은 종료일보다 늦을 수 없습니다.');
      }
      final response = monitor
          ? await widget.api.overview(
              page: page,
              status: status,
              keyword: keyword,
              submittedFrom: submittedFrom?.toIso8601String().substring(0, 10),
              submittedTo: submittedTo?.toIso8601String().substring(0, 10),
              order: order,
            )
          : await widget.api.list(
              stage: widget.stage,
              view: view,
              page: page,
              order: order,
            );
      if (mounted && request == requestNumber) {
        setState(() => result = response);
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

  String date(dynamic value) {
    final d = DateTime.tryParse('$value');
    if (d == null) return '—';
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${d.year}.${pad(d.month)}.${pad(d.day)} ${pad(d.hour)}:${pad(d.minute)}';
  }

  Future<void> openDetail(int id) async {
    if (detailLoading != null) return;
    setState(() => detailLoading = id);
    try {
      final data = monitor
          ? await widget.api.overviewDetail(id)
          : await widget.api.detail(id, widget.stage);
      if (!mounted) return;
      final document = data['requisition'] as Map<String, dynamic>;
      final canDecide =
          (widget.stage == 'TEAM_LEAD' || widget.stage == 'DIRECTOR') &&
          view == 'pending' &&
          document['requisition_status'] ==
              (widget.stage == 'DIRECTOR'
                  ? 'PENDING_DIRECTOR'
                  : 'PENDING_TEAM_LEAD') &&
          (data['approval'] as Map<String, dynamic>?)?['approval_status'] ==
              'PENDING';
      final processed = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            '품의 #${document['purchase_requisition_id']} · ${document['title']}',
          ),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '현재 상태: ${requisitionStatusLabels[document['requisition_status']] ?? document['requisition_status']}',
                  ),
                  Text('상신일: ${date(document['submitted_at'])}'),
                  const SizedBox(height: 12),
                  Text(document['reason'] as String),
                  const SizedBox(height: 12),
                  for (final item in document['items'] as List<dynamic>)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${item['product_name']} · ${item['color_name']} / ${item['size_mm']} · ${item['requested_quantity']}켤레',
                      ),
                    ),
                  const Divider(),
                  const Text(
                    '결재 단계와 처리 이력',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final step in data['steps'] as List<dynamic>)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${step['approval_sequence']}차 ${step['role_name']} · ${approvalStatusLabels[step['approval_status']] ?? step['approval_status']}',
                          ),
                          if (step['approver_name'] != null)
                            Text(
                              '${step['approver_name']} · ${date(step['decided_at'])}',
                            ),
                          if (step['approval_comment'] != null)
                            Text(step['approval_comment'] as String),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (canDecide)
              for (final approve in [false, true])
                FilledButton(
                  onPressed: () async {
                    final saved = await showDialog<Map<String, dynamic>>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => ApprovalDecisionDialog(
                        stage: widget.stage,
                        api: widget.api,
                        id: id,
                        approve: approve,
                        revision: document['revision'] as String,
                      ),
                    );
                    if (saved != null && context.mounted) {
                      Navigator.pop(context, saved);
                    }
                  },
                  child: Text(approve ? '승인' : '반려'),
                ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        ),
      );
      if (processed != null && mounted) {
        page = 1;
        await refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                processed['manufacturer_order'] == null
                    ? '결재 처리가 완료되었습니다. 내 처리 이력에서 확인할 수 있습니다.'
                    : '최종 승인 및 자동 발주 등록 완료: ${processed['manufacturer_order']['order_number']} (외부 전송 전)',
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
              setState(() {
                order = value;
                page = 1;
              });
              refresh();
            },
          ),
          if (monitor) ...[
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                key: ValueKey('monitor-status-${status ?? 'all'}'),
                initialValue: status ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '품의 상태',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('전체 상태')),
                  for (final entry in requisitionStatusLabels.entries.where(
                    (e) => e.key != 'DRAFT',
                  ))
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    status = value == '' ? null : value;
                    page = 1;
                  });
                  refresh();
                },
              ),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                key: const Key('monitor-search'),
                controller: searchController,
                decoration: const InputDecoration(
                  labelText: '제목·작성자 검색',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => search(),
              ),
            ),
            OutlinedButton(
              onPressed: loading ? null : search,
              child: const Text('검색'),
            ),
            OutlinedButton(
              onPressed: () => selectDate(true),
              child: Text(
                submittedFrom == null
                    ? '상신 시작일'
                    : date(submittedFrom).substring(0, 10),
              ),
            ),
            OutlinedButton(
              onPressed: () => selectDate(false),
              child: Text(
                submittedTo == null
                    ? '상신 종료일'
                    : date(submittedTo).substring(0, 10),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  status = null;
                  keyword = '';
                  searchController.clear();
                  submittedFrom = null;
                  submittedTo = null;
                  page = 1;
                });
                refresh();
              },
              child: const Text('초기화'),
            ),
          ] else
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pending', label: Text('결재 대기')),
                ButtonSegment(value: 'history', label: Text('내 처리 이력')),
              ],
              selected: {view},
              onSelectionChanged: (selected) {
                setState(() {
                  view = selected.single;
                  page = 1;
                });
                refresh();
              },
            ),
          OutlinedButton.icon(
            key: const Key('approval-refresh'),
            onPressed: loading ? null : refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('새로고침'),
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
        Text(
          monitor
              ? '상신된 품의가 없습니다.'
              : view == 'pending'
              ? '결재 대기 품의가 없습니다.'
              : '본인이 처리한 결재 이력이 없습니다.',
        ),
      for (final row in result?.rows ?? <Map<String, dynamic>>[])
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '품의 #${row['purchase_requisition_id']} · ${row['title']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${row['employee_name']} · ${row['branch_name'] ?? '본사'} · ${row['item_count']}개 품목 / ${row['total_requested_quantity']}켤레',
                ),
                Text(
                  '현재 상태: ${requisitionStatusLabels[row['requisition_status']] ?? row['requisition_status']}',
                ),
                if (monitor) ...[
                  Text(
                    '팀장: ${monitorResult(row['team_approval_status'], row['requisition_status'], 'PENDING_TEAM_LEAD')} · ${row['team_approver_name'] ?? '—'}',
                  ),
                  Text(
                    '이사: ${monitorResult(row['director_approval_status'], row['requisition_status'], 'PENDING_DIRECTOR')} · ${row['director_approver_name'] ?? '—'}',
                  ),
                  Text('상신일: ${date(row['submitted_at'])}'),
                ] else if (view == 'history') ...[
                  Text(
                    '내 결재: ${approvalStatusLabels[row['approval_status']] ?? row['approval_status']} · ${date(row['decided_at'])}',
                  ),
                  if (row['approval_comment'] != null)
                    Text('의견: ${row['approval_comment']}'),
                ] else
                  Text('상신일: ${date(row['submitted_at'])}'),
                TextButton(
                  key: ValueKey(
                    'approval-detail-${monitor ? row['purchase_requisition_id'] : row['purchase_approval_id']}',
                  ),
                  onPressed: detailLoading != null
                      ? null
                      : () => openDetail(
                          (monitor
                                  ? row['purchase_requisition_id']
                                  : row['purchase_approval_id'])
                              as int,
                        ),
                  child: Text(
                    detailLoading ==
                            (monitor
                                ? row['purchase_requisition_id']
                                : row['purchase_approval_id'])
                        ? '불러오는 중…'
                        : '상세 보기',
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 12),
      Row(
        children: [
          OutlinedButton(
            key: const Key('approval-previous'),
            onPressed: loading || page <= 1
                ? null
                : () {
                    setState(() => page--);
                    refresh();
                  },
            child: const Text('이전'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const Key('approval-next'),
            onPressed: loading || page * 20 >= (result?.totalCount ?? 0)
                ? null
                : () {
                    setState(() => page++);
                    refresh();
                  },
            child: const Text('다음'),
          ),
        ],
      ),
    ],
  );
}
