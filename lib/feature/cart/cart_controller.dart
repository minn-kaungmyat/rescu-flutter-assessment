import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../repository/order_repo.dart';
import '../../service/api_exception.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

class CartController extends GetxController {
  final CartService cartService;
  final OrderRepo orderRepo;

  CartController({required this.cartService, required this.orderRepo});

  final isCheckingOut = false.obs;

  Future<void> checkout() async {
    if (cartService.items.isEmpty || isCheckingOut.value) return;

    // Block checkout if any reservations are still pending
    if (cartService.hasPendingItems) {
      Get.snackbar(
        'Please wait',
        'Some items are still being reserved…',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    // Block checkout if any reservations have expired
    if (cartService.hasExpiredItems) {
      Get.snackbar(
        'Reservation expired',
        'Some items need to be re-reserved before checkout.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.shade50,
        colorText: Colors.orange.shade800,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    isCheckingOut.value = true;
    try {
      final order = await orderRepo.checkout(cartService.items.toList());
      cartService.items.clear();
      cartService.itemCount.value = 0;
      Get.snackbar(
        'Order confirmed',
        'Order #${order.id} — pick up soon!',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on ApiException catch (e) {
      LogService.error('checkout failed', e);
      if (e.statusCode == 410) {
        // Reservation expired server-side during checkout
        Get.snackbar(
          'Reservation expired',
          'One or more holds expired. Please review your bag and try again.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange.shade50,
          colorText: Colors.orange.shade800,
          duration: const Duration(seconds: 4),
        );
      } else {
        Get.snackbar(
          'Checkout failed',
          e.message,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
    isCheckingOut.value = false;
  }
}
