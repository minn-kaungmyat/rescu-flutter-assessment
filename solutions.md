# solutions.md

## RES-101 Search shows results for the wrong query

**Root cause:** `_search()` fired on every keystroke with no delay and no way to cancel old requests. The API is intentionally slower for short broad queries like "s" (~1.2s) than specific ones like "sushi" (~0.2s). So typing "sushi" sends 5 requests "sushi" returns first and shows correct results, then "s" returns last and overwrites them.

**Why this fix is the right one:** Added a 300ms debounce time so only the final query is sent after the use pauses for a moment. Also added a generation counter so each search gets a ticket number, and when results come back we check if the number is still current. If a newer search starts, the stale results will be thrown away.

- _Alternative considered and rejected:_ My first thought after seeing the bug was using the debounce timer only. But when I discussed with the AI, I found that we really need both debounce and generation counter because if a user types and pauses (triggering a slow search), and then types again (triggering a fast search), the slow search could still arrive late and overwrite the correct results.

**Edge cases:** Clearing the text field resets immediately (no debounce). The debounce timer is cancelled in `onClose()` so it can't fire after the search screen is closed.

---

## RES-102 Crash after leaving My Orders

**Root cause:** In `pickup_countdown.dart`, a `Timer.periodic` is created in `initState()` to update the countdown every second. But the timer was never stored in a variable and there was no `dispose()` method. When the user navigates away, Flutter destroys the widget, but the orphaned timer keeps firing `setState()` on the dead widget causing the `setState() called after dispose()` crash.

**Why this fix is the right one:** Store the timer in a `_timer` variable and cancel it in `dispose()`. This is the standard Flutter pattern for cleaning up resources tied to a widget's lifecycle the timer only lives as long as the widget does.

- _Alternative considered and rejected:_ Wrapping `setState` in an `if (mounted)` check. This would stop the crash, but the timer would still run forever in the background wasting resources. The assessment says "a fix that merely hides the symptom scores worse than a correct diagnosis" so properly cancelling the timer is the right approach.

**Edge cases:** If the pickup window is already open when the widget loads (the remaining time is negative), the timer still ticks harmlessly showing "Pickup window is open", and gets properly cancelled when leaving. No additional logic needed.

---

## RES-103 Requests pile up the longer you browse

**Root cause:** In `deal_details_controller.dart`, this `ever(cartService.itemCount, ...)` use a listener to the global `CartService` every time we open a deal page. Because the global `CartService` lives forever but the controller is destroyed when we leave. The listener is glued to the permanent service, so it nevers get's cleaned up. Eg. after visiting 5 deals, there are 5 listeners and then tapping "Add to bag" results 5 separate API calls to re-check availability for all those deals.

**Why this fix is the right one:** Save the `Worker` object returned by `ever()` and call `_cartListener.dispose()` in the controller's `onClose()`. This way the listener dies when the controller dies, and only the current deal page reacts to cart changes.

- _Alternative considered and rejected:_ Removing the `ever()` entirely and just re-checking availability inside `addToCart()` after adding. This might work but breaks the reactive pattern like if someone else modifies the cart (e.g. from a different screen), this deal page wouldn't know about it.

**Edge cases:** If the user leaves the deal page before the re-check API call finishes, the response comes back to a disposed controller. But GetX handles this well, the observable update is ignored since nothing is listening anymore.

---

## RES-104 Duplicate deals in the home feed

**Root cause:** In `home_controller.dart`, there are `refreshDeals()` and `loadMore()` share the same `_page` variable without coordination. If the user pulls to refresh while the `loadMore()` is waiting for the server response, the refresh resets `_page` to 1. But `loadMore()` still finishes and appends its old page 2 data to list. The next scroll triggers `loadMore()` to fetch page 2 again (because `_page` is 1 now) results in duplicates.

**Why this fix is the right one:** We used a ticket like `_refreshGeneration` counter just like in RES-101. `refreshDeals()` increments the counter. `loadMore()` checks this counter before and after fetching data. If the counter changed while waiting, it means a refresh happened so the old data is rejected.

- _Alternative considered and rejected:_ Blocking pull-to-refresh while `loadMore()` is running. This would prevent the race condition but it is bad UX. Also if the network is slow, the user's natural reaction is to pull down to refresh, and blocking that makes the app feel broken.

**Edge cases:** If the user triggers multiple rapid refreshes, each one increments the generation, so only the very last refresh's data survives. The `finally` block ensures `_isFetchingMore` is always cleaned up even when we discard stale data.

---

## RES-105 Home feed jank

**Root cause:** There were three contributing problems in the home feed:

