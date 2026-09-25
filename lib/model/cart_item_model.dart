import 'deal_model.dart';
import 'reservation_model.dart';

/// Represents the lifecycle of a cart item's server-side reservation.
enum ReservationStatus {
  /// no reservation attempt yet or just added optimistically.
  pending,

  /// server confirmed the hold, stock is reserved for 5 minutes.
  reserved,

  /// reservation API call failed (e.g. 409 stock contention).
  /// item will be rolled back out of the cart.
  failed,

  /// 5-minute hold has expired. The user must re-reserve or remove.
  expired,
}

class CartItemModel {
  final DealModel deal;
  int quantity;

  /// Stock hold for this line item.
  ReservationModel? reservation;

  /// Tracks the current state of the reservation lifecycle.
  ReservationStatus reservationStatus;

  CartItemModel({
    required this.deal,
    this.quantity = 1,
    this.reservation,
    this.reservationStatus = ReservationStatus.pending,
  });

  num get lineTotal => deal.price * quantity;

  /// Whether the reservation has been confirmed and is still valid.
  bool get isReserved =>
      reservationStatus == ReservationStatus.reserved &&
      reservation != null &&
      !reservation!.isExpired;

  /// Whether the hold has expired (either server said so, or local clock).
  bool get isExpired =>
      reservationStatus == ReservationStatus.expired ||
      (reservation != null && reservation!.isExpired);
}
