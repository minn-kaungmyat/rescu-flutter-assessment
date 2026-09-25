import 'dart:async';
import 'package:flutter/foundation.dart';

class CentralTicker {
  static final CentralTicker instance = CentralTicker._();
  CentralTicker._();

  final ValueNotifier<DateTime> nowNotifier = ValueNotifier(DateTime.now());
  Timer? _timer;
  int _listenerCount = 0;

  void addListener(VoidCallback listener) {
    if (_listenerCount == 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        nowNotifier.value = DateTime.now();
      });
    }
    _listenerCount++;
    nowNotifier.addListener(listener);
  }

  void removeListener(VoidCallback listener) {
    nowNotifier.removeListener(listener);
    _listenerCount--;
    if (_listenerCount <= 0) {
      _timer?.cancel();
      _timer = null;
      _listenerCount = 0;
    }
  }
}
