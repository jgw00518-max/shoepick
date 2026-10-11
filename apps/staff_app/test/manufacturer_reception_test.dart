import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoepick_staff_app/vm/auth_api.dart';
import 'manufacturer_order_list_test.dart';

class ReceptionApi extends OrderApi {
  Map<String, dynamic>? posted;
  bool failSave = false;
  bool completed = false;
  Map<String, dynamic>? receipt;
  @override
  Future<Map<String, dynamic>> getResponse(String path) async {
    final data = await super.getResponse(path);
    final rows = data['data'] is List ? data['data'] as List : [data['data']];
    for (final row in rows) {
      row['can_record_reception'] = !completed;
      row['reception_status'] = completed ? posted!['decision'] : 'PENDING';
      row['goods_receipt'] = receipt;
    }
    return data;
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    expect(path, '/api/v1/manufacturer-orders/10/reception');
    posted = body;
    if (failSave) throw const AuthApiException('접수 기록 저장 실패');
    completed = true;
    if (body['decision'] == 'ACCEPTED') {
      receipt = {
        'total_received_quantity': 100,
        'received_at': '2026-10-11T12:00:00',
        'items': [
          {
            'product_variant_id': 12,
            'received_quantity': 100,
            'on_hand_after': 120,
          },
        ],
      };
    }
    return {'goods_receipt': receipt};
  }
}

void main() {
  for (final accept in [true, false]) {
    testWidgets('직원이 제조사 ${accept ? '접수 확인' : '거절'}을 기록하고 목록을 갱신한다', (
      tester,
    ) async {
      final api = ReceptionApi();
      await tester.pumpWidget(orderScreen(api));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('manufacturer-order-detail-10')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, accept ? '접수 확인 및 전체 입고' : '접수 거절'),
      );
      await tester.pumpAndSettle();
      if (accept) {
        expect(find.textContaining('100켤레 전체가 본사에 입고'), findsOneWidget);
      }
      if (!accept) {
        await tester.tap(find.text('기록 저장'));
        await tester.pumpAndSettle();
        expect(find.text('접수 거절 사유를 입력해주세요.'), findsOneWidget);
        expect(api.posted, isNull);
      }
      await tester.enterText(find.byType(TextField).last, '제조사 답변');
      api.failSave = true;
      await tester.tap(find.text(accept ? '전체 입고 확정' : '기록 저장'));
      await tester.pumpAndSettle();
      expect(find.text('접수 기록 저장 실패'), findsOneWidget);
      final requestId = api.posted!['request_id'];
      api.failSave = false;
      await tester.tap(find.text(accept ? '전체 입고 확정' : '기록 저장'));
      await tester.pumpAndSettle();
      expect(api.posted!['decision'], accept ? 'ACCEPTED' : 'REJECTED');
      expect(api.posted!['request_id'], requestId);
      expect(
        find.text('제조사 접수: ${accept ? '접수 확인' : '접수 거절'}'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('manufacturer-order-detail-10')),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, '접수 확인 및 전체 입고'), findsNothing);
      expect(find.widgetWithText(FilledButton, '접수 거절'), findsNothing);
      if (accept) {
        expect(find.textContaining('입고 처리 후 본사 실물 재고 120켤레'), findsOneWidget);
      } else {
        expect(api.receipt, isNull);
      }
    });
  }
}
