import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../../app/design/sheets.dart';
import '../../app/design/tokens.dart';
import '../../data/library.dart';
import '../record/widgets.dart';

enum StoreEvent { owned, pending, cancelled, failed }

/// The one-time Pro purchase. The store only answers; the entitlement is kept in settings.
abstract class Store {
  /// Price text when Pro can be bought now; null when it can't (no store, not on sale yet).
  Future<String?> price();
  Future<void> buy();
  Future<void> restore();

  /// Purchases and restores as the store confirms them (also ones finishing after a restart).
  Stream<StoreEvent> get events;

  /// Saves the entitlement; awaited before the store is told the purchase was delivered, so a
  /// kill in between never leaves a paid purchase without Pro.
  Future<void> Function()? onOwned;
}

/// No store (tests, and builds without store credentials): Pro is simply not for sale.
class NoStore implements Store {
  @override
  Future<void> Function()? onOwned;
  @override
  Future<String?> price() async => null;
  @override
  Future<void> buy() async {}
  @override
  Future<void> restore() async {}
  @override
  Stream<StoreEvent> get events => const Stream.empty();
}

/// Google Play Billing / StoreKit through in_app_purchase. Product `earmark_pro`, non-consumable.
class IapStore implements Store {
  IapStore() {
    // Listen from app start: a purchase can finish after the app was closed mid-payment.
    _iap.purchaseStream.listen(_onPurchases, onError: (Object _) => _events.add(StoreEvent.failed));
  }

  static const productId = 'earmark_pro';
  final _iap = InAppPurchase.instance;
  @override
  Future<void> Function()? onOwned;
  final _events = StreamController<StoreEvent>.broadcast();
  ProductDetails? _product;

  @override
  Stream<StoreEvent> get events => _events.stream;

  @override
  Future<String?> price() async {
    if (!await _iap.isAvailable()) return null;
    final r = await _iap.queryProductDetails({productId});
    _product = r.productDetails.where((p) => p.id == productId).firstOrNull;
    return _product?.price;
  }

  @override
  Future<void> buy() async {
    final p = _product;
    if (p == null) throw StateError('Pro is not for sale');
    // false: the store refused to open (for example Pro is already owned on this account).
    if (!await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p))) {
      throw StateError('purchase not started');
    }
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    // Play reports a cancel or an error with no product as productID ''.
    for (final p in list.where((p) => p.productID == productId || p.productID.isEmpty)) {
      // A restore lists unpaid (pending) purchases as "restored" too: those are not owned yet.
      final unpaid = p is GooglePlayPurchaseDetails && p.billingClientPurchase.purchaseState != PurchaseStateWrapper.purchased;
      final e = switch (p.status) {
        PurchaseStatus.purchased || PurchaseStatus.restored => unpaid ? StoreEvent.pending : StoreEvent.owned,
        PurchaseStatus.pending => StoreEvent.pending,
        PurchaseStatus.canceled => StoreEvent.cancelled,
        PurchaseStatus.error => StoreEvent.failed,
      };
      if (e == StoreEvent.owned) await onOwned?.call();
      _events.add(e);
      // Acknowledges the purchase (Play refunds unacknowledged ones after 3 days); the silent
      // restore at each start retries any that failed.
      if (e != StoreEvent.pending && p.pendingCompletePurchase && p.productID.isNotEmpty) {
        try {
          await _iap.completePurchase(p);
        } catch (_) {}
      }
    }
  }
}

/// Pro state for the screens: owned (kept in settings), price, and the last store answer.
class Pro extends ChangeNotifier {
  Pro({required this.store, required this.library}) {
    store.onOwned = () => library.setPro(true);
    store.events.listen(_on);
  }