1. **Unnecessary rebuilds:** `scrollOffset` was observed by an `Obx` wrapping the entire `Scaffold`. The scroll listener updates `scrollOffset` continuously, so the whole screen subtree was rebuilt during scrolling even though only the AppBar elevation and FAB visibility needed the value.

2. **Eager list construction:** The feed used `ListView(children: ...)` and created all `DealCard` widgets from `visibleDeals` at once. As more deals were loaded, more widgets were created instead of building them only when needed.

3. **Large images in memory:** `TheNetworkImage` used `CachedNetworkImage` without `memCacheHeight` or `memCacheWidth`. The deal images are displayed at a fixed size, but the source images can be much larger, so the in-memory image cache could use more memory than necessary.

4. **Ghost Obx Listeners & Layout Jitter:** The `FlashCountdownText` widget used GetX's `Obx` to listen to a 1-second timer. Due to a known issue with `Obx` inside rapidly scrolling `ListView`s, the listeners failed to detach when the cards were destroyed off-screen. This left hundreds of "ghost" widgets firing every second in the background. Furthermore, when the text digits changed, their slight width differences caused the entire parent `Card` to relayout and repaint.

**Why this fix is the right one:**

1. **Targeted `Obx`:** Removed the top-level `Obx` and moved the `scrollOffset` observers to the AppBar and FAB. This prevents scroll updates from rebuilding the feed.

2. **Lazy list:** Replaced `ListView(children: ...)` with `ListView.builder`. Deal cards are now built lazily as they are needed.

3. **Image cache size:** Added `memCacheHeight` based on the displayed image height and device pixel ratio. This reduces the size of decoded images kept in the memory cache when the source image is much larger than the displayed image.

4. **Native Ticker & Paint Isolation:** Completely removed `Obx` from the ticking widgets and replaced it with Flutter's native `ValueListenableBuilder` connected to a custom `CentralTicker`, totally eliminating the memory leak. To stop layout jitter, the countdown text was wrapped in a `RepaintBoundary` and styled with `FontFeature.tabularFigures()`, ensuring Flutter only repaints a tiny isolated 20-pixel box instead of the entire Card layer.

**DevTools Evidence:**

_Note: The screenshots for the evidence below are located in the `assets/` folder. The performance screenshots are captured while scrolling through the deals rapidly up and down._

**Before the fixes:**

- **UI jank:** The UI thread reached ~28 ms per frame while completely idle, well above the 16 ms target for 60 FPS. DevTools recorded exactly 335 `Obx` and `Text` ghost rebuilds firing every single second due to the leaked listeners (see before-fix rebuild stats screenshot).

- **Memory:** The Dart heap reached 93.2 MB during our tests. The memory profiler showed 136 `DealModel` and `PickupWindowModel` instances loaded into memory, alongside heavy `CacheObject` allocations due to the large unscaled network images.

![Before Performance 1](assets/before_perf_1.png)

![Before Performance 2](assets/before_perf_2.png)

![Before Memory](assets/before_memory.png)

**After the fixes:**

- **UI performance:** The timeline is perfectly smooth and completely blue. While idle, UI thread time dropped well below 16ms, with `ValueListenableBuilder` rebuilding exactly the 2 widgets that are physically visible on screen. `Raster` times stayed under 8ms (see after-fix screenshots).

- **Raster performance:** Raster time was around 3.0 ms during steady scrolling.

- **Memory:** Dart heap usage dropped from 114.2 MB to 84.9 MB during the comparable test. The number of active `DealCard` instances was also substantially lower because the list is now built lazily.

![After Performance 1](assets/after_perf_1.png)

![After Performance 2](assets/after_perf_2.png)

![After Memory](assets/after_memory.png)

- _*Alternative considered and rejected:*_ I considered using `CustomScrollView` with `SliverList`, but `ListView.builder` provides the required lazy construction with less structural change to the existing screen.

**Edge cases:** Pull-to-refresh continues to work as before. The AppBar remains correctly sized after moving its `Obx` into the `PreferredSize` wrapper.

---

## RES-106 Wrong pickup times; "Pickup today" filter misses deals

**Root cause:** The API sends pickup times as ISO-8601 strings in UTC format. `DateTime.parse()` reads this and creates a Dart `DateTime` object locked in the UTC timezone. Because it was never converted to local time, `DateFormat` blindly printed the raw UTC hours and also `isToday` check compared a UTC date against the user's local date. This causes deals filter display to mess up.

**Why this fix is the right one:** I added `.toLocal()` directly in the JSON parser (`PickupWindowModel.fromJson`). This instantly translates the UTC time into the user's local timezone exactly when the data enters the app. This is the cleanest fix because all downstream UI logic (like formatting and the filter check) now automatically operates on local time.

