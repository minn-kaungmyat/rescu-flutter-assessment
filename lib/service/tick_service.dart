import 'dart:async';

import 'package:get/get.dart';

/// A single global clock that ticks once per second.
///
/// Any widget that needs live time (flash-sale countdowns, pickup timers, etc.)
/// can listen to [now] via an `Obx`. Because there is only one timer regardless
/// of how many widgets are on screen.
class TickService extends GetxService {
  final now = DateTime.now().obs;
  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      now.value = DateTime.now();
    });
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
