import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../util/log_service.dart';
import 'tick_service.dart';

/// App-wide cart. Lives for the whole session.
///
/// NOTE: the starter cart is purely local — it does not reserve stock on the
/// backend. See the "Reservations" feature task in PROBLEM.md.
class CartService extends GetxService {
  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  Worker? _tickListener;

  @override
  void onInit() {
    super.onInit();
    final tick = Get.find<TickService>();
    _tickListener = ever(tick.now, (_) => _evictExpired());
  }

  void _evictExpired() {
    final expired = items
        .where((i) =>
            i.deal.isFlashSale &&
            !i.deal.flashSaleEndsAt!.isAfter(DateTime.now()))
        .toList();

    for (final item in expired) {
      items.removeWhere((i) => i.deal.id == item.deal.id);
      LogService.log('cart: auto-removed expired deal ${item.deal.id}');
      Get.snackbar(
        'Flash sale expired',
        '${item.deal.name} was removed from your bag',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade50,
        colorText: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      );
    }
    if (expired.isNotEmpty) _recount();
  }

  bool add(DealModel deal) {
    // Block adding expired flash deals.
    if (deal.isFlashSale && !deal.flashSaleEndsAt!.isAfter(DateTime.now())) {
      Get.snackbar(
        'Flash sale expired',
        '${deal.name} can no longer be added',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return false;
    }

    final existing = items.firstWhereOrNull((i) => i.deal.id == deal.id);
    if (existing != null) {
      if (existing.quantity >= deal.quantityLeft) {
        LogService.log('cart: cannot add more of deal ${deal.id}');
        return false;
      }
      existing.quantity++;
      items.refresh();
    } else {
      items.add(CartItemModel(deal: deal));
    }
    _recount();
    return true;
  }

  void decrement(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;
    existing.quantity--;
    if (existing.quantity <= 0) {
      items.removeWhere((i) => i.deal.id == dealId);
    } else {
      items.refresh();
    }
    _recount();
  }

  void remove(int dealId) {
    items.removeWhere((i) => i.deal.id == dealId);
    _recount();
  }

  void clear() {
    items.clear();
    _recount();
  }

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

  void _recount() {
    itemCount.value = items.fold(0, (sum, i) => sum + i.quantity);
  }

  @override
  void onClose() {
    _tickListener?.dispose();
    super.onClose();
  }
}
