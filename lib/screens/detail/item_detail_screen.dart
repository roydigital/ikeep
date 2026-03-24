import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/subscription_constants.dart';
import '../../core/utils/uuid_generator.dart';
import '../../domain/models/firestore_borrow_request.dart';
import '../../domain/models/household_member.dart';
import '../../domain/models/item.dart';
import '../../domain/models/item_location_history.dart';
import '../../domain/models/item_visibility.dart';
import '../../domain/models/location_model.dart';
import '../../providers/history_providers.dart';
import '../../providers/household_providers.dart';
import '../../providers/item_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/settings_provider.dart';
import '../../routing/app_routes.dart';
import '../settings/paywall_screen.dart';
import '../../theme/app_colors.dart';
import '../../widgets/adaptive_image.dart';
import '../../widgets/app_nav_bar.dart';
import '../../widgets/item_activity_timeline.dart';

class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key, required this.uuid});
  final String uuid;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  int _selectedImage = 0;
  bool _expiryLoading = false;
  String _expiryStatusText = '';

  // General-purpose loading state for async actions
  String? _activeOp; // non-null = an operation is in progress
  String _activeOpText = '';

  void _startOp(String text) => setState(() {
        _activeOp = text;
        _activeOpText = text;
      });
  void _endOp() => setState(() {
        _activeOp = null;
        _activeOpText = '';
      });

  Future<void> _showCloudQuotaFeedback(bool isPremium) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(cloudBackupQuotaExceededError(isPremium: isPremium)),
        backgroundColor: AppColors.error,
      ),
    );
    if (!isPremium) {
      await _showPaywall();
    }
  }

  Future<bool> _confirmDisableCloudBackup(Item item) async {
    if (item.visibility != ItemVisibility.household) {
      return true;
    }

    final shouldDisable = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Turn off backup and sharing?'),
        content: const Text(
          'This item is currently visible to family members. '
          'Turning off Backup to Cloud will also switch Visibility off '
          'and keep the item only on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Turn Off'),
          ),
        ],
      ),
    );

    return shouldDisable ?? false;
  }

  Future<void> _toggleCloudBackup(Item item, bool enabled) async {
    if (!enabled) {
      final shouldDisable = await _confirmDisableCloudBackup(item);
      if (!shouldDisable) return;
    }

    _startOp(enabled ? 'Enabling cloud backup...' : 'Disabling cloud backup...');

    if (!enabled) {
      final wasSharedWithHousehold =
          item.visibility == ItemVisibility.household;
      final error = await ref.read(itemsNotifierProvider.notifier).updateItem(
            item.copyWith(
              isBackedUp: false,
              clearCloudId: true,
              clearLastSyncedAt: true,
              visibility: ItemVisibility.private_,
              clearHouseholdId: true,
              sharedWithMemberUuids: const [],
              updatedAt: DateTime.now(),
            ),
          );
      if (!mounted) return;
      _endOp();
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.error),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasSharedWithHousehold
                  ? 'Cloud backup disabled. Family visibility turned off because this item is now saved only on this device.'
                  : 'Cloud backup disabled. This item is now saved only on this device.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
      return;
    }

    final settings = ref.read(settingsProvider);
    final backedUpCount = await ref.read(backedUpItemsCountProvider.future);
    if (hasReachedCloudBackupLimit(
      isPremium: settings.isPremium,
      backedUpCount: backedUpCount,
    )) {
      if (!mounted) return;
      _endOp();
      await _showCloudQuotaFeedback(settings.isPremium);
      return;
    }

    await ref.read(settingsProvider.notifier).setBackupEnabled(true);
    final error = await ref.read(itemsNotifierProvider.notifier).updateItem(
          item.copyWith(
            isBackedUp: true,
            updatedAt: DateTime.now(),
          ),
        );
    if (!mounted) return;
    _endOp();

    if (error != null) {
      if (error.contains('Cloud quota exceeded')) {
        await _showCloudQuotaFeedback(settings.isPremium);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cloud backup enabled. You can now share this item from Visibility.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _showPaywall() {
    return PaywallScreen.show(context);
  }

  int _itemImageLimitFor(bool isPremium) {
    return isPremium ? premiumItemImageLimit : freeItemImageLimit;
  }

  Future<bool> _canAddAnotherImage(Item item) async {
    final settings = ref.read(settingsProvider);
    final imageLimit = _itemImageLimitFor(settings.isPremium);
    if (item.imagePaths.length < imageLimit) {
      return true;
    }

    final message = settings.isPremium
        ? 'Paid members can add up to $premiumItemImageLimit photos per item.'
        : 'Free members can add 1 photo per item. Upgrade to add up to $premiumItemImageLimit photos.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );

    if (!settings.isPremium) {
      await _showPaywall();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final itemAsync = ref.watch(singleItemProvider(widget.uuid));
    final settings = ref.watch(settingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: itemAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('Error: $e', style: TextStyle(color: textPrimary))),
        data: (item) {
          if (item == null) {
            return Center(
                child: Text('Item not found',
                    style: TextStyle(color: textPrimary)));
          }

          final historyAsync = ref.watch(itemHistoryProvider(item.uuid));
          final images = item.imagePaths;
          final imageLimit = _itemImageLimitFor(settings.isPremium);
          final hasReachedImageLimit = images.length >= imageLimit;
          final selected = images.isEmpty
              ? null
              : images[_selectedImage.clamp(0, images.length - 1)];

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                        child: Row(
                          children: [
                            IconButton(
                                onPressed: () => context.pop(),
                                icon: const Icon(Icons.arrow_back, size: 30),
                                color: textPrimary),
                            Expanded(
                              child: Text('Item Details',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)),
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: textPrimary),
                              color: isDark
                                  ? AppColors.surfaceVariantDark
                                  : AppColors.surfaceVariantLight,
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _editItemName(item);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Image gallery ────────────────────────
                            if (images.isNotEmpty) ...[
                              GestureDetector(
                                onTap: () => _zoom(selected, isDark),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: AspectRatio(
                                    aspectRatio: 1,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        _img(selected!, BoxFit.cover, isDark),
                                        Positioned(
                                          top: 12,
                                          right: 12,
                                          child: Material(
                                            color: Colors.black54,
                                            shape: const CircleBorder(),
                                            child: IconButton(
                                              tooltip: 'Delete photo',
                                              onPressed: _activeOp != null
                                                  ? null
                                                  : () => _deleteImage(
                                                        item,
                                                        selected,
                                                      ),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (images.length > 1) ...[
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: 72,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: images.length + 1,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 10),
                                    itemBuilder: (_, i) {
                                      if (i == images.length) {
                                        return _addImageButton(
                                          item,
                                          hasReachedLimit: hasReachedImageLimit,
                                          imageLimit: imageLimit,
                                        );
                                      }
                                      return _thumb(images[i], i, isDark);
                                    },
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(height: 10),
                                _addImageButton(
                                  item,
                                  hasReachedLimit: hasReachedImageLimit,
                                  imageLimit: imageLimit,
                                ),
                              ],
                            ] else ...[
                              _addImageButton(
                                item,
                                hasReachedLimit: hasReachedImageLimit,
                                imageLimit: imageLimit,
                              ),
                            ],

                            const SizedBox(height: 22),

                            // ── Title + location ──────────────────────
                            Text(item.name,
                                style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    height: 1.05)),
                            const SizedBox(height: 8),
                            Row(children: [
                              const Icon(Icons.location_on,
                                  color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: historyAsync.when(
                                  data: (history) => Text(
                                    _location(
                                      item,
                                      latestHistory:
                                          history.isEmpty ? null : history.last,
                                    ),
                                    style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 17),
                                  ),
                                  loading: () => Text(
                                    _location(item),
                                    style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 17),
                                  ),
                                  error: (_, __) => Text(
                                    _location(item),
                                    style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 17),
                                  ),
                                ),
                              ),
                            ]),

                            const SizedBox(height: 14),

                            // ── Lending status ──────────────────────
                            _buildLendingSection(
                              context,
                              item,
                              isDark,
                              textPrimary,
                            ),

                            // ── Expiry status ───────────────────────
                            _buildExpirySection(
                              context,
                              item,
                              isDark,
                              textPrimary,
                            ),

                            const SizedBox(height: 18),
                            _buildCloudBackupSection(item, isDark, textPrimary),

                            const SizedBox(height: 18),
                            _ItemVisibilitySection(item: item),

                            if (item.tags.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: item.tags
                                    .map((t) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? AppColors.surfaceVariantDark
                                                : AppColors.surfaceVariantLight,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text('#$t',
                                              style: const TextStyle(
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.w600)),
                                        ))
                                    .toList(),
                              ),
                            ],

                            const SizedBox(height: 24),
                            historyAsync.when(
                              data: (h) => _meta(context, isDark, item.savedAt,
                                  h.isEmpty ? item.updatedAt : h.last.movedAt),
                              loading: () => _meta(context, isDark,
                                  item.savedAt, item.updatedAt),
                              error: (_, __) => _meta(context, isDark,
                                  item.savedAt, item.updatedAt),
                            ),

                            const SizedBox(height: 24),

                            // ── Action buttons ────────────────────────
                            Row(children: [
                              Expanded(
                                  child: _Action(
                                      label: 'Update\nLocation',
                                      filled: false,
                                      icon: Icons.edit_location_alt,
                                      onTap: () => _updateLocation(item))),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: _Action(
                                      label: item.isLent
                                          ? 'Mark\nReturned'
                                          : 'Found /\nRemove',
                                      filled: true,
                                      icon: item.isLent
                                          ? Icons.assignment_turned_in
                                          : Icons.check_circle,
                                      onTap: () => item.isLent
                                          ? _markReturned(item)
                                          : _foundRemove(item))),
                            ]),

                            const SizedBox(height: 44),

                            // ── History ───────────────────────────────
                            ItemActivityTimeline(
                              itemUuid: item.uuid,
                              showUserAttribution:
                                  item.visibility == ItemVisibility.household,
                              title: 'Location History',
                            ),
                            SizedBox(
                              height: AppNavBar.contentBottomSpacing(
                                context,
                                includeFab: true,
                              ),
                            ),
                          ]),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: const AppNavBar(activeTab: AppNavTab.items),
              ),
              const _DetailFab(),
              // ── Global loading banner for async ops ──
              if (_activeOp != null)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: AppNavBar.navBarHeight(context) + 16,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(14),
                    color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _activeOpText,
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimaryLight,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── Lending section ──────────────────────────────────────────────────────

  Widget _buildLendingSection(
    BuildContext context,
    Item item,
    bool isDark,
    Color textPrimary,
  ) {
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Lent status card
        if (item.isLent) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.outbox,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Currently Lent Out',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'To: ${item.lentTo ?? 'Unknown'}',
                  style: TextStyle(color: textPrimary, fontSize: 14),
                ),
                if (item.lentOn != null)
                  Text(
                    'Since: ${DateFormat('dd MMM yyyy').format(item.lentOn!)}',
                    style: TextStyle(color: textSecondary, fontSize: 13),
                  ),
                if (item.expectedReturnDate != null)
                  Text(
                    'Expected return: ${DateFormat('dd MMM yyyy').format(item.expectedReturnDate!)}',
                    style: TextStyle(color: textSecondary, fontSize: 13),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _activeOp != null ? null : () => _markReturned(item),
                    icon: const Icon(Icons.assignment_turned_in, size: 18),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    label: const Text('Mark as Returned'),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // Not lent — show "Lend This Item" button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _activeOp != null ? null : () => _lendItem(item),
              icon: const Icon(Icons.outbox, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side:
                    BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              label: const Text('Lend This Item',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ],
    );
  }

  // ── Expiry section ───────────────────────────────────────────────────────

  Widget _buildExpirySection(
    BuildContext context,
    Item item,
    bool isDark,
    Color textPrimary,
  ) {
    final expiryDate = item.expiryDate;

    // No expiry set — show "Add expiry" button or loading state
    if (expiryDate == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: _expiryLoading
            ? _buildExpiryLoadingIndicator(isDark)
            : SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _editExpiryDate(item),
                  icon: const Icon(Icons.event, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  label: const Text('Add Expiry Date',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
      );
    }

    // Expiry is set — compute urgency
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiryDay = DateTime(
      expiryDate.year,
      expiryDate.month,
      expiryDate.day,
    );
    final daysLeft = expiryDay.difference(today).inDays;

    // Color scheme based on urgency
    final Color accentColor;
    final Color bgColor;
    final IconData icon;
    final String statusText;
    final String subtitle;

    if (daysLeft < 0) {
      // Expired
      accentColor = AppColors.error;
      bgColor = AppColors.error.withValues(alpha: 0.12);
      icon = Icons.error_outline;
      statusText = 'Expired';
      subtitle = '${-daysLeft} ${-daysLeft == 1 ? "day" : "days"} ago  ·  '
          'Consider replacing or removing this item';
    } else if (daysLeft == 0) {
      // Expires today
      accentColor = AppColors.error;
      bgColor = AppColors.error.withValues(alpha: 0.12);
      icon = Icons.warning_amber_rounded;
      statusText = 'Expires Today';
      subtitle = 'Check this item before using it';
    } else if (daysLeft <= 7) {
      // Critical — within 7 days
      accentColor = AppColors.error;
      bgColor = AppColors.error.withValues(alpha: 0.10);
      icon = Icons.warning_amber_rounded;
      statusText = 'Expires in $daysLeft ${daysLeft == 1 ? "day" : "days"}';
      subtitle = DateFormat('dd MMM yyyy').format(expiryDate);
    } else if (daysLeft <= 30) {
      // Warning — within 30 days
      accentColor = AppColors.warning;
      bgColor = AppColors.warning.withValues(alpha: 0.10);
      icon = Icons.schedule;
      statusText = 'Expires in $daysLeft days';
      subtitle = DateFormat('dd MMM yyyy').format(expiryDate);
    } else {
      // Safe — more than 30 days
      accentColor = AppColors.success;
      bgColor = AppColors.success.withValues(alpha: 0.08);
      icon = Icons.event_available;
      statusText = 'Expires ${DateFormat('dd MMM yyyy').format(expiryDate)}';
      final months = (daysLeft / 30).floor();
      subtitle = months > 0
          ? '~$months ${months == 1 ? "month" : "months"} remaining'
          : '$daysLeft days remaining';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accentColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            if (_expiryLoading)
              _buildExpiryLoadingIndicator(isDark)
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _editExpiryDate(item),
                      icon: const Icon(Icons.edit_calendar, size: 16),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accentColor,
                        side: BorderSide(
                            color: accentColor.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      label: const Text('Change Date',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _removeExpiryDate(item),
                      icon: const Icon(Icons.event_busy, size: 16),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                        side: BorderSide(
                          color: isDark
                              ? AppColors.borderDark
                              : AppColors.borderLight,
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      label: const Text('Remove',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpiryLoadingIndicator(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _expiryStatusText,
            style: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editExpiryDate(Item item) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          item.expiryDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: 'SELECT EXPIRY DATE',
    );
    if (picked == null || !mounted) return;

    setState(() {
      _expiryLoading = true;
      _expiryStatusText = item.expiryDate == null
          ? 'Setting expiry date...'
          : 'Updating expiry date...';
    });

    final error = await ref.read(itemsNotifierProvider.notifier).updateItem(
          item.copyWith(expiryDate: picked, updatedAt: DateTime.now()),
        );
    if (!mounted) return;

    setState(() {
      _expiryLoading = false;
      _expiryStatusText = '';
    });

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Expiry set to ${DateFormat('dd MMM yyyy').format(picked)}',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _removeExpiryDate(Item item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Expiry Date'),
        content: Text(
          'Remove the expiry date from "${item.name}"? '
          'You won\'t receive expiry notifications for this item anymore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _expiryLoading = true;
      _expiryStatusText = 'Removing expiry date...';
    });

    final error = await ref.read(itemsNotifierProvider.notifier).updateItem(
          item.copyWith(clearExpiryDate: true, updatedAt: DateTime.now()),
        );
    if (!mounted) return;

    setState(() {
      _expiryLoading = false;
      _expiryStatusText = '';
    });

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expiry date removed'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Widget _buildCloudBackupSection(Item item, bool isDark, Color textPrimary) {
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final settings = ref.watch(settingsProvider);
    final backedUpCountAsync = ref.watch(backedUpItemsCountProvider);
    final backedUpCount = backedUpCountAsync.valueOrNull ?? 0;
    final progress = cloudBackupUsageProgress(
      isPremium: settings.isPremium,
      backedUpCount: backedUpCount,
    );
    final progressColor = backedUpCount >=
            cloudBackupWarningThresholdFor(settings.isPremium)
        ? AppColors.warning
        : AppColors.primary;
    final helperText = item.isBackedUp
        ? item.visibility == ItemVisibility.household
            ? 'This item is shareable because it is backed up. Turning backup off will also switch Visibility to private.'
            : 'Only cloud-backed items can be shared with family. Use Visibility if you want to share this item.'
        : 'This item is stored only on this device. Turn on cloud backup to make family sharing available.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backup to Cloud',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Turn On/Off Cloud Backup for this Item',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: item.isBackedUp
                                ? AppColors.primary
                                : textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_activeOp != null && _activeOp!.contains('backup'))
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary.withValues(alpha: 0.7),
                  ),
                )
              else
                Switch.adaptive(
                  value: item.isBackedUp,
                  activeThumbColor: AppColors.primary,
                  onChanged: (value) => _toggleCloudBackup(item, value),
                ),
            ],
          ),
          if (!settings.isPremium) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: backedUpCountAsync.isLoading ? null : progress,
              minHeight: 8,
              backgroundColor: textSecondary.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              borderRadius: BorderRadius.circular(999),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            helperText,
            style: TextStyle(
              color: textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _editItemName(Item item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: item.name);
    final updatedName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: Text(
          'Edit Item Name',
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
          decoration: InputDecoration(
            hintText: 'Item name',
            hintStyle: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
            filled: true,
            fillColor:
                isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Save',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted || updatedName == null || updatedName.isEmpty) return;
    if (updatedName == item.name) return;

    _startOp('Updating item name...');
    final error = await ref.read(itemsNotifierProvider.notifier).updateItem(
          item.copyWith(
            name: updatedName,
            updatedAt: DateTime.now(),
          ),
        );

    if (!mounted) return;
    _endOp();

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Item name updated'), backgroundColor: AppColors.success),
    );
  }

  Future<void> _lendItem(Item item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lentToController = TextEditingController();
    DateTime expectedReturn = DateTime.now().add(const Duration(days: 7));

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Lend "${item.name}"',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: lentToController,
                  autofocus: true,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Who are you lending to?',
                    hintStyle: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                    prefixIcon: const Icon(Icons.person_outline,
                        color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setSheet(() => expectedReturn = picked);
                    }
                  },
                  icon: const Icon(Icons.event_available, size: 18),
                  label: Text(
                    'Return by ${DateFormat('dd MMM yyyy').format(expectedReturn)}',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (lentToController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Enter who you\'re lending to'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop(true);
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    child: const Text('Lend Item'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final lentTo = lentToController.text.trim();
    if (confirmed != true || lentTo.isEmpty) return;

    _startOp('Lending item...');
    final updated = item.copyWith(
      isLent: true,
      lentTo: lentTo,
      lentOn: DateTime.now(),
      expectedReturnDate: expectedReturn,
    );
    final error =
        await ref.read(itemsNotifierProvider.notifier).updateItem(updated);
    if (!mounted) return;
    _endOp();

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    } else {
      ref.invalidate(singleItemProvider(widget.uuid));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lent to $lentTo'), backgroundColor: AppColors.success),
      );
    }
  }

  Future<void> _markReturned(Item item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor:
                isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            title: Text('Mark as Returned',
                style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight)),
            content: Text(
                'Confirm that "${item.name}" has been returned by ${item.lentTo ?? 'the borrower'}?',
                style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: const Text('Confirm Return')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    _startOp('Marking as returned...');
    final updated = item.copyWith(
      isLent: false,
      clearLentTo: true,
      clearLentOn: true,
      clearExpectedReturnDate: true,
      clearLentReminderAfterDays: true,
    );
    final error =
        await ref.read(itemsNotifierProvider.notifier).updateItem(updated);
    if (!mounted) return;
    _endOp();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? '${item.name} marked as returned'),
        backgroundColor: error != null ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _foundRemove(Item item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor:
                isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            title: Text('Found / Remove',
                style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight)),
            content: Text(
                'Mark this item as found and remove it from active items?',
                style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: const Text('Confirm')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    _startOp('Archiving item...');
    final error =
        await ref.read(itemsNotifierProvider.notifier).archiveItem(item.uuid);
    if (!mounted) return;
    _endOp();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
      return;
    }
    context.pop();
  }

  Future<void> _updateLocation(Item item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locations = await ref.read(allLocationsProvider.future);
    if (!mounted) return;
    String? selected = item.locationUuid;
    final newLocationController = TextEditingController();

    Future<void> saveNewLocation(BuildContext modalCtx) async {
      final name = newLocationController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a location name'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      final newLocation = LocationModel(
        uuid: generateUuid(),
        name: name,
        createdAt: DateTime.now(),
      );

      final error = await ref
          .read(locationsNotifierProvider.notifier)
          .saveLocation(newLocation);
      if (!mounted) return;

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.error),
        );
        return;
      }

      if (modalCtx.mounted) {
        Navigator.of(modalCtx).pop(newLocation.uuid);
      }
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setInner) => SafeArea(
          top: false,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(99))),
                  const SizedBox(height: 18),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Update Location',
                          style: TextStyle(
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                              fontWeight: FontWeight.w700,
                              fontSize: 20))),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.42,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: locations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final l = locations[i];
                        final active = l.uuid == selected;
                        return InkWell(
                          onTap: () => setInner(() => selected = l.uuid),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.primary.withValues(alpha: 0.2)
                                  : (isDark
                                      ? AppColors.surfaceVariantDark
                                      : AppColors.surfaceVariantLight),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: active
                                      ? AppColors.primary
                                      : Colors.transparent),
                            ),
                            child: Row(children: [
                              Icon(Icons.place_outlined,
                                  color: active
                                      ? AppColors.primary
                                      : (isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondaryLight)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(
                                      (l.fullPath?.trim().isNotEmpty ?? false)
                                          ? l.fullPath!
                                          : l.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: isDark
                                              ? AppColors.textPrimaryDark
                                              : AppColors.textPrimaryLight))),
                              if (active)
                                const Icon(Icons.check_circle,
                                    color: AppColors.primary),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: newLocationController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => saveNewLocation(ctx),
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.add_location_alt,
                          color: AppColors.primary),
                      hintText: 'Add new location (e.g. Kitchen Drawer)',
                      hintStyle: TextStyle(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppColors.surfaceVariantDark
                          : AppColors.surfaceVariantLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selected == null
                          ? null
                          : () => Navigator.of(ctx).pop(selected),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size.fromHeight(50)),
                      child: const Text('Save Location'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );

    if (result == null || result == item.locationUuid) return;
    final error = await ref
        .read(itemsNotifierProvider.notifier)
        .updateItem(item.copyWith(locationUuid: result));
    if (!mounted || error != null) return;
    ref.invalidate(singleItemProvider(widget.uuid));
    ref.invalidate(itemHistoryProvider(widget.uuid));
  }

  Future<void> _addImage(Item item) async {
    if (_activeOp != null) return;
    if (!await _canAddAnotherImage(item)) return;

    final source = await _chooseImageSource();
    if (source == null) return;

    _startOp('Processing photo...');
    String picked;
    try {
      picked = source == ImageSourceOption.camera
          ? await ref.read(imageServiceProvider).pickFromCamera()
          : await ref.read(imageServiceProvider).pickFromGallery();
    } catch (_) {
      if (mounted) _endOp();
      return;
    }

    if (!mounted) return;
    setState(() => _activeOpText = 'Saving photo...');
    final updated = item.copyWith(imagePaths: [...item.imagePaths, picked]);
    final error = await _persistItemImageChange(updated);
    if (!mounted) return;
    _endOp();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _selectedImage = updated.imagePaths.length - 1);
    ref.invalidate(singleItemProvider(widget.uuid));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo added'), backgroundColor: AppColors.success),
    );
  }

  Future<void> _deleteImage(Item item, String imagePath) async {
    if (_activeOp != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text(
          'This will remove the photo from this item and permanently delete its cloud copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    _startOp('Deleting photo...');
    final updatedPaths = [...item.imagePaths]..remove(imagePath);
    final updated = item.copyWith(imagePaths: updatedPaths);
    final error = await _persistItemImageChange(updated);
    if (!mounted) return;

    if (error != null) {
      _endOp();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
      return;
    }

    if (!imagePath.startsWith('http')) {
      await ref.read(imageServiceProvider).deleteImage(imagePath);
    }
    if (!mounted) return;

    setState(() {
      if (updatedPaths.isEmpty) {
        _selectedImage = 0;
      } else if (_selectedImage >= updatedPaths.length) {
        _selectedImage = updatedPaths.length - 1;
      }
    });
    _endOp();
    ref.invalidate(singleItemProvider(widget.uuid));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Photo deleted'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<ImageSourceOption?> _chooseImageSource() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return showModalBottomSheet<ImageSourceOption>(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add Photo',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _imageSourceTile(
                context: ctx,
                icon: Icons.photo_camera,
                title: 'Camera',
                subtitle: 'Take a new photo',
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                value: ImageSourceOption.camera,
              ),
              const SizedBox(height: 10),
              _imageSourceTile(
                context: ctx,
                icon: Icons.photo_library,
                title: 'Gallery',
                subtitle: 'Choose from your photos',
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                value: ImageSourceOption.gallery,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageSourceTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color textPrimary,
    required Color textSecondary,
    required ImageSourceOption value,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceVariantDark
              : AppColors.surfaceVariantLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: textPrimary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: textSecondary, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  void _zoom(String? path, bool isDark) {
    if (path == null || path.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(children: [
          InteractiveViewer(
              child: AspectRatio(
                  aspectRatio: 1, child: _img(path, BoxFit.contain, isDark))),
          Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white))),
        ]),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _img(String path, BoxFit fit, bool isDark) {
    return AdaptiveImage(
      path: path,
      fit: fit,
      errorBuilder: (_) => Container(
        color: isDark
            ? AppColors.surfaceVariantDark
            : AppColors.surfaceVariantLight,
        child: const Center(
            child:
                Icon(Icons.broken_image, color: AppColors.primary, size: 48)),
      ),
    );
  }

  Widget _thumb(String path, int index, bool isDark) {
    final active = index == _selectedImage;
    return GestureDetector(
      onTap: () => setState(() => _selectedImage = index),
      child: Container(
        width: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: _img(path, BoxFit.cover, isDark),
      ),
    );
  }

  Widget _addImageButton(
    Item item, {
    required bool hasReachedLimit,
    required int imageLimit,
  }) {
    return GestureDetector(
      onTap: () => _addImage(item),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: hasReachedLimit
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.primary.withValues(alpha: 0.12),
          border: Border.all(
            color: AppColors.primary.withValues(
              alpha: hasReachedLimit ? 0.18 : 0.3,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasReachedLimit ? Icons.lock_outline : Icons.add_a_photo,
              color: AppColors.primary.withValues(
                alpha: hasReachedLimit ? 0.7 : 1,
              ),
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              '${item.imagePaths.length}/$imageLimit',
              style: TextStyle(
                color: AppColors.primary.withValues(
                  alpha: hasReachedLimit ? 0.7 : 0.9,
                ),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _persistItemImageChange(Item updatedItem) async {
    final error =
        await ref.read(itemsNotifierProvider.notifier).updateItem(updatedItem);
    if (!mounted || error != null) return error;

    return null;
  }

  String _location(Item item, {ItemLocationHistory? latestHistory}) {
    if (item.locationFullPath?.trim().isNotEmpty ?? false) {
      return item.locationFullPath!;
    }
    if (item.locationName?.trim().isNotEmpty ?? false) {
      return item.locationName!;
    }
    if (latestHistory != null && latestHistory.locationName.trim().isNotEmpty) {
      return latestHistory.locationName;
    }
    return 'No location set';
  }

  Widget _meta(
      BuildContext context, bool isDark, DateTime savedAt, DateTime? movedAt) {
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.primary.withValues(alpha: 0.15)),
          bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(children: [
        Expanded(child: _metaCell(isDark, 'SAVED', _ago(savedAt), textPrimary)),
        Container(
            width: 1,
            height: 52,
            color: AppColors.primary.withValues(alpha: 0.15)),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.only(left: 22),
                child: _metaCell(isDark, 'LAST MOVED',
                    movedAt == null ? '-' : _ago(movedAt), textPrimary))),
      ]),
    );
  }

  Widget _metaCell(bool isDark, String title, String value, Color textPrimary) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              fontSize: 15.5,
              letterSpacing: 1.2)),
      const SizedBox(height: 4),
      Text(value,
          style: TextStyle(
              color: textPrimary, fontSize: 19.5, fontWeight: FontWeight.w600)),
    ]);
  }

  String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}

