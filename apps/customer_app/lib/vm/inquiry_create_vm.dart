import 'dart:math';
import 'package:get/get.dart';

/// 실패 시 요청 ID와 내용을 보존하여 같은 문의 재전송을 구분한다.
class InquiryCreateVm extends GetxController {
  InquiryCreateVm({required this.send});
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) send;
  bool saving = false;
  String? error;
  Map<String, dynamic>? _pending;
  Future<bool> submit(Map<String, dynamic> values) async {
    if (saving || isClosed) return false;
    if (_pending == null) {
      _pending = {
        ...values,
        'request_id':
            'inquiry-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      };
    } else {
      final previous = Map<String, dynamic>.of(_pending!)..remove('request_id');
      if (previous.toString() != values.toString()) {
        error = '이전 요청의 결과가 확인되지 않았습니다. 같은 내용으로 다시 시도해주세요.';
        update();
        return false;
      }
    }
    saving = true;
    error = null;
    update();
    try {
      final response = await send(Map.of(_pending!));
      if (isClosed) return false;
      if (response['data']?['inquiry_id'] is! int) {
        throw StateError('저장 결과를 확인하지 못했습니다.');
      }
      _pending = null;
      return true;
    } catch (e) {
      if (!isClosed) {
        error = e is StateError
            ? e.message.toString()
            : '저장 결과를 확인하지 못했습니다. 같은 내용으로 다시 시도해주세요.';
      }
      return false;
    } finally {
      if (!isClosed) {
        saving = false;
        update();
      }
    }
  }
}
