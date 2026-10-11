import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../vm/auth_api.dart';
import '../vm/inquiry_history_vm.dart';

/// 화면이 조회 상태를 소유하며 기존 작성 목업과 서버 목록을 섞지 않는다.
class InquiryHistoryView extends StatefulWidget {
  const InquiryHistoryView({super.key, this.request});
  final Future<Map<String, dynamic>> Function(String)? request;
  @override
  State<InquiryHistoryView> createState() => _InquiryHistoryViewState();
}

class _InquiryHistoryViewState extends State<InquiryHistoryView> {
  late final InquiryHistoryVm _vm;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    _vm = InquiryHistoryVm(
      request: widget.request ?? (path) => AuthApi().getResponse(path),
    );
    _vm.onStart();
  }

  @override
  void dispose() {
    _vm.onDelete();
    super.dispose();
  }

  Future<void> _open(int id) async {
    if (_opening) return;
    _opening = true;
    _vm.fetchDetail(id);
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => GetBuilder<InquiryHistoryVm>(
          init: _vm,
          global: false,
          autoRemove: false,
          builder: (vm) => AlertDialog(
            title: Text(vm.detail?.title ?? '문의 상세'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: vm.detailLoading
                    ? const Center(child: CircularProgressIndicator())
                    : vm.detailError != null
                    ? Column(
                        children: [
                          Text(vm.detailError!),
                          TextButton(
                            onPressed: () => vm.fetchDetail(id),
                            child: const Text('상세 다시 시도'),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(vm.detail?.status ?? ''),
                          Text(
                            '${vm.detail?.data['inquiry_type'] ?? ''} · ${vm.detail?.data['created_at'] ?? ''}',
                          ),
                          Text(
                            vm.detail?.data['inquiry_content'] as String? ?? '',
                          ),
                          const Divider(),
                          if ((vm.detail?.data['responses'] as List? ?? [])
                              .isEmpty)
                            const Text('등록된 답변이 없습니다.'),
                          for (final response
                              in vm.detail?.data['responses'] as List? ??
                                  []) ...[
                            Text(response['response_content'] as String),
                            Text('${response['responded_at']}'),
                          ],
                        ],
                      ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
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
  Widget build(BuildContext context) => GetBuilder<InquiryHistoryVm>(
    init: _vm,
    global: false,
    autoRemove: false,
    builder: (vm) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('내 문의 목록'),
        if (vm.loading)
          const Center(child: CircularProgressIndicator())
        else if (vm.error != null) ...[
          Text(vm.error!),
          TextButton(
            onPressed: () => vm.fetch(targetPage: vm.page),
            child: const Text('다시 시도'),
          ),
        ] else ...[
          if (vm.inquiries.isEmpty) const Text('문의 내역이 없습니다.'),
          for (final entry in vm.inquiries)
            ListTile(
              title: Text(entry.title),
              subtitle: Text('${entry.status} · ${entry.data['created_at']}'),
              onTap: () => _open(entry.id),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
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
  );
}