// ── Supporting widgets ─────────────────────────────────────────────────────────

class _ItemVisibilitySection extends ConsumerStatefulWidget {
  const _ItemVisibilitySection({required this.item});

  final Item item;

  @override
  ConsumerState<_ItemVisibilitySection> createState() =>
      _ItemVisibilitySectionState();
}

class _ItemVisibilitySectionState
    extends ConsumerState<_ItemVisibilitySection> {
  static const String _backupRequiredMessage =
      'Turn on Backup to Cloud before sharing this item with family. '
      'Device-only items stay private on this device.';

  bool _isSaving = false;

  /// Optimistic override so the switch flips immediately on tap instead of
  /// waiting for cloud sync to finish. Null = use the actual item state.
  bool? _pendingShared;

  Item get _item => widget.item;

  bool get _isShared =>
      _pendingShared ??
      (_item.visibility == ItemVisibility.household &&
          (!_isCurrentUserOwner || _item.isBackedUp));

  String? get _currentUserUid {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid.trim();
    if (uid == null || uid.isEmpty) return null;
    return uid;
  }

  String? get _itemOwnerMemberUuid {
    final cloudId = _item.cloudId?.trim();
    // cloudId stores the item's own UUID when set by FirebaseSyncService
    // (personal backup), but stores the actual ownerUid when synced from
    // the household Firestore collection. Only treat it as an owner UID
    // when it differs from the item UUID (i.e. it came from another member).
    if (cloudId != null &&
        cloudId.isNotEmpty &&
        cloudId != _item.uuid) {
      return cloudId;
    }
    return _currentUserUid;
  }

  bool get _canChangeShareState {
    final ownerMemberUuid = _itemOwnerMemberUuid;
    final currentUserUid = _currentUserUid;
    if (ownerMemberUuid == null || currentUserUid == null) return true;
    return ownerMemberUuid == currentUserUid;
  }

  bool get _isCurrentUserOwner => _canChangeShareState;

  bool get _canShareWhileBackupState =>
      !_isCurrentUserOwner || _item.isBackedUp;

  List<String> _normalizedSelectedMemberUuids([Iterable<String>? memberUuids]) {
    final ownerMemberUuid = _itemOwnerMemberUuid;
    final normalized = <String>[];
    final seen = <String>{};

    for (final memberUuid in memberUuids ?? _item.sharedWithMemberUuids) {
      final trimmedMemberUuid = memberUuid.trim();
      if (trimmedMemberUuid.isEmpty) continue;
      if (ownerMemberUuid != null && trimmedMemberUuid == ownerMemberUuid) {
        continue;
      }
      if (seen.add(trimmedMemberUuid)) {
        normalized.add(trimmedMemberUuid);
      }
    }

    return normalized;
  }

  /// Saves the item locally, syncs to personal cloud backup, and — when the
  /// item has household visibility — also pushes it to the household Firestore
  /// collection so other family members can see it.
  ///
  /// Returns a user-facing error string, or null on success.
  Future<String?> _saveItem(Item updatedItem) async {
    if (updatedItem.visibility == ItemVisibility.household &&
        _isCurrentUserOwner &&
        !updatedItem.isBackedUp) {
      return _backupRequiredMessage;
    }

    final error =
        await ref.read(itemsNotifierProvider.notifier).updateItem(updatedItem);
    if (!mounted) return error;
    return error;
  }

  Future<void> _toggleSharing(bool enabled) async {
    if (_isSaving) return;
    if (!enabled && !_canChangeShareState) return;
    if (enabled && !_canShareWhileBackupState) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_backupRequiredMessage)),
      );
      return;
    }

    // ── Flip the switch immediately (optimistic UI) ──
    setState(() {
      _isSaving = true;
      _pendingShared = enabled;
    });

    try {
      if (!enabled) {
        final error = await _saveItem(
          _item.copyWith(
            visibility: ItemVisibility.private_,
            clearHouseholdId: true,
            sharedWithMemberUuids: const [],
          ),
        );
        if (error != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error)));
        }
        return;
      }

      final householdId = await ref.read(currentHouseholdIdProvider.future);
      if (!mounted) return;
      if (householdId == null || householdId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Create a household before sharing this item.'),
          ),
        );
        return;
      }

      // Family sharing requires cloud backup — check quota first.
      final error = await _saveItem(
        _item.copyWith(
          visibility: ItemVisibility.household,
          householdId: householdId,
          sharedWithMemberUuids: const [],
        ),
      );
      if (error != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _pendingShared = null;
        });
      }
    }
  }

  Future<void> _shareWithAll() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final error = await _saveItem(
        _item.copyWith(
          visibility: ItemVisibility.household,
          sharedWithMemberUuids: const [],
        ),
      );
      if (error != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleMember(String memberUuid, bool selected) async {
    if (_isSaving) return;
    if (memberUuid == _itemOwnerMemberUuid) return;

    setState(() => _isSaving = true);
    try {
      final next = {..._normalizedSelectedMemberUuids()};
      if (selected) {
        next.add(memberUuid);
      } else {
        next.remove(memberUuid);
      }

      final error = await _saveItem(
        _item.copyWith(
          visibility: ItemVisibility.household,
          sharedWithMemberUuids: _normalizedSelectedMemberUuids(next),
        ),
      );
      if (error != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final membersAsync = ref.watch(householdMembersProvider);
    final hasHousehold = ref.watch(hasHouseholdProvider);
    final selectedMemberUuids = _normalizedSelectedMemberUuids();
    final allMembersSelected = selectedMemberUuids.isEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visibility',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isSaving
                          ? (_isShared ? 'Sharing…' : 'Removing…')
                          : _isShared
                              ? 'Shared'
                              : 'Private (Only visible to you)',
                      style: TextStyle(
                        color: _isShared ? AppColors.primary : textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Show a spinner next to the switch while cloud sync runs
              if (_isSaving)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              Switch.adaptive(
                value: _isShared,
                activeThumbColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                onChanged: _isSaving ||
                        (!hasHousehold && !_isShared) ||
                        (!_isShared && !_canShareWhileBackupState) ||
                        (_isShared && !_canChangeShareState)
                    ? null
                    : _toggleSharing,
              ),
            ],
          ),
          if (!_canShareWhileBackupState) ...[
            const SizedBox(height: 12),
            Text(
              _backupRequiredMessage,
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          if (_canShareWhileBackupState && !hasHousehold && !_isShared) ...[
            const SizedBox(height: 12),
            Text(
              'Private by default. Create a household in Family Sharing Pool settings to enable sharing.',
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: membersAsync.when(
                data: (members) => _VisibilityMembersList(
                  members: members,
                  itemOwnerMemberUuid: _itemOwnerMemberUuid,
                  selectedMemberUuids: selectedMemberUuids,
                  allMembersSelected: allMembersSelected,
                  isSaving: _isSaving,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  onShareWithAll: _shareWithAll,
                  onToggleMember: _toggleMember,
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                error: (error, _) => Text(
                  'Could not load household members: $error',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            crossFadeState: _isShared
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _VisibilityMembersList extends StatelessWidget {
  const _VisibilityMembersList({
    required this.members,
    required this.itemOwnerMemberUuid,
    required this.selectedMemberUuids,
    required this.allMembersSelected,
    required this.isSaving,
    required this.textPrimary,
    required this.textSecondary,
    required this.onShareWithAll,
    required this.onToggleMember,
  });

  final List<HouseholdMember> members;
  final String? itemOwnerMemberUuid;
  final List<String> selectedMemberUuids;
  final bool allMembersSelected;
  final bool isSaving;
  final Color textPrimary;
  final Color textSecondary;
  final Future<void> Function() onShareWithAll;
  final Future<void> Function(String memberUuid, bool selected) onToggleMember;

  @override
  Widget build(BuildContext context) {
    final selectableMembers = members
        .where(
          (member) =>
              member.uuid != HouseholdMember.localOwnerUuid &&
              member.uuid != itemOwnerMemberUuid,
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose who can see this item',
          style: TextStyle(
            color: textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Select specific family members, or keep "All Household Members" enabled. An empty selection list is stored as shared with everyone. The original item lister is always included.',
          style: TextStyle(
            color: textSecondary,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        _VisibilityOptionTile(
          title: 'All Household Members',
          subtitle: 'Everyone in the family pool can see this item.',
          value: allMembersSelected,
          enabled: !isSaving,
          onChanged: (_) => onShareWithAll(),
        ),
        if (selectableMembers.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Add more household members to share with specific people.',
            style: TextStyle(color: textSecondary, fontSize: 12),
          ),
        ] else
          ...selectableMembers.map(
            (member) => _VisibilityOptionTile(
              title: member.name,
              subtitle: ((member.email ?? '').trim().isNotEmpty)
                  ? member.email!
                  : 'Visible to this member only',
              value: selectedMemberUuids.contains(member.uuid),
              enabled: !isSaving,
              onChanged: (selected) =>
                  onToggleMember(member.uuid, selected ?? false),
            ),
          ),
      ],
    );
  }
}

class _VisibilityOptionTile extends StatelessWidget {
  const _VisibilityOptionTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: enabled ? onChanged : null,
      activeColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
    );
  }
}

enum ImageSourceOption { camera, gallery }

class _BorrowRequestTile extends StatelessWidget {
  const _BorrowRequestTile({
    required this.request,
    required this.textPrimary,
    required this.textSecondary,
    required this.onApprove,
    required this.onDeny,
  });

  final FirestoreBorrowRequest request;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final returnText = request.requestedReturnDate == null
        ? 'No return date suggested'
        : 'Wants it back by ${DateFormat('dd MMM').format(request.requestedReturnDate!)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.requesterName,
            style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(returnText,
              style: TextStyle(color: textSecondary, fontSize: 12)),
          if ((request.note ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '"${request.note!.trim()}"',
              style:
                  TextStyle(color: textSecondary, fontSize: 12, height: 1.35),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDeny,
                  child: const Text('Deny'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onApprove,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.filled,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: filled
              ? AppColors.primary
              : (isDark
                  ? AppColors.surfaceVariantDark
                  : AppColors.surfaceVariantLight),
          borderRadius: BorderRadius.circular(16),
          border: filled
              ? null
              : Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: filled ? Colors.white : AppColors.primary, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: filled
                    ? Colors.white
                    : (isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.title,
    required this.subtitle,
    required this.first,
    required this.tail,
  });

  final String title;
  final String subtitle;
  final bool first;
  final bool tail;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: first
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                ),
                if (tail)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailFab extends StatelessWidget {
  const _DetailFab();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: AppNavBar.fabBottom(context),
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () => context.push(AppRoutes.save),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  blurRadius: 28,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: const Icon(
              Icons.photo_camera,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}
