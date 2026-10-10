import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';

import '../model/pickup_branch.dart';

class PickupBranchVm extends GetxController {
  List<PickupBranch> branches = [];
  int? selectedBranchId;
  bool loading = true;
  String? error;

  PickupBranch? get selectedBranch {
    for (final branch in branches) {
      if (branch.id == selectedBranchId) {
        return branch;
      }
    }
    return null;
  }

  @override
  void onInit() {
    super.onInit();
    fetchBranches();
  }

  void selectBranch(int? id) {
    selectedBranchId = id;
    update();
  }

  Future<void> fetchBranches() async {
    loading = true;
    error = null;
    update();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      const baseUrl = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://10.0.2.2:8000',
      );

      final request = await client.getUrl(
        Uri.parse(
          '${baseUrl.replaceFirst(RegExp(r"/$"), "")}'
          '/api/v1/branches/pickup',
        ),
      );

      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != 200) {
        throw HttpException('대리점 조회 실패');
      }

      final text = await utf8.decoder.bind(response).join();
      final body = jsonDecode(text) as Map<String, dynamic>;
      final rows = body['data'] as List<dynamic>;

      final loaded = rows
          .map(
            (row) => PickupBranch.fromJson(
              row as Map<String, dynamic>,
            ),
          )
          .toList();

      if (isClosed) return;

      branches = loaded;

      if (selectedBranch == null) {
        selectedBranchId = null;
      }
    } catch (_) {
      if (isClosed) return;

      branches = [];
      selectedBranchId = null;
      error = '대리점을 불러오지 못했습니다.';
    } finally {
      client.close(force: true);

      if (!isClosed) {
        loading = false;
        update();
      }
    }
  }
}