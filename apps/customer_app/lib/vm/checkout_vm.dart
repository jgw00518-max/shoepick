import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:get/get.dart';

import '../domain/models.dart';
import 'auth_api.dart';

class CheckoutVm extends GetxController {
  CheckoutVm() {
    // 재시도할 때 같은 키를 사용하여 중복 저장을 방지한다.
    final random = Random.secure();
    final key = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();

    orderRequestKey = 'order-$key';
    transactionKey = 'payment-$key';
  }

  final AuthApi api = AuthApi();

  late final String orderRequestKey;
  late final String transactionKey;

  bool submitting = false;
  bool paid = false;
  String? error;

  int? orderId;
  String? orderNumber;
  int? paidTotal;

  int? _branchId;
  String? _customerUid;
  List<Map<String, int>>? _items;

  Future<bool> pay({
    required int branchId,
    required List<CartItem> lines,
    required int expectedTotal,
  }) async {
    if (submitting) return false;
    if (paid) return true;

    submitting = true;
    error = null;
    update();

    try {
      final user = api.auth.currentUser;

      if (user == null) {
        throw StateError('로그인 후 주문해주세요.');
      }

      if (_customerUid != null && _customerUid != user.uid) {
        throw StateError('주문을 시작한 계정으로 다시 로그인해주세요.');
      }

      if (_items == null) {
        if (branchId <= 0 || lines.isEmpty) {
          throw StateError('주문 상품과 수령 대리점을 확인해주세요.');
        }

        final quantities = <int, int>{};

        for (final item in lines) {
          final variantId = item.productVariantId;

          if (variantId == null || variantId <= 0 || item.quantity <= 0) {
            throw StateError(
              '상품 옵션 정보가 없습니다. 상품 상세에서 옵션을 다시 선택해주세요.',
            );
          }

          quantities[variantId] =
              (quantities[variantId] ?? 0) + item.quantity;
        }

        _items = quantities.entries
            .map(
              (entry) => {
                'product_variant_id': entry.key,
                'quantity': entry.value,
              },
            )
            .toList();

        _branchId = branchId;
        _customerUid = user.uid;
      }

      // 응답을 받지 못해도 같은 요청 키로 다시 조회·생성한다.
      if (orderId == null) {
        final order = await _post(
          '/api/v1/orders',
          {
            'branch_id': _branchId,
            'order_request_key': orderRequestKey,
            'items': _items,
          },
        );

        orderId = (order['order_id'] as num).toInt();
        orderNumber = order['order_number'] as String;
        paidTotal = (order['paid_total'] as num).toInt();

        final status = order['order_status'];

        if (status != 'PENDING_PAYMENT' && status != 'PAID') {
          throw StateError(
            '결제할 수 없는 주문입니다. 주문 내역을 확인해주세요.',
          );
        }
      }

      // 결제 금액은 서버에서 계산한 값과 일치해야 한다.
      if (paidTotal != expectedTotal) {
        throw StateError(
          '상품 금액이 변경되었습니다. 결제를 진행하지 않았습니다. '
          '상품을 다시 조회하고 주문해주세요.',
        );
      }

      final payment = await _post(
        '/api/v1/orders/$orderId/mock-payment',
        {'transaction_key': transactionKey},
      );

      if (payment['order_status'] != 'PAID' ||
          payment['payment_status'] != 'PAID') {
        throw StateError('결제 완료 상태를 확인하지 못했습니다.');
      }

      paidTotal = (payment['paid_total'] as num).toInt();
      paid = true;
      return true;
    } on StateError catch (exception) {
      error = exception.message.toString();
      return false;
    } catch (_) {
      error =
          '서버 응답을 확인하지 못했습니다. 같은 화면에서 다시 눌러주세요. '
          '같은 요청 키로 처리 결과를 확인합니다.';
      return false;
    } finally {
      submitting = false;
      if (!isClosed) update();
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final user = api.auth.currentUser;

    if (user == null) {
      throw StateError('로그인이 필요합니다.');
    }

    if (api.baseUrl.isEmpty) {
      throw StateError('API_BASE_URL을 확인해주세요.');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final token = await user.getIdToken(attempt == 1);

        if (token == null || token.isEmpty) {
          throw StateError('로그인 정보를 확인하지 못했습니다.');
        }

        final request = await client.postUrl(
          Uri.parse(
            '${api.baseUrl.replaceFirst(RegExp(r"/$"), "")}$path',
          ),
        ).timeout(const Duration(seconds: 15));

        request.headers.contentType = ContentType.json;
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $token',
        );
        request.write(jsonEncode(data));

        final response = await request.close().timeout(
          const Duration(seconds: 15),
        );

        final responseText = await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 401 && attempt == 0) {
          continue;
        }

        if (response.statusCode == 401) {
          throw StateError('로그인이 만료되었습니다. 다시 로그인해주세요.');
        }

        Map<String, dynamic> body = {};

        try {
          final decoded = jsonDecode(responseText);
          if (decoded is Map<String, dynamic>) {
            body = decoded;
          }
        } catch (_) {
          // JSON이 아닌 오류 응답은 아래 공통 문구로 처리한다.
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          final detail = body['error'] ?? body['detail'];
          final message = detail is Map ? detail['message'] : null;

          throw StateError(
            message is String
                ? message
                : '요청에 실패했습니다. HTTP ${response.statusCode}',
          );
        }

        final result = body['data'];

        if (result is! Map<String, dynamic>) {
          throw StateError(
            '서버 응답 형식을 확인하지 못했습니다. 같은 화면에서 다시 시도해주세요.',
          );
        }

        return result;
      }

      throw StateError('로그인 정보를 확인해주세요.');
    } finally {
      client.close(force: true);
    }
  }
}