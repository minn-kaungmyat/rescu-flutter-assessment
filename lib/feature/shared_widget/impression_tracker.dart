import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../service/analytics_service.dart';

class ImpressionTracker extends StatefulWidget {
  final int dealId;
  final String source;
  final int position;
  final Widget child;

  const ImpressionTracker({
    super.key,
    required this.dealId,
    required this.source,
    required this.position,
    required this.child,
  });

  @override
  State<ImpressionTracker> createState() => _ImpressionTrackerState();
}

class _ImpressionTrackerState extends State<ImpressionTracker> {
  Timer? _impressionTimer;
  bool _hasLogged = false;

  @override
  void dispose() {
    _impressionTimer?.cancel();
    super.dispose();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    //if already logged, do nothing
    if (_hasLogged) return;

    if (info.visibleFraction >= 0.5) {
      if (_impressionTimer == null || !_impressionTimer!.isActive) {
        _impressionTimer = Timer(const Duration(seconds: 1), () {
          Get.find<AnalyticsService>().logDealImpression(
            widget.dealId,
            widget.source,
            widget.position,
          );
          _hasLogged = true;
          // Trigger a rebuild so the VisibilityDetector is detached immediately,
          // saving CPU cycles on future scroll events.
          if (mounted) setState(() {});
        });
      }
    } else {
      // If it drops below 50% before the timer fires, cancel the timer
      _impressionTimer?.cancel();
      _impressionTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // If we've already logged it globally in this session, just return the child directly
    // without the VisibilityDetector to save CPU cycles on scroll.
    final hasSeenGlobally =
        Get.find<AnalyticsService>().hasSeenDeal(widget.dealId);
    if (_hasLogged || hasSeenGlobally) {
      return widget.child;
    }

    return VisibilityDetector(
      key: ValueKey(
          'impression_${widget.dealId}_${widget.source}_${widget.position}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: widget.child,
    );
  }
}
