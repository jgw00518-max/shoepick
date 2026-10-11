import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';
import '../domain/repositories.dart';

class ApiProductRepository implements ProductRepository {
  final String baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  @override
  Future<List<Product>> getProducts() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final url = Uri.parse(
        '${baseUrl.replaceFirst(RegExp(r"/$"), "")}/api/v1/products',
      );

      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != 200) {
        throw HttpException('상품 조회 실패: ${response.statusCode}');
      }

      final text = await utf8.decoder.bind(response).join();
      final body = jsonDecode(text) as Map<String, dynamic>;
      final rows = body['data'] as List<dynamic>;

      return rows.map((row) {
        final data = row as Map<String, dynamic>;

        return Product(
          id: (data['product_id'] as num).toInt(),
          name: data['product_name'] as String,
          description: data['product_description'] as String? ?? '',
          price: (data['price'] as num).toInt(),
          imageUrl: data['image_url'] as String? ?? '',

          // DB에서 상품에 연결된 카테고리 이름을 사용한다.
          category: data['category_name'] as String? ?? '',
          color: '',
          gender: '',
          middleCategory: '',
          subcategory: '',
          reviewCount: 0,
          salesCount: 0,
        );
      }).toList();
    } finally {
      client.close(force: true);
    }
  }
}