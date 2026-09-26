import 'dart:async';
import 'package:flutter/foundation.dart';

class CentralTicker extends ValueNotifier<DateTime> {
  static final CentralTicker instance = CentralTicker._();
  
  CentralTicker._() : super(DateTime.now());

  Timer? _timer;

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        value = DateTime.now();
      });
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }
}
