import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../providers/service_providers.dart';
import '../providers/settings_provider.dart';

class GooglePlayBillingListener extends ConsumerStatefulWidget {
  const GooglePlayBillingListener({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<GooglePlayBillingListener> createState() =>
      _GooglePlayBillingListenerState();
}

class _GooglePlayBillingListenerState
    extends ConsumerState<GooglePlayBillingListener> {
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final billingService = ref.read(googlePlayBillingServiceProvider);
      if (!billingService.isSupportedPlatform) return;

      _purchaseSubscription = billingService.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Google Play purchase stream error: $error');
          debugPrintStack(stackTrace: stackTrace);
        },
      );

      unawaited(billingService.restorePurchases());
    });
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    final billingService = ref.read(googlePlayBillingServiceProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    for (final purchase in purchaseDetailsList) {
      final plan = billingService.planForProductId(purchase.productID);
      if (plan == null) continue;

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await settingsNotifier.setPlan(plan);
      } else if (purchase.status == PurchaseStatus.error) {
        debugPrint('Google Play purchase failed: ${purchase.error}');
      }

      if (purchase.pendingCompletePurchase) {
        try {
          await billingService.completePurchase(purchase);
        } catch (error, stackTrace) {
          debugPrint('Failed to complete purchase: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