- _Alternative considered and rejected:_ We could kept the model in UTC and added `.toLocal()` only in the UI when formatting the string. I rejected this because it is error-prone: if another developer adds a new screen and forgets to add `.toLocal()`, the bug comes back.

**Edge cases:** I also hardened the `isToday` getter. Instead of just checking if `start.day == DateTime.now().day`, it now also checks the `year`, `month`, and `day`.

---

## RES-107 Deep link opens to a crash

**Root cause:** When opened through a deep link, GetX does not pass the `DealModel` object in memory, meaning `Get.arguments` is `null`. The controller blindly tried to read `deal = Get.arguments as DealModel;`, causing an instant crash.

**Why this fix is the right one:** I updated the controller to handle missing data. If `Get.arguments` is missing, it grabs the `id` from the URL and downloads the deal from the backend. While it downloads, the screen displays a `CircularProgressIndicator` to prevent UI crashes. Once the data arrives, the screen instantly rebuilds.

- _Alternative considered and rejected:_ We could just simply show an error screen saying "Please open this deal from the home feed.", but this was rejected because the requirements explicitly forbid using error/fallback screens.

**Edge cases:** I added `if (deal == null) return;` safeguards inside `addToCart()` and `_recheckAvailability()`. This prevents the app from crashing if those actions are somehow triggered before the deep link finishes loading.

---

## F-1 Live flash-sale countdowns

**Implementation:** I added `TickService` that acts as a single 1-second metronome for the entire app. I created a tiny `FlashCountdownText` widget that uses `Obx` to redraw only the `00:00` string every second. For the Deal Card, I built a `FlashSaleWrapper` that listens to the clock in the background using `ever()`, but only calls `setState()` exactly once when the expiration time is reached. Also added a background listener to `CartService` that checks the clock every second; when `00:00` hits, it automatically deletes expired deals from the cart, blocks new additions, and pops up a `Snackbar` notice.

- _Alternative considered and rejected:_ The easiest approach would be wrapping the entire `DealCard` in an `Obx` so the whole card rebuilds every second. Rejected this because rebuilding a heavy parent card 60 times a minute per item can destroy scroll performance.

**Edge cases:** I handled the edge case where a user is actively staring at the `DealDetailsScreen` at the exact second a deal expires. To prevent them from trying to add a dead deal to their cart, the "Add to bag" button is wrapped in its own `Obx` and instantly passes `onPressed: null` to turn itself grey and unclickable the millisecond the clock runs out.

---

## F-2 Impression tracking

**Implementation:** Built an `ImpressionTracker` widget wrapping `VisibilityDetector`. It starts a 1s timer when `visibleFraction >= 0.5`. When completes, it calls `AnalyticsService` to queue the event. `AnalyticsService` uses a `Set<int>` to make sure deals are logged at most once per session. A list queue and a 15-second `Timer` are used to batch events. To maximize scroll performance, `ImpressionTracker.build` first checks the `AnalyticsService` to see if a deal was already logged globally; if so, it entirely skips mounting the `VisibilityDetector`.

- _Alternative considered and rejected:_ We could have placed the `VisibilityDetector` directly inside the `DealCard` file itself. I rejected this because it would tightly couple analytics logic to the UI presentation. Creating a reusable wrapper keeps the UI file clean and allows us to track impressions for any widget in the future.

**Edge cases:** If the user scrolls past a card very quickly, the `visibleFraction` drops below 0.5 before the 1-second timer finishes. The tracker intercepts this and cancels the timer instantly, preventing a false impression from being logged. Additionally, the `ValueKey` used for the detector is a combination of the deal ID, source string, and list index position; this make sure cryptographic uniqueness and prevents the detector from crashing even if a screen renders accidental duplicate deals.

---

## F-3 Stock reservations with optimistic UI

**Implementation:** Added server-side state tracking (`ReservationStatus` enum) into the `CartItemModel`. When a user adds an item, `CartService` instantly increments the UI (optimistic update) and calls the API in the background. To enforce the 5-minute lifecycle, reused the global `TickService` from F-1 to monitor all reservations every second. If an item expires, it is flagged as `expired` locally. The checkout process strictly validates this enum, blocking the transaction if any items are invalid. I abstracted the UI changes into a clean `CartItemCard` widget with private sub-widgets to maintain readability.

- _Alternative considered and rejected:_ For the "Mystery Requirement" (what to do when an item expires), I considered having the app automatically delete the expired item from the cart to save space. I rejected this because modifying a user's cart without their explicit consent while they are browsing or typing credit card details is terrible UX. Instead, we choose keep the item in the cart, ghost it (lower opacity), show a red "Expired" tag, and provide explicit "Re-reserve" and "Remove" buttons so the user has total control.

**Edge cases:**