  /// Android: a silent check of owned purchases at start (no sign-in prompt there) re-delivers
  /// and acknowledges any purchase that finished while the app was closed.
  Future<void> startup() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await store.restore();
    } catch (_) {}
  }

  Timer? _restoreTimer;

  final Store store;
  final LibraryStore library;

  bool get owned => library.pro;

  /// Null while unchecked or when Pro can't be bought right now.
  String? price;
  bool checked = false;
  bool busy = false;

  /// The latest outcome to show under the buttons.
  String? message;

  Future<void> check() async {
    try {
      price = await store.price();
    } catch (_) {
      price = null;
    }
    checked = true;
    notifyListeners();
  }

  Future<void> buy() async {
    _busy(null);
    try {
      await store.buy();
    } catch (_) {
      busy = false;
      message = "The store couldn't start the purchase. If you bought Pro before, tap Restore purchase.";
      notifyListeners();
    }
  }

  Future<void> restore() async {
    _busy(null);
    try {
      await store.restore();
    } catch (_) {
      busy = false;
      message = "The store couldn't be reached. Try again later.";
      notifyListeners();
      return;
    }
    // A restore with nothing to restore sends no event: settle after a while (one timer only).
    _restoreTimer?.cancel();
    _restoreTimer = Timer(const Duration(seconds: 8), () {
      if (!busy || owned) return;
      busy = false;
      message = 'No Pro purchase found for this store account.';
      notifyListeners();
    });
  }

  void _busy(String? m) {
    busy = true;
    message = m;
    notifyListeners();
  }

  void _on(StoreEvent e) {
    if (e == StoreEvent.owned && !library.pro) unawaited(library.setPro(true)); // stores without onOwned
    if (e != StoreEvent.pending) _restoreTimer?.cancel();
    busy = e == StoreEvent.pending;
    message = switch (e) {
      StoreEvent.owned => 'Pro is on. Thank you.',
      StoreEvent.pending => 'Waiting for the store to confirm the payment.',
      StoreEvent.cancelled => null,
      StoreEvent.failed => "The purchase didn't go through.",
    };
    notifyListeners();
  }
}

/// True when Pro is owned; otherwise opens the Pro sheet and answers after it closes.
Future<bool> requirePro(BuildContext context, Pro pro) async {
  if (pro.owned) return true;
  await showAppSheet<void>(context, (_) => ProSheet(pro: pro));
  return pro.owned;
}

class ProSheet extends StatefulWidget {
  const ProSheet({super.key, required this.pro});

  final Pro pro;

  @override
  State<ProSheet> createState() => _ProSheetState();
}

class _ProSheetState extends State<ProSheet> {
  @override
  void initState() {
    super.initState();
    if (!widget.pro.owned) widget.pro.check();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.pro,
      builder: (context, _) {
        final p = widget.pro;
        Widget feature(String title, String detail) => Padding(
              padding: const EdgeInsets.only(bottom: Space.l),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 3), child: RibbonGlyph(color: c.accentInk, size: 16)),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: text.labelLarge),
                    const SizedBox(height: 2),
                    Text(detail, style: text.bodyMedium!.copyWith(color: c.text2)),
                  ]),
                ),
              ]),
            );
        final String? reason = p.owned
            ? null
            : !p.checked
                ? 'Checking the store…'
                : p.price == null
                    ? "Pro isn't on sale yet. Everything else in Earmark is free and complete."
                    : null;
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Earmark Pro', style: text.headlineSmall),
              const SizedBox(height: Space.xs),
              Text('One payment, yours for good. No subscription, no account.', style: text.bodyLarge!.copyWith(color: c.text2)),
              const SizedBox(height: Space.xl),
              feature('Share many clips at once', 'Pick marks in a recording and share all their clips together.'),
              feature('Quick labels', 'Hold Bookmark while recording, slide to Idea, To-do, Quote or Question, and let go.'),
              const SizedBox(height: Space.s),
              if (p.owned)
                Semantics(
                  liveRegion: true,
                  child: Text('Pro is on. Thank you for supporting Earmark.', style: text.labelLarge!.copyWith(color: c.success)),
                )
              else ...[
                SheetButton(
                  label: p.busy ? 'Waiting for the store…' : (p.price == null ? 'Buy Pro' : 'Buy Pro · ${p.price}'),
                  fill: p.price == null || p.busy ? null : c.accent,
                  ink: c.onAccent,
                  onTap: p.price == null || p.busy ? null : p.buy,
                ),
                if (reason != null) ...[
                  const SizedBox(height: Space.s),
                  Text(reason, style: text.bodyMedium!.copyWith(color: c.text2)),
                ],
                const SizedBox(height: Space.s),
                SheetButton(label: 'Restore purchase', onTap: p.busy ? null : p.restore),
              ],
              if (p.message != null && !p.owned) ...[
                const SizedBox(height: Space.m),
                Semantics(liveRegion: true, child: Text(p.message!, style: text.bodyMedium)),
              ],
            ],
          ),
        );
      },
    );
  }
}
