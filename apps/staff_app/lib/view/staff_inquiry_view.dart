import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../vm/auth_api.dart';
import '../vm/staff_inquiry_vm.dart';

/// 직원 문의 전용 화면. 표시 직급 선택은 서버의 권한 근거가 아니다.
class StaffInquiryView extends StatefulWidget {
  const StaffInquiryView({super.key, this.read, this.write});
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  write;
  final Future<Map<String, dynamic>> Function(String)? read;
  @override
  State<StaffInquiryView> createState() => _StaffInquiryViewState();
}

class _StaffInquiryViewState extends State<StaffInquiryView> {
  late final StaffInquiryVm _vm;
  bool _opening = false;
  final _answerController = TextEditingController();
  @override
  void initState() {
    super.initState();
    _vm = StaffInquiryVm(
      read: widget.read ?? (path) => AuthApi().getResponse(path),
      write: widget.write ?? (path, body) => AuthApi().post(path, body),
    );
    _vm.onStart();
  }

  @override
  void dispose() {
    _vm.onDelete();
    _answerController.dispose();
    super.dispose();
  }

  String _status(dynamic value) => switch (value) {
    'OPEN' => '답변 대기',
    'ANSWERED' => '답변 완료',
    'CLOSED' => '종료',
    _ => '상태 확인 필요 ($value)',
  };
  Future<void> _open(int id) async {
    if (_opening || _vm.saving) return;
    _answerController.text = _vm.pendingAnswer(id);
    _opening = true;
    _vm.loadDetail(id);
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => GetBuilder<StaffInquiryVm>(
          init: _vm,
          global: false,
          autoRemove: false,
          builder: (vm) => AlertDialog(
            title: Text(vm.detail?['title'] as String? ?? '문의 상세'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: vm.detailLoading
                    ? const Center(child: CircularProgressIndicator())
                    : vm.detailError != null
                    ? Column(
                        children: [
                          Text(vm.detailError!),
                          TextButton(
                            onPressed: () => vm.loadDetail(id),
                            child: const Text('상세 다시 시도'),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_status(vm.detail?['inquiry_status'])),
                          Text(
                            '${vm.detail?['inquiry_type']} · ${vm.detail?['created_at']}',
                          ),
                          Text(vm.detail?['inquiry_content'] as String? ?? ''),
                          const Divider(),
                          if ((vm.detail?['responses'] as List? ?? []).isEmpty)
                            const Text('등록된 답변이 없습니다.'),
                          for (final row
                              in vm.detail?['responses'] as List? ?? []) ...[
                            Text(row['response_content'] as String),
                            Text('${row['responded_at']}'),
                          ],
                          if (vm.detail?['inquiry_status'] == 'OPEN') ...[
                            TextField(
                              controller: _answerController,
                              enabled: !vm.saving,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: '답변 내용',
                              ),
                            ),
                            if (vm.answerError != null) Text(vm.answerError!),
                            FilledButton(
                              onPressed: vm.saving
                                  ? null
                                  : () async {
                                      final saved = await vm.answer(
                                        id,
                                        _answerController.text,
                                      );
                                      if (!mounted || !context.mounted) return;
                                      if (saved) {
                                        _answerController.clear();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('답변이 등록되었습니다.'),
                                          ),
                                        );
                                      }
                                    },
                              child: Text(vm.saving ? '저장 중' : '답변 등록'),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: vm.saving ? null : () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _vm.closeDetail();
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => GetBuilder<StaffInquiryVm>(
    init: _vm,
    global: false,
    autoRemove: false,
    builder: (vm) => Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('고객 문의'),
            DropdownButton<String>(
              value: vm.status ?? '',
              onChanged: vm.loading
                  ? null
                  : (value) {
                      vm.status = value == '' ? null : value;
                      vm.fetch();
                    },
              items: const [
                DropdownMenuItem(value: '', child: Text('전체')),
                DropdownMenuItem(value: 'OPEN', child: Text('답변 대기')),
                DropdownMenuItem(value: 'ANSWERED', child: Text('답변 완료')),
                DropdownMenuItem(value: 'CLOSED', child: Text('종료')),
              ],
            ),
            if (vm.loading)
              const Center(child: CircularProgressIndicator())
            else if (vm.error != null) ...[
              Text(vm.error!),
              TextButton(
                onPressed: () => vm.fetch(targetPage: vm.page),
                child: const Text('다시 시도'),
              ),
            ] else ...[
              if (vm.rows.isEmpty) const Text('문의가 없습니다.'),
              for (final row in vm.rows)
                ListTile(
                  title: Text(row['title'] as String),
                  subtitle: Text(
                    '${_status(row['inquiry_status'])} · ${row['created_at']}',
                  ),
                  onTap: () => _open(row['inquiry_id'] as int),
                ),
              Row(
                children: [
                  TextButton(
                    onPressed: vm.page > 1
                        ? () => vm.fetch(targetPage: vm.page - 1)
                        : null,
                    child: const Text('이전'),
                  ),
                  Text('${vm.page}페이지 · 총 ${vm.total}건'),
                  TextButton(
                    onPressed: vm.hasNext
                        ? () => vm.fetch(targetPage: vm.page + 1)
                        : null,
                    child: const Text('다음'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
