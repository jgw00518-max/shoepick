import 'package:get/get.dart';

import '../presentation/store_shell.dart';

/// 매장 화면의 이동 기록과 현재 화면을 GetX 상태로 관리합니다.
class StoreNavigationController extends GetxController {
  StorePage page = StorePage.home;
  final List<StorePage> _history = [];

  /// 현재 화면을 기록하고 다음 화면으로 이동합니다.
  void go(StorePage next) {
    if (page == next) return;
    _history.add(page);
    page = next;
    update();
  }

  /// 이전 화면으로 돌아가며 기록이 없으면 홈을 표시합니다.
  void back() {
    page = _history.isEmpty ? StorePage.home : _history.removeLast();
    update();
  }

  /// 이동 기록을 비우고 지정한 화면을 시작 화면으로 만듭니다.
  void resetTo(StorePage next) {
    _history.clear();
    page = next;
    update();
  }
}
