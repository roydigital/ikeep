import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/zone.dart';
import '../../providers/location_hierarchy_providers.dart';
import '../../providers/quick_add_zone_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';
import '../../widgets/app_action_button.dart';
import '../../widgets/quick_add_item_card.dart';

const _quickAddInstructionText =
    'Blank rows are ignored when saving. Rows with notes, tags, photos, or documents still need a name.';
const _quickAddZoneHelperText =
    'All items added here will be saved in this zone automatically.';

class QuickAddMultipleScreen extends ConsumerStatefulWidget {
  const QuickAddMultipleScreen({
    super.key,
    required this.zoneUuid,
  });

  final String zoneUuid;

  @override
  ConsumerState<QuickAddMultipleScreen> createState() =>
      _QuickAddMultipleScreenState();
}

class _QuickAddMultipleScreenState
    extends ConsumerState<QuickAddMultipleScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _rowKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zoneAsync = ref.watch(resolvedZoneProvider(widget.zoneUuid));
    final state = ref.watch(zoneQuickAddControllerProvider(widget.zoneUuid));

    _syncRowKeys(state);

    return PopScope(
      canPop: !state.hasUnsavedChanges && !state.isSaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || state.isSaving || !state.hasUnsavedChanges) {
          return;
        }
        final shouldPop = await _handleBackPressed(state);
        if (shouldPop && context.mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
        appBar: AppBar(
          title: const Text('Quick Add Multiple'),
          leading: IconButton(
            onPressed: state.isSaving
                ? null
                : () async {
                    final shouldPop = await _handleBackPressed(state);
                    if (shouldPop && context.mounted) {
                      context.pop();
                    }
                  },
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: zoneAsync.when(
          data: (zone) {
            if (zone == null) {
              return const _MissingZoneState();
            }
            return Column(
              children: [
                if (state.isSaving)
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: AppColors.primary,
                  ),
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      AppDimensions.spacingMd,
                      AppDimensions.spacingMd,
                      AppDimensions.spacingMd,
                      AppDimensions.spacingXxl,
                    ),
                    children: [
                      _ZoneSummaryCard(
                        zone: zone,
                        zoneUuid: widget.zoneUuid,
                        backupToCloud: state.backupToCloud,
                        isSaving: state.isSaving,
                      ),
                      const SizedBox(height: AppDimensions.spacingMd),
                      Text(
                        _quickAddInstructionText,
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spacingLg),
                      ...state.rows.asMap().entries.map((entry) {
                        final row = entry.value;
                        return Padding(
                          key: _rowKeys[row.id],
                          padding: const EdgeInsets.only(
                            bottom: AppDimensions.spacingMd,
                          ),
                          child: QuickAddItemCard(
                            zoneUuid: widget.zoneUuid,
                            row: row,
                            itemNumber: entry.key + 1,
                            canRemove: state.rows.length > 1,
                            showValidationError:
                                state.invalidRowIds.contains(row.id),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.spacingLg),
              child: Text(
                'Could not load this zone.\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        bottomNavigationBar: zoneAsync.maybeWhen(
          data: (zone) => zone == null
              ? null
              : _QuickAddFooter(
                  saveLabelCount: state.savableRowCount,
                  isSaving: state.isSaving,
                  onAddAnother: _handleAddAnother,
                  onSaveAll: () => _handleSave(zone),
                ),
          orElse: () => null,
        ),
      ),
    );
  }

  Future<void> _handleAddAnother() async {
    ref.read(zoneQuickAddControllerProvider(widget.zoneUuid).notifier).addRow();
    await Future<void>.delayed(Duration.zero);
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 220,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _handleSave(Zone zone) async {
    final outcome = await ref
        .read(zoneQuickAddControllerProvider(widget.zoneUuid).notifier)
        .saveAll(zone);
    if (!mounted) return;

    if (outcome.hasValidationErrors) {
      _showSnackBar(
        outcome.errorMessage ?? 'Some rows still need a name.',
        isError: true,
      );
      await _scrollToFirstInvalidRow(outcome.invalidRowIds);
      return;
    }

    if (outcome.hasError) {
      _showSnackBar(outcome.errorMessage!, isError: true);
      return;
    }

    final message = _successMessage(
      zoneName: zone.name,
      savedCount: outcome.savedCount,
      ignoredBlankCount: outcome.ignoredBlankCount,
    );
    if (mounted) {
      context.pop(message);
    }
  }

  Future<bool> _handleBackPressed(ZoneQuickAddState state) async {
    if (state.isSaving || !state.hasUnsavedChanges) {
      return true;
    }

    final discard = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Discard quick add draft?'),
            content: const Text(
              'Unsaved rows, photos, and documents in this draft will be removed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;

    if (!discard || !mounted) {
      return false;
    }

    await ref
        .read(zoneQuickAddControllerProvider(widget.zoneUuid).notifier)
        .discardDraft();
    return true;
  }

  Future<void> _scrollToFirstInvalidRow(Set<String> invalidRowIds) async {
    if (invalidRowIds.isEmpty) return;
    final firstInvalidId = invalidRowIds.first;
    final key = _rowKeys[firstInvalidId];
    final context = key?.currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    );
  }

  void _syncRowKeys(ZoneQuickAddState state) {
    for (final row in state.rows) {
      _rowKeys.putIfAbsent(row.id, GlobalKey.new);
    }
    final activeIds = state.rows.map((row) => row.id).toSet();
    _rowKeys.removeWhere((rowId, _) => !activeIds.contains(rowId));
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  String _successMessage({
    required String zoneName,
    required int savedCount,
    required int ignoredBlankCount,
  }) {
    final savedLabel = savedCount == 1 ? 'item' : 'items';
    final ignoredSuffix = ignoredBlankCount == 0
        ? ''
        : ' $ignoredBlankCount blank row${ignoredBlankCount == 1 ? '' : 's'} ignored.';
    return '$savedCount $savedLabel added to $zoneName.$ignoredSuffix';
  }
}

class _ZoneSummaryCard extends ConsumerWidget {
  const _ZoneSummaryCard({
    required this.zone,
    required this.zoneUuid,
    required this.backupToCloud,
    required this.isSaving,
  });

  final Zone zone;
  final String zoneUuid;
  final bool backupToCloud;
  final bool isSaving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingLg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: isDark ? 0.28 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            zone.name,
            style: TextStyle(
              color: textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingXs),
          Text(
            _locationLine(zone),
            style: TextStyle(
              color: Color.lerp(
                  textSecondary, AppColors.primary, isDark ? 0.12 : 0.18),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingSm),
          Text(
            _quickAddZoneHelperText,
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingMd,
              vertical: AppDimensions.spacingSm,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceVariantDark
                  : AppColors.surfaceVariantLight,
              borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
              border: Border.all(
                color:
                    AppColors.primary.withValues(alpha: isDark ? 0.24 : 0.10),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Backup to Cloud',
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spacingXs),
                      Text(
                        backupToCloud
                            ? 'New items will join the normal backup queue after local save.'
                            : 'New items will stay local until you choose cloud backup later.',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: backupToCloud,
                  activeThumbColor: AppColors.primaryDark,
                  activeTrackColor: AppColors.primaryLight,
                  onChanged: isSaving
                      ? null
                      : (enabled) async {
                          final message = await ref
                              .read(
                                zoneQuickAddControllerProvider(zoneUuid)
                                    .notifier,
                              )
                              .setBackupToCloud(enabled);
                          if (message != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(message),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _locationLine(Zone zone) {
    final parts = <String>[
      if (zone.areaName?.trim().isNotEmpty == true) zone.areaName!.trim(),
      if (zone.roomName?.trim().isNotEmpty == true) zone.roomName!.trim(),
      zone.name,
    ];
    return parts.join(' > ');
  }
}

class _QuickAddFooter extends StatelessWidget {
  const _QuickAddFooter({
    required this.saveLabelCount,
    required this.isSaving,
    required this.onAddAnother,
    required this.onSaveAll,
  });

  final int saveLabelCount;
  final bool isSaving;
  final VoidCallback onAddAnother;
  final VoidCallback onSaveAll;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final systemBottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final footerSafeBottomInset = keyboardInset > 0 ? 0.0 : systemBottomInset;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          AppDimensions.spacingMd,
          AppDimensions.spacingSm,
          AppDimensions.spacingMd,
          AppDimensions.spacingMd + footerSafeBottomInset,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          border: Border(
            top: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.10),
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.surfaceVariantDark.withValues(alpha: 0.50)
                : AppColors.primary.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.10),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppActionButton(
                isDark: isDark,
                isPrimary: true,
                icon: Icons.add_rounded,
                label: 'Add Another Item',
                labelMaxLines: 1,
                minHeight: 56,
                onPressed: isSaving ? null : onAddAnother,
                trailing: Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: AppColors.onPrimary,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingSm),
              AppActionButton(
                isDark: isDark,
                isPrimary: false,
                icon: Icons.save_outlined,
                label: saveLabelCount == 0
                    ? 'Save All'
                    : 'Save All ($saveLabelCount)',
                labelMaxLines: 1,
                minHeight: 56,
                isLoading: isSaving,
                onPressed: isSaving || saveLabelCount == 0 ? null : onSaveAll,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingZoneState extends StatelessWidget {
  const _MissingZoneState();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_searching_outlined,
              size: 44,
              color: isDark
                  ? AppColors.textDisabledDark
                  : AppColors.textDisabledLight,
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            Text(
              'This zone could not be found.',
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingXs),
            Text(
              'Go back to Rooms & Zones and reopen the zone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
