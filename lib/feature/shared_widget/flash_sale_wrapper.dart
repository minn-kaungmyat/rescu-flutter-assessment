import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/tick_service.dart';

/// Wraps a widget (like a DealCard) and provides an `isExpired` boolean that
/// only flips exactly once when the flash sale ends.
///
/// Keeps per-second clock updates out of the child card.
/// The wrapper only triggers its own state transition when the sale expires.
class FlashSaleWrapper extends StatefulWidget {
  final DateTime endsAt;
  final Widget Function(BuildContext context, bool isExpired) builder;

  const FlashSaleWrapper({
    super.key,
    required this.endsAt,
    required this.builder,
  });

  @override
  State<FlashSaleWrapper> createState() => _FlashSaleWrapperState();
}

class _FlashSaleWrapperState extends State<FlashSaleWrapper> {
  bool _isExpired = false;
  Worker? _worker;

  @override
  void initState() {
    super.initState();

    final tick = Get.find<TickService>();

    _checkExpired(tick.now.value);

    _worker = ever(tick.now, (now) {
      _checkExpired(now);
    });
  }

  void _checkExpired(DateTime now) {
    if (!_isExpired && !widget.endsAt.isAfter(now)) {
      _isExpired = true;

      _worker?.dispose();
      _worker = null;

      setState(() {});
    }
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _isExpired);
  }
}
