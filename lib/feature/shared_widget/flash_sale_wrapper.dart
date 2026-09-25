import 'package:flutter/material.dart';

import '../../util/central_ticker.dart';

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

  @override
  void initState() {
    super.initState();
    _checkExpired();
    CentralTicker.instance.addListener(_checkExpired);
  }

  void _checkExpired() {
    final now = CentralTicker.instance.nowNotifier.value;
    if (!_isExpired && !widget.endsAt.isAfter(now)) {
      _isExpired = true;
      CentralTicker.instance.removeListener(_checkExpired);
      setState(() {});
    }
  }

  @override
  void dispose() {
    CentralTicker.instance.removeListener(_checkExpired);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _isExpired);
  }
}
