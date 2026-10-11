import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';

import '../model/product_option.dart';

class ProductOptionsVm extends GetxController {
  ProductOptionsVm({required this.productId});

  final int productId;

  List<ProductOption> options = [];
  bool loading = true;
  String? error;
  String selectedColor = '';

  List<String> get colors =>
      options.map((option) => option.colorName).toSet().toList();

  List<ProductOption> get colorOptions {
    final result = options
        .where((option) => option.colorName == selectedColor)
        .toList();

    result.sort((a, b) => a.sizeMm.compareTo(b.sizeMm));
    return result;
  }

  @override
  void onInit() {
    super.onInit();
    fetchOptions();
  }

  void selectColor(String value) {
    selectedColor = value;
    update();
  }

  Future<void> fetchOptions() async {
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

      final url = Uri.parse(
        '${baseUrl.replaceFirst(RegExp(r"/$"), "")}'
        '/api/v1/products/$productId/options',
      );

      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != 200) {
        throw HttpException('옵션 조회 실패');
      }

      final text = await utf8.decoder.bind(response).join();
      final body = jsonDecode(text) as Map<String, dynamic>;
      final rows = body['data'] as List<dynamic>;

      final loaded = rows
          .map(
            (row) => ProductOption.fromJson(
              row as Map<String, dynamic>,
            ),
          )
          .toList();

      if (isClosed) return;

      options = loaded;
      selectedColor = colors.isEmpty ? '' : colors.first;
    } catch (_) {
      if (isClosed) return;

      options = [];
      selectedColor = '';
      error = '옵션을 불러오지 못했습니다.';
    } finally {
      client.close(force: true);

      if (!isClosed) {
        loading = false;
        update();
      }
    }
  }
}