import 'dart:ui';
import 'package:flutter/material.dart';

import '../../util/central_ticker.dart';

/// Displays a live countdown for a flash sale.
///
/// The `Obx` is scoped to the countdown `Text`, so per-second updates do not
/// rebuild the parent card or the surrounding list.
class FlashCountdownText extends StatelessWidget {
  final DateTime endsAt;
  final TextStyle? style;
  final TextStyle? expiredStyle;

  const FlashCountdownText({
    super.key,
    required this.endsAt,
    this.style,
    this.expiredStyle,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<DateTime>(
        valueListenable: CentralTicker.instance,
        builder: (context, now, child) {
          final remaining = endsAt.difference(now);
          if (remaining <= Duration.zero) {
            return Text(
              'Expired',
              style: expiredStyle ??
                  TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
            );
          }
          return Text(
            _format(remaining),
            style: (style ??
                    TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                    ))
                .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          );
        },
      ),
    );
  }

  /// Formats a Duration as `mm:ss` or `hh:mm:ss` if above one hour.
  static String _format(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
