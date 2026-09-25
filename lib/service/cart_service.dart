import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../repository/order_repo.dart';
import '../service/api_exception.dart';
import '../util/log_service.dart';
import 'tick_service.dart';

/// App-wide cart. Lives for the whole session.
///
/// F-3: Adding an item now reserves stock on the backend. The UI responds
/// optimistically (instant feedback), then reconciles when the server replies.
class CartService extends GetxService {
  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  Worker? _tickListener;

  @override
  void onInit() {
    super.onInit();
    final tick = Get.find<TickService>();
    _tickListener = ever(tick.now, (_) {
      _evictExpiredFlashDeals();
      _checkReservationExpiry();
    });
  }

  // ---------------------------------------------------------------------------
  // Flash-sale expiry (from F-1)
  // ---------------------------------------------------------------------------

  void _evictExpiredFlashDeals() {
    final expired = items
        .where((i) =>
            i.deal.isFlashSale &&
            !i.deal.flashSaleEndsAt!.isAfter(DateTime.now()))
        .toList();

    for (final item in expired) {
      // If the flash sale violently evicts this item from the local bag, we MUST
      // tell the backend to release the 5-minute stock hold so we don't leak server inventory
      if (item.reservation != null) {
        _releaseQuietly(item.reservation!.id);
      }
      items.removeWhere((i) => i.deal.id == item.deal.id);
      LogService.log('cart: auto-removed expired flash deal ${item.deal.id}');
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

  // ---------------------------------------------------------------------------
  // Reservation expiry detection (F-3)
  // ---------------------------------------------------------------------------

  /// Called every tick. Transitions reserved items whose hold has expired
  /// to the `expired` state so the UI can show a warning.
  void _checkReservationExpiry() {
    bool changed = false;
    for (final item in items) {
      if (item.reservationStatus == ReservationStatus.reserved &&
          item.reservation != null &&
          item.reservation!.isExpired) {
        item.reservationStatus = ReservationStatus.expired;
        item.reservation = null;
        changed = true;
        LogService.log('cart: reservation expired for deal ${item.deal.id}');
      }
    }
    if (changed) items.refresh();
  }

  // ---------------------------------------------------------------------------
  // Add to cart — optimistic with background reservation
  // ---------------------------------------------------------------------------

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
      existing.reservationStatus = ReservationStatus.pending;
      items.refresh();
      // re-reserve with the new quantity
      _reserveInBackground(deal.id, existing.quantity);
    } else {
      items.add(CartItemModel(deal: deal));
      _reserveInBackground(deal.id, 1);
    }
    _recount();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Re-reserve (for expired items the user wants to keep)
  // ---------------------------------------------------------------------------

  void reReserve(int dealId) {
    final item = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (item == null) return;
    item.reservationStatus = ReservationStatus.pending;
    items.refresh();
    _reserveInBackground(dealId, item.quantity);
  }

  // ---------------------------------------------------------------------------
  // Background reservation call
  // ---------------------------------------------------------------------------

  Future<void> _reserveInBackground(int dealId, int quantity) async {
    try {
      final repo = Get.find<OrderRepo>();

      // Release old reservation first if we had one (e.g. quantity change)
      final existingItem = items.firstWhereOrNull((i) => i.deal.id == dealId);
      final oldReservationId = existingItem?.reservation?.id;

      final reservation = await repo.reserve(dealId, quantity: quantity);

      // Release the old reservation now that we have a new one
      if (oldReservationId != null) {
        _releaseQuietly(oldReservationId);
      }

      // Check if the item is still in the cart (user might have removed it
      // while the API call was in-flight - race condition guard).
      final current = items.firstWhereOrNull((i) => i.deal.id == dealId);
      if (current == null) {
        // User removed it while we were reserving. Release the new hold.
        _releaseQuietly(reservation.id);
        LogService.log(
            'cart: deal $dealId removed during reservation, releasing');
        return;
      }

      current.reservation = reservation;
      current.reservationStatus = ReservationStatus.reserved;
      items.refresh();
      LogService.log('cart: reserved deal $dealId (${reservation.id}, '
          'expires ${reservation.expiresAt.toLocal()})');
    } on ApiException catch (e) {
      LogService.log(
          'cart: reservation failed for deal $dealId - ${e.message}');
      _rollback(dealId, e.message);
    } catch (e) {
      LogService.error(
          'cart: unexpected reservation error for deal $dealId', e);
      _rollback(dealId, 'Something went wrong. Please try again.');
    }
  }

  /// Removes the item from the cart (if new) or reverts its quantity (if adjusted) and shows an error message.
  void _rollback(int dealId, String reason) {
    final item = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (item == null) return; // if already removed from cart do nothing

    if (item.reservation != null && !item.reservation!.isExpired) {
      // We already had a valid reservation! This was just a failed quantity update.
      // Rollback the UI back to the old valid quantity instead of deleting the item.
      item.quantity = item.reservation!.quantity;
      item.reservationStatus = ReservationStatus.reserved;
      items.refresh();
      _recount();
      Get.snackbar(
        'Could not update quantity',
        '${item.deal.name} - $reason',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.shade50,
        colorText: Colors.orange.shade800,
        duration: const Duration(seconds: 3),
      );
    } else {
      // this was a completely new item, and we failed to get a reservation.
      // remove it completely from the cart.
      items.removeWhere((i) => i.deal.id == dealId);
      _recount();
      Get.snackbar(
        'Could not reserve',
        '${item.deal.name} - $reason',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade50,
        colorText: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      );
    }
  }

  /// Fire-and-forget release.
  void _releaseQuietly(String reservationId) {
    try {
      Get.find<OrderRepo>().releaseReservation(reservationId);
      LogService.log('cart: released reservation $reservationId');
    } catch (e) {
      LogService.error('cart: failed to release $reservationId', e);
    }
  }

  // ---------------------------------------------------------------------------
  // Decrement / Remove / Clear — now release reservations
  // ---------------------------------------------------------------------------

  void decrement(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;

    if (existing.quantity <= 1) {
      // Removing last unit - release full reservation
      remove(dealId);
      return;
    }

    existing.quantity--;
    existing.reservationStatus = ReservationStatus.pending;
    items.refresh();
    _recount();

    // Re-reserve with the reduced quantity
    _reserveInBackground(dealId, existing.quantity);
  }

  void remove(int dealId) {
    final item = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (item?.reservation != null) {
      _releaseQuietly(item!.reservation!.id);
    }
    items.removeWhere((i) => i.deal.id == dealId);
    _recount();
  }

  void clear() {
    // Release all active reservations
    for (final item in items) {
      if (item.reservation != null) {
        _releaseQuietly(item.reservation!.id);
      }
    }
    items.clear();
    _recount();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Whether any item has an expired reservation (blocks checkout).
  bool get hasExpiredItems =>
      items.any((i) => i.reservationStatus == ReservationStatus.expired);

  /// Whether any item is still waiting for its reservation to be confirmed.
  bool get hasPendingItems =>
      items.any((i) => i.reservationStatus == ReservationStatus.pending);

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
