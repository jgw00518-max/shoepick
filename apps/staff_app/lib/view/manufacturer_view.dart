import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../vm/manufacturer_vm.dart';

import '../model/manufacturer.dart';
import 'manufacturer_form.dart';

class ManufacturerView extends StatefulWidget {
  const ManufacturerView({super.key});

  @override
  State<ManufacturerView> createState() =>
      _ManufacturerViewState();
}

class _ManufacturerViewState extends State<ManufacturerView> {
  late final String tag;
  late final ManufacturerVm vm;

  @override
  void initState() {
    super.initState();

    tag = 'manufacturers-${identityHashCode(this)}';
    vm = Get.put(ManufacturerVm(), tag: tag);
  }

  @override
  void dispose() {
    Get.delete<ManufacturerVm>(tag: tag);
    super.dispose();
  }

  String display(String? value) {
    return value == null || value.trim().isEmpty
        ? '미등록'
        : value;
  }

    Future<void> openForm({Manufacturer? manufacturer}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ManufacturerForm(
        vm: vm,
        manufacturer: manufacturer,
      ),
    );

    if (!mounted || saved != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('제조사 정보를 저장했습니다.')),
    );

    await vm.fetchManufacturers();
  }


  @override
  Widget build(BuildContext context) {
    return GetBuilder<ManufacturerVm>(
      tag: tag,
      builder: (controller) {
        if (controller.loading) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (controller.error != null) {
          return Column(
            children: [
              Text(controller.error!),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: controller.fetchManufacturers,
                child: const Text('다시 시도'),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '등록된 제조사 ${controller.manufacturers.length}개',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: controller.fetchManufacturers,
                  icon: const Icon(Icons.refresh),
                  label: const Text('새로고침'),
                ),
                   OutlinedButton.icon(
                  onPressed: controller.fetchManufacturers,
                  icon: const Icon(Icons.refresh),
                  label: const Text('새로고침'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => openForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('등록'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (controller.manufacturers.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('등록된 제조사가 없습니다.'),
                ),
              ),
            for (final manufacturer in controller.manufacturers)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manufacturer.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('제조사 ID: ${manufacturer.id}'),
                      Text('담당자: ${display(manufacturer.contactName)}'),
                      Text('전화번호: ${display(manufacturer.phone)}'),
                      Text('이메일: ${display(manufacturer.email)}'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => openForm(
                          manufacturer: manufacturer,
                        ),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('수정'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}