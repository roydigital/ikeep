import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/constants/subscription_constants.dart';
import '../providers/settings_provider.dart';

class GooglePlayBillingService {
  GooglePlayBillingService({InAppPurchase? inAppPurchase})
      : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;

  static const Set<String> _productIds = <String>{
    googlePlayMonthlySubscriptionId,
    googlePlayYearlySubscriptionId,
  };

  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Set<String> get productIds => _productIds;

  Stream<List<PurchaseDetails>> get purchaseStream =>
      _inAppPurchase.purchaseStream;

  Future<bool> isStoreAvailable() async {
    if (!isSupportedPlatform) return false;
    return _inAppPurchase.isAvailable();
  }

  Future<ProductDetailsResponse> querySubscriptions() {
    return _inAppPurchase.queryProductDetails(_productIds);
  }

  AppPlan? planForProductId(String productId) {
    switch (productId) {
      case googlePlayMonthlySubscriptionId:
        return AppPlan.monthly;
      case googlePlayYearlySubscriptionId:
        return AppPlan.yearly;
      default:
        return null;
    }
  }

  String fallbackPriceForPlan(AppPlan plan) {
    if (plan == AppPlan.monthly) return monthlyPlanFallbackPrice;
    if (plan == AppPlan.yearly) return yearlyPlanFallbackPrice;
    return '';
  }

  Future<bool> startSubscriptionPurchase(ProductDetails productDetails) {
    final purchaseParam = PurchaseParam(productDetails: productDetails);
    return _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() {
    return _inAppPurchase.restorePurchases();
  }

  Future<void> completePurchase(PurchaseDetails purchaseDetails) {
    return _inAppPurchase.completePurchase(purchaseDetails);
  }
}
