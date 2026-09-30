import 'dart:convert';

import 'package:flutter/material.dart';
import '../localization.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/store_controller.dart';
import '../../domain/models.dart';

/// 구매 항목의 리뷰, 착화감, 사진을 목업 저장소에 기록합니다.
class ReviewSheet extends StatefulWidget {
  const ReviewSheet({
    super.key,
    required this.order,
    required this.item,
    required this.store,
    required this.onSaved,
    this.existing,
  });
  final StoreOrder order;
  final CartItem item;
  final StoreController store;
  final VoidCallback onSaved;
  final ProductReview? existing;
  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  final formKey = GlobalKey<FormState>();
  final content = TextEditingController();
  final picker = ImagePicker();
  int rating = 5;
  String fitSize = '정사이즈';
  String fitWidth = '적당함';
  String fitComfort = '편함';
  final List<String> photos = [];
  String? photoError;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      content.text = existing.content;
      rating = existing.rating;
      fitSize = existing.fitSize;
      fitWidth = existing.fitWidth;
      fitComfort = existing.fitComfort;
      photos.addAll(existing.photos);
    }
    _recoverLostPhotos();
  }

  Future<void> _recoverLostPhotos() async {
    try {
      final response = await picker.retrieveLostData();
      if (response.files != null) await _addFiles(response.files!);
    } catch (_) {
      /* 데스크톱 등 복구를 지원하지 않는 환경입니다. */
    }
  }

  Future<void> _pickPhotos() async {
    try {
      await _addFiles(await picker.pickMultiImage());
    } catch (_) {
      if (mounted) setState(() => photoError = '사진을 선택하지 못했습니다.');
    }
  }

  Future<void> _addFiles(List<XFile> files) async {
    if (files.isEmpty) return;
    if (photos.length + files.length > 3) {
      setState(() => photoError = '사진은 최대 3장까지 추가할 수 있어요.');
      return;
    }
    for (final file in files) {
      if (await file.length() > 5 * 1024 * 1024) {
        setState(() => photoError = '사진 한 장의 크기는 5MB 이하로 선택해주세요.');
        return;
      }
    }
    final encoded = await Future.wait(
      files.map((file) async => base64Encode(await file.readAsBytes())),
    );
    if (mounted) {
      setState(() {
        photos.addAll(encoded);
        photoError = null;
      });
    }
  }

  @override
  void dispose() {
    content.dispose();
    super.dispose();
  }

  Widget _fitChoice(
    String title,
    List<String> options,
    String selected,
    ValueChanged<String> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LText(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      Wrap(
        spacing: 6,
        children: [
          for (final option in options)
            ChoiceChip(
              label: LText(option),
              selected: selected == option,
              onSelected: (_) => setState(() => onChanged(option)),
            ),
        ],
      ),
    ],
  );

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    final review = ProductReview(
      orderNumber: widget.order.number,
      itemKey: widget.item.key,
      rating: rating,
      content: content.text.trim(),
      fitSize: fitSize,
      fitWidth: fitWidth,
      fitComfort: fitComfort,
      photos: List.of(photos),
    );
    try {
      if (widget.existing == null) {
        await widget.store.addReview(review);
      } else {
        await widget.store.updateReview(review);
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          photoError = '리뷰를 저장하지 못했습니다.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      16,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Form(
        key: formKey,
        child: ListView(
          children: [
            LText(
              widget.existing == null ? '리뷰 작성' : '리뷰 수정',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            LText(
              '${widget.item.product.name} · ${widget.item.color} · ${widget.item.size}',
            ),
            Row(
              children: [
                for (var value = 1; value <= 5; value++)
                  IconButton(
                    tooltip: '$value점',
                    onPressed: () => setState(() => rating = value),
                    icon: Icon(
                      value <= rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                  ),
              ],
            ),
            const SectionLabel('실착 후기'),
            _fitChoice(
              '사이즈',
              ['작아요', '정사이즈', '커요'],
              fitSize,
              (value) => fitSize = value,
            ),
            _fitChoice(
              '발볼',
              ['좁아요', '적당함', '넓어요'],
              fitWidth,
              (value) => fitWidth = value,
            ),
            _fitChoice(
              '착화감',
              ['보통', '편함', '불편함'],
              fitComfort,
              (value) => fitComfort = value,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: content,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '리뷰 내용',
                border: OutlineInputBorder(),
                hintText: '착화감, 사이즈, 색상에 대한 경험을 알려주세요.',
              ),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? '리뷰 내용을 입력해주세요.' : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _pickPhotos,
              child: LText('사진 선택 ${photos.length}/3 · 장당 5MB 이하'),
            ),
            if (photos.isNotEmpty)
              SizedBox(
                height: 86,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var index = 0; index < photos.length; index++)
                      Stack(
                        children: [
                          Image.memory(
                            base64Decode(photos[index]),
                            width: 82,
                            height: 82,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            right: 0,
                            child: IconButton(
                              onPressed: () =>
                                  setState(() => photos.removeAt(index)),
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            if (photoError != null)
              LText(photoError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving ? null : _save,
              child: LText(
                saving
                    ? '저장 중...'
                    : widget.existing == null
                    ? '리뷰 등록'
                    : '리뷰 수정',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: LText(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );
}