1. **Quantity Reduction Rollback:** Because the API has no `adjustReservation` endpoint, reducing a quantity from 2 to 1 requires requesting a new reservation. If this fails due to stock contention (409 error), we must _not_ delete the item from the cart, because the user still holds the original reservation for 2! So we made a rollback logic to catch this and revert the UI quantity back to the previous valid state.
2. **Race Conditions:** If a user taps "Add" and then instantly taps "Delete" while the background API call is still flying, the API will eventually succeed and hold stock forever. So added a guard that checks if the item is still in the local cart after the `await` finishes; if it was deleted, it instantly fires a `releaseReservation` call to free the server stock.

---

## AI Usage Log

**Tool used:** Antigravity IDE (Claude) for codebase analysis and understanding, root-cause identification, code fixes, and documentation.

**How I used it:** I used the AI as a pair-programming partner. I had it analyze the codebase to map out the architecture and identify potential root causes for the bugs first. I discussed architectural approaches (like how to handle timers globally instead of locally) and pushed back when it suggested poor UX decisions or unidiomatic code (like raw streams instead of GetX). For every fix, I reviewed the code line-by-line, tested it manually in the UI, and deliberately commented out parts of the fixes to prove to myself exactly why they were necessary.

**Example 1 wrong/misleading AI suggestion:**
For the F-1 flash sale expiration, the AI suggested using `StreamBuilder` and `.distinct()` to prevent the deal card from rebuilding every second. This was misleading because it introduced raw Dart streams into a codebase that exclusively uses GetX for state management. I rejected this approach and built a clean `StatefulWidget` wrapper that uses a standard GetX `ever` listener instead.

**Example 2 wrong/misleading AI suggestion:**
For F-1, the AI suggested wrapping the "Add to bag" button in an `Obx` with a short-circuit condition: `deal.isFlashSale && !deal.flashSaleEndsAt!.isAfter(tick.now.value)`. This caused a crash when viewing regular (non-flash) deals. Because `deal.isFlashSale` was false, Dart short-circuited and never read the observable `now.value`, violating GetX's rule that every `Obx` must read an observable. I fixed this by only applying the `Obx` wrapper if the deal is actually a flash sale.

**Example 3 wrong/misleading AI suggestion:**
For the F-3 quantity decrement, the AI's rollback logic blindly deleted the entire item from the cart if the API request for the lower quantity failed. By testing the minus button manually, I noticed my entire valid reservation disappeared just because a quantity adjustment failed. I corrected the logic to gracefully revert the UI quantity back to its previous valid state if the user already held a confirmed reservation.

---

## Design Questions

**Q1: In this codebase, what is the difference between a `GetxController`'s lifecycle and a widget `State`'s lifecycle? Name one bug from Part A that exists because of confusion between the two.**
A widget `State` lives in the UI tree and dies (`dispose`) when it scrolls off-screen or the route changes. A `GetxController` lives in memory until its route is popped (`onClose`), while global services (`Get.put`) live forever. RES-103 happened because a temporary UI controller (`DealDetailsController`) added a permanent listener to the eternal `CartService`, but forgot to remove it when the screen closed.

**Q2: When does wrapping a large subtree in a single `Obx` hurt you? How do you decide how tightly to scope reactivity?**
Wrapping a huge subtree (like a `Scaffold`) in a single `Obx` hurts performance because a single variable change forces Flutter to redraw everything inside it, causing lag (as seen in RES-105). To fix this, we follow the "leaf node rule": push `Obx` as deep down the widget tree as possible so it only wraps the exact `Text` or `Icon` that actually changes (e.g., `FlashCountdownText`).

**Q3: How would you write an automated test that would have caught RES-106 before release? What (if anything) would you change in the code to make such a test possible?**
To catch RES-106, we need a unit test that passes a known UTC string (`"2026-10-01T23:00:00Z"`) to `PickupWindowModel.fromJson()` and asserts that the local time shifts correctly. To make this test reliable, I would stop using the global `DateTime.now()` and `.toLocal()`. Instead, we can pass a mockable `TimeProvider` interface into the parser so the test suite can explicitly fake the user's "local" timezone.

---

## Time Spent

| Phase               | Time    |
| ------------------- | ------- |
| Setup & environment | ~1 hr   |
| Codebase analysis   | ~2 hr   |
| Bug fixes           | ~3 hr   |
| Features            | ~4.5 hr |
| Documentation       | ~1.5 hr |
| **Total**           | ~12 hr  |

**What I'd do with one more day:**
I would write unit tests for the `CartService` state machine to ensure the pending, reserved, and expired transitions behave correctly under mocked time. I'd also like to add a network monitor to handle offline states more gracefully (like pausing the background `TickService`), and finally, add some simple Hero animations between the home feed and the deal details screen to make the app feel a bit more polished.
