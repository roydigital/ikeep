import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/constants/subscription_constants.dart';
import '../../providers/service_providers.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_colors.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PaywallScreen(),
    );
  }

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  final Map<AppPlan, ProductDetails> _productsByPlan =
      <AppPlan, ProductDetails>{};

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  ProviderSubscription<AppSettings>? _settingsSubscription;

  bool _isLoadingStore = true;
  bool _isStoreAvailable = false;
  bool _isRestoring = false;
  AppPlan? _activePlan;
  String? _errorText;
  List<String> _notFoundIds = const <String>[];

  @override
  void initState() {
    super.initState();

    _settingsSubscription = ref.listenManual<AppSettings>(
      settingsProvider,
      (previous, next) {
        if (previous?.isPremium != true && next.isPremium && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('${next.plan.label} activated successfully.')),
          );
          Navigator.of(context).pop();
        }
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startPurchaseListener();
      unawaited(_loadProducts());
    });
  }

  void _startPurchaseListener() {
    final billingService = ref.read(googlePlayBillingServiceProvider);
    if (!billingService.isSupportedPlatform) return;

    _purchaseSubscription = billingService.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Paywall purchase stream error: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    final billingService = ref.read(googlePlayBillingServiceProvider);

    for (final purchase in purchaseDetailsList) {
      final plan = billingService.planForProductId(purchase.productID);
      if (plan == null || !mounted) continue;

      if (purchase.status == PurchaseStatus.pending) {
        setState(() {
          _activePlan = plan;
          _errorText = null;
        });
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        setState(() {
          _activePlan = null;
          _errorText = purchase.error?.message ??
              'Unable to complete the Google Play purchase.';
        });
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        setState(() {
          _activePlan = null;
          _errorText = null;
        });
        continue;
      }

      setState(() {
        _activePlan = null;
      });
    }
  }

  Future<void> _loadProducts() async {
    final billingService = ref.read(googlePlayBillingServiceProvider);

    if (!billingService.isSupportedPlatform) {
      if (!mounted) return;
      setState(() {
        _isLoadingStore = false;
        _isStoreAvailable = false;
        _errorText = 'Google Play subscriptions are available only on Android.';
      });
      return;
    }

    try {
      final isAvailable = await billingService.isStoreAvailable();
      if (!mounted) return;

      if (!isAvailable) {
        setState(() {
          _isLoadingStore = false;
          _isStoreAvailable = false;
          _errorText =
              'Google Play Store is currently unavailable on this device.';
        });
        return;
      }

      final response = await billingService.querySubscriptions();
      if (!mounted) return;

      final productsByPlan = <AppPlan, ProductDetails>{};
      for (final product in response.productDetails) {
        final plan = billingService.planForProductId(product.id);
        if (plan != null) {
          productsByPlan[plan] = product;
        }
      }

      setState(() {
        _productsByPlan
          ..clear()
          ..addAll(productsByPlan);
        _notFoundIds = response.notFoundIDs;
        _isLoadingStore = false;
        _isStoreAvailable = true;
        _errorText = response.error?.message;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load Google Play products: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      setState(() {
        _isLoadingStore = false;
        _isStoreAvailable = false;
        _errorText = 'Unable to load subscription plans right now.';
      });
    }
  }

  Future<void> _restorePurchases() async {
    final billingService = ref.read(googlePlayBillingServiceProvider);
    if (!billingService.isSupportedPlatform) return;

    setState(() {
      _isRestoring = true;
      _errorText = null;
    });

    try {
      await billingService.restorePurchases();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Restore requested. If an active subscription exists, it will appear shortly.',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Restore purchases failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _errorText = 'Unable to restore purchases right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
      }
    }
  }

  Future<void> _subscribeToPlan(AppPlan plan) async {
    final billingService = ref.read(googlePlayBillingServiceProvider);
    final product = _productsByPlan[plan];

    if (product == null) {
      setState(() {
        _errorText = googlePlaySubscriptionSetupNotice;
      });
      return;
    }

    setState(() {
      _activePlan = plan;
      _errorText = null;
    });

    try {
      final launched = await billingService.startSubscriptionPurchase(product);
      if (!mounted) return;
      if (!launched) {
        setState(() {
          _activePlan = null;
          _errorText = 'Google Play could not open the purchase flow.';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Subscription purchase failed to start: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _activePlan = null;
        _errorText = 'Unable to start the Google Play purchase flow.';
      });
    }
  }

  String _planPriceLabel(AppPlan plan) {
    final billingService = ref.read(googlePlayBillingServiceProvider);
    final product = _productsByPlan[plan];
    final price = product?.price ?? billingService.fallbackPriceForPlan(plan);

    if (plan == AppPlan.monthly) return '$price / month';
    if (plan == AppPlan.yearly) return '$price / year';
    return price;
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _settingsSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final showSetupNotice = _notFoundIds.isNotEmpty ||
        (_isStoreAvailable && _productsByPlan.isEmpty);

    Widget feature(String text) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.check_circle, color: AppColors.success, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    Widget planButton({
      required AppPlan plan,
      required String title,
      required String subtitle,
    }) {
      final isCurrentPlan = settings.isPremium && settings.plan == plan;
      final isBusy = _activePlan == plan;
      final isAvailable = _productsByPlan.containsKey(plan);
      final canPurchase = _isStoreAvailable && isAvailable && !isCurrentPlan;

      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: canPurchase && !isBusy && _activePlan == null
              ? () => _subscribeToPlan(plan)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _planPriceLabel(plan),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (isBusy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              else if (isCurrentPlan)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'CURRENT',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                )
              else
                const Icon(Icons.arrow_forward_rounded),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 52,
                      height: 5,
                      decoration: BoxDecoration(
                        color: textSecondary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: AppColors.primary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Protect your memories. Upgrade to Ikeep Plus.',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Unlock full cloud protection and keep every important item safely backed up.',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  feature(premiumCloudBackupFeatureLabel),
                  const SizedBox(height: 14),
                  feature('Restore across devices'),
                  const SizedBox(height: 14),
                  feature('Unlimited Family Sharing'),
                  const SizedBox(height: 10),
                  Text(
                    premiumCloudBackupFairUsageDisclaimer,
                    style: TextStyle(
                      color: textSecondary.withValues(alpha: 0.72),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_isLoadingStore)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  if (!_isLoadingStore) ...[
                    planButton(
                      plan: AppPlan.monthly,
                      title: 'Monthly Plus',
                      subtitle: 'Flexible monthly access via Google Play',
                    ),
                    const SizedBox(height: 12),
                    planButton(
                      plan: AppPlan.yearly,
                      title: 'Yearly Plus',
                      subtitle: 'Best long-term value for cloud protection',
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isRestoring || !_isStoreAvailable
                          ? null
                          : _restorePurchases,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.45),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: _isRestoring
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.restore_rounded),
                      label: const Text(
                        'Restore Purchases',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        _errorText!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                  if (showSetupNotice) ...[
                    const SizedBox(height: 14),
                    Text(
                      googlePlaySubscriptionSetupNotice,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    googlePlaySubscriptionTestingNotice,
                    style: TextStyle(
                      color: textSecondary.withValues(alpha: 0.82),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
