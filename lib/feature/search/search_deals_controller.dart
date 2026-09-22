import 'dart:async';

import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../util/log_service.dart';

class SearchDealsController extends GetxController {
  final DealRepo dealRepo;

  SearchDealsController({required this.dealRepo});

  final results = <DealModel>[].obs;
  final isLoading = false.obs;
  final hasSearched = false.obs;

  /// Debounce timer — waits 300ms after the last keystroke before searching.
  Timer? _debounce;

  /// Generation counter — incremented on every new search so stale responses
  /// from slower, earlier queries are discarded.
  int _searchGeneration = 0;

  void onQueryChanged(String query) {
    // Cancel any pending debounce timer from the previous keystroke.
    _debounce?.cancel();

    // If the field is cleared, reset immediately (no debounce needed).
    if (query.trim().isEmpty) {
      _searchGeneration++;
      results.clear();
      hasSearched.value = false;
      isLoading.value = false;
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    // Capture the current generation before the async gap.
    final generation = ++_searchGeneration;

    isLoading.value = true;
    hasSearched.value = true;
    try {
      final found = await dealRepo.search(query);

      // If a newer search was started while we were waiting, discard
      if (generation != _searchGeneration) return;

      results.assignAll(found);
    } catch (e) {
      if (generation != _searchGeneration) return;
      LogService.error('search failed', e);
    }
    isLoading.value = false;
  }

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }
}
