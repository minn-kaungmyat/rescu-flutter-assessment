import 'dart:async';
import 'package:get/get.dart';

import '../util/log_service.dart';
import 'fake_api_service.dart';

class AnalyticsEvent {
  final String name;
  final Map<String, dynamic> properties;
  final DateTime at;

  AnalyticsEvent(this.name, this.properties) : at = DateTime.now();

  Map<String, dynamic> toJson() => {
        'name': name,
        'properties': properties,
        'at': at.toIso8601String(),
      };
}

/// In-memory analytics sink. Events are visible on the debug screen
/// (overflow menu on Home -> "Analytics debug") and in the console.
///
/// The "Impression tracking" feature task builds on top of this service.
class AnalyticsService extends GetxService {
  final events = <AnalyticsEvent>[].obs;

  final Set<int> _seenDealIds = {};
  final List<AnalyticsEvent> _queue = [];
  Timer? _flushTimer;

  void logEvent(String name, [Map<String, dynamic> properties = const {}]) {
    final event = AnalyticsEvent(name, properties);
    events.add(event);
    LogService.log('analytics: $name $properties');
  }

  bool hasSeenDeal(int dealId) => _seenDealIds.contains(dealId);

  void logDealImpression(int dealId, String source, int position) {
    if (_seenDealIds.contains(dealId)) return;
    _seenDealIds.add(dealId);

    final properties = {
      'deal_id': dealId,
      'source': source,
      'position': position,
    };

    final event = AnalyticsEvent('deal_impression', properties);
    events.add(event); // Still add to global list for debug screen
    LogService.log('analytics: deal_impression $properties');

    // add to the queue for periodic batch flesh
    _queue.add(event);

    // flush queue if it reaches 10 events
    if (_queue.length >= 10) {
      _flush();
    } else if (_queue.length == 1) {
      // flush queue after 15 seconds if it's not full
      _flushTimer = Timer(const Duration(seconds: 15), _flush);
    }
  }

  Future<void> _flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;

    if (_queue.isEmpty) return;

    // batch the queue to send to the server
    final batch = _queue.map((e) => e.toJson()).toList();
    // immediately clear queue after adding to batch
    _queue.clear();

    try {
      await Get.find<FakeApiService>().sendAnalyticsBatch(batch);
    } catch (e) {
      LogService.log('analytics: failed to send batch');
    }
  }

  @override
  void onClose() {
    _flushTimer?.cancel();
    super.onClose();
  }
}
