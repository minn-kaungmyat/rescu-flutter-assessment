import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../service/analytics_service.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

class DealDetailsController extends GetxController {
  final DealRepo dealRepo;
  final CartService cartService;
  final AnalyticsService analytics;

  DealDetailsController({
    required this.dealRepo,
    required this.cartService,
    required this.analytics,
  });

  final _deal = Rxn<DealModel>();
  DealModel? get deal => _deal.value;
  bool get isLoading => _deal.value == null;

  final _quantityLeft = RxnInt();
  Worker? _cartListener;
  int? get quantityLeft => _quantityLeft.value;

  @override
  void onInit() {
    super.onInit();
    _initDeal();
  }

  Future<void> _initDeal() async {
    if (Get.arguments is DealModel) {
      _deal.value = Get.arguments as DealModel;
      _onDealLoaded();
      return;
    }

    final idParam = Get.parameters['id'];
    if (idParam != null) {
      final id = int.tryParse(idParam);
      if (id != null) {
        try {
          _deal.value = await dealRepo.fetchById(id);
          _onDealLoaded();
          return;
        } catch (e) {
          LogService.error('Failed to fetch deal from deep link', e);
        }
      }
    }
  }

  void _onDealLoaded() {
    _quantityLeft.value = _deal.value!.quantityLeft;
    analytics.logEvent('deal_details_view', {
      'deal_id': _deal.value!.id,
      'source': Get.parameters['source'] ?? 'unknown',
    });
    // Whenever the cart changes, re-check this deal's remaining stock so the
    // details screen never shows stale availability.
    _cartListener = ever(cartService.itemCount, (_) => _recheckAvailability());
  }

  Future<void> _recheckAvailability() async {
    if (deal == null) return;
    LogService.log('re-checking availability for deal ${deal!.id}');
    final fresh = await dealRepo.fetchById(deal!.id);
    _quantityLeft.value = fresh.quantityLeft;
  }

  void addToCart() {
    if (deal == null) return;
    cartService.add(deal!);
    Get.snackbar(
      'Added to bag',
      '${deal!.name} — pick up ${deal!.pickupWindow.label}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void onClose() {
    _cartListener?.dispose();
    super.onClose();
  }
}
