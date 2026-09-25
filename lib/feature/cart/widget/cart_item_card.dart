import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app_config.dart';
import '../../../model/cart_item_model.dart';
import '../../../service/tick_service.dart';
import '../../shared_widget/the_network_image.dart';

/// A single cart line item card with reservation status display.
class CartItemCard extends StatelessWidget {
  final CartItemModel item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onReReserve;
  final VoidCallback onRemove;

  const CartItemCard({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onReReserve,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isExpired = item.isExpired;

    return Opacity(
      opacity: isExpired ? 0.6 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: Colors.white,
        elevation: 0.5,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TheNetworkImage(
                    url: item.deal.imageUrl,
                    width: 64,
                    height: 64,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.deal.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600)),
                        Text(item.deal.storeName,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade600)),
                        Text('฿${item.deal.price.toStringAsFixed(0)} each',
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppConfig.primaryGreen,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: isExpired ? null : onDecrement,
                      ),
                      Text('${item.quantity}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: isExpired ? null : onIncrement,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _ReservationStatusRow(
                item: item,
                onReReserve: onReReserve,
                onRemove: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the reservation countdown or expired state for a cart line.
class _ReservationStatusRow extends StatelessWidget {
  final CartItemModel item;
  final VoidCallback onReReserve;
  final VoidCallback onRemove;

  const _ReservationStatusRow({
    required this.item,
    required this.onReReserve,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    switch (item.reservationStatus) {
      case ReservationStatus.pending:
        return Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 8),
            Text('Reserving…',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500)),
          ],
        );

      case ReservationStatus.reserved:
        return _ReservationCountdown(item: item);

      case ReservationStatus.expired:
        return Row(
          children: [
            Icon(Icons.error_outline,
                size: 14, color: Colors.red.shade600),
            const SizedBox(width: 4),
            Text('Reservation expired',
                style: TextStyle(
                    fontSize: 12, color: Colors.red.shade600)),
            const Spacer(),
            SizedBox(
              height: 28,
              child: TextButton(
                onPressed: onReReserve,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Re-reserve', style: TextStyle(fontSize: 12)),
              ),
            ),
            SizedBox(
              height: 28,
              child: TextButton(
                onPressed: onRemove,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.red.shade600,
                ),
                child: const Text('Remove', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        );

      case ReservationStatus.failed:
        return Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 14, color: Colors.orange.shade700),
            const SizedBox(width: 4),
            Expanded(
              child: Text('Failed to reserve — removing…',
                  style: TextStyle(
                      fontSize: 12, color: Colors.orange.shade700)),
            ),
          ],
        );
    }
  }
}

/// Displays the live countdown for a confirmed reservation using TickService.
class _ReservationCountdown extends StatelessWidget {
  final CartItemModel item;

  const _ReservationCountdown({required this.item});

  @override
  Widget build(BuildContext context) {
    final tick = Get.find<TickService>();
    return Obx(() {
      // Force Obx to re-evaluate every tick
      final now = tick.now.value;
      final remaining = item.reservation!.expiresAt.difference(now.toUtc());
      if (remaining <= Duration.zero) {
        // Will be caught by _checkReservationExpiry on next tick
        return Row(
          children: [
            Icon(Icons.timer_off, size: 14, color: Colors.red.shade600),
            const SizedBox(width: 4),
            Text('Expiring…',
                style: TextStyle(
                    fontSize: 12, color: Colors.red.shade600)),
          ],
        );
      }
      final minutes = remaining.inMinutes;
      final seconds = remaining.inSeconds % 60;
      return Row(
        children: [
          Icon(Icons.timer_outlined,
              size: 14, color: AppConfig.primaryGreen),
          const SizedBox(width: 4),
          Text(
            'Reserved · ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: TextStyle(
                fontSize: 12,
                color: remaining.inMinutes < 1
                    ? Colors.orange.shade700
                    : AppConfig.primaryGreen,
                fontWeight: FontWeight.w500),
          ),
        ],
      );
    });
  }
}
