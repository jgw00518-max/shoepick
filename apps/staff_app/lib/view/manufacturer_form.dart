import 'package:flutter/material.dart';

import '../model/manufacturer.dart';
import '../vm/manufacturer_vm.dart';

class ManufacturerForm extends StatefulWidget {
  const ManufacturerForm({
    super.key,
    required this.vm,
    this.manufacturer,
  });

  final ManufacturerVm vm;
  final Manufacturer? manufacturer;

  @override
  State<ManufacturerForm> createState() => _ManufacturerFormState();
}

class _ManufacturerFormState extends State<ManufacturerForm> {
  final formKey = GlobalKey<FormState>();

  late final TextEditingController nameController;
  late final TextEditingController contactController;
  late final TextEditingController phoneController;
  late final TextEditingController emailController;

  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();

    final manufacturer = widget.manufacturer;

    nameController = TextEditingController(
      text: manufacturer?.name ?? '',
    );
    contactController = TextEditingController(
      text: manufacturer?.contactName ?? '',
    );
    phoneController = TextEditingController(
      text: manufacturer?.phone ?? '',
    );
    emailController = TextEditingController(
      text: manufacturer?.email ?? '',
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    contactController.dispose();
    phoneController.dispose();
    emailController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !formKey.currentState!.validate()) return;

    setState(() {
      saving = true;
      error = null;
    });

    try {
      await widget.vm.saveManufacturer(
        id: widget.manufacturer?.id,
        name: nameController.text,
        contactName: contactController.text,
        phone: phoneController.text,
        email: emailController.text,
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } on StateError catch (exception) {
      if (!mounted) return;

      setState(() => error = exception.message.toString());
    } catch (_) {
      if (!mounted) return;

      setState(() {
        error = '저장 응답을 확인하지 못했습니다. '
            '창을 닫고 목록을 새로고침하여 반영 여부를 먼저 확인해주세요.';
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget input({
    required TextEditingController controller,
    required String label,
    required int maxLength,
    bool requiredField = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: !saving,
        maxLength: maxLength,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (requiredField && (value ?? '').trim().isEmpty) {
            return '제조사명을 입력해주세요.';
          }
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(
          widget.manufacturer == null ? '제조사 등록' : '제조사 수정',
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  input(
                    controller: nameController,
                    label: '제조사명 · 필수',
                    maxLength: 100,
                    requiredField: true,
                  ),
                  input(
                    controller: contactController,
                    label: '담당자',
                    maxLength: 100,
                  ),
                  input(
                    controller: phoneController,
                    label: '전화번호',
                    maxLength: 20,
                    keyboardType: TextInputType.phone,
                  ),
                  input(
                    controller: emailController,
                    label: '이메일',
                    maxLength: 255,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving
                ? null
                : () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? '저장 중...' : '저장'),
          ),
        ],
      ),
    );
  }
}