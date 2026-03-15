import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/item.dart';
import '../../providers/item_providers.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';

enum _FilterType { all, recent, location, tags }

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;
  _FilterType _activeFilter = _FilterType.all;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    // Push initial query into the provider after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(itemSearchQueryProvider.notifier).state = widget.initialQuery;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    ref.read(itemSearchQueryProvider.notifier).state = value;
  }

  void _clearQuery() {
    _controller.clear();
    ref.read(itemSearchQueryProvider.notifier).state = '';
  }

  List<Item> _applyFilter(List<Item> items) {
    switch (_activeFilter) {
      case _FilterType.recent:
        final sorted = [...items]
          ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
        return sorted;
      case _FilterType.all:
      case _FilterType.location:
      case _FilterType.tags:
        return items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Column(
        children: [
          _SearchHeader(
            controller: _controller,
            isDark: isDark,
            activeFilter: _activeFilter,
            onQueryChanged: _onQueryChanged,
            onClear: _clearQuery,
            onFilterSelected: (f) => setState(() => _activeFilter = f),
          ),
          Expanded(child: _ResultsList(isDark: isDark, applyFilter: _applyFilter)),
        ],
      ),
    );
  }
}

// ── Sticky header (back, title, search input, filter chips) ────────────────────

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.isDark,
    required this.activeFilter,
    required this.onQueryChanged,
    required this.onClear,
    required this.onFilterSelected,
  });

  final TextEditingController controller;
  final bool isDark;
  final _FilterType activeFilter;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final ValueChanged<_FilterType> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? AppColors.backgroundDark : AppColors.backgroundLight)
            .withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.primary.withValues(alpha: 0.10)
                : AppColors.primary.withValues(alpha: 0.10),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: back + title + more
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.spacingSm,
                AppDimensions.spacingSm,
                AppDimensions.spacingSm,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(
                      Icons.arrow_back,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Search Results',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: Icon(
                      Icons.more_vert,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                ],
              ),
            ),
            // Search input
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.spacingMd,
                AppDimensions.spacingSm,
                AppDimensions.spacingMd,
                0,
              ),
              child: _SearchInput(
                controller: controller,
                isDark: isDark,
                onChanged: onQueryChanged,
                onClear: onClear,
              ),
            ),
            // Filter chips
            const SizedBox(height: AppDimensions.spacingSm),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacingMd,
                ),
                children: _FilterType.values.map((f) {
                  return _FilterChip(
                    label: _filterLabel(f),
                    isActive: activeFilter == f,
                    isDark: isDark,
                    onTap: () => onFilterSelected(f),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingMd),
          ],
        ),
      ),
    );
  }

  static String _filterLabel(_FilterType f) {
    switch (f) {
      case _FilterType.all:
        return 'All';
      case _FilterType.recent:
        return 'Recent';
      case _FilterType.location:
        return 'Location';
      case _FilterType.tags:
        return 'Tags';
    }
  }
}

// ── Search input field ─────────────────────────────────────────────────────────

class _SearchInput extends StatelessWidget {
  const _SearchInput({
    required this.controller,
    required this.isDark,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppDimensions.inputHeight,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.primary.withValues(alpha: 0.07)
            : AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.20),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppDimensions.spacingMd),
          Icon(Icons.search, color: AppColors.primary, size: AppDimensions.iconMd),
          const SizedBox(width: AppDimensions.spacingSm),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
              decoration: InputDecoration(
                hintText: 'Search your saved world...',
                hintStyle: TextStyle(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  fontWeight: FontWeight.normal,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) {
              if (value.text.isEmpty) return const SizedBox(width: AppDimensions.spacingMd);
              return IconButton(
                onPressed: onClear,
                icon: Icon(
                  Icons.cancel,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: AppDimensions.spacingSm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingMd,
          vertical: AppDimensions.spacingXs + 2,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          border: isActive
              ? null
              : Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isActive
                    ? AppColors.onPrimary
                    : (isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more,
              size: 16,
              color: isActive
                  ? AppColors.onPrimary
                  : (isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Results list ───────────────────────────────────────────────────────────────

class _ResultsList extends ConsumerWidget {
  const _ResultsList({required this.isDark, required this.applyFilter});

  final bool isDark;
  final List<Item> Function(List<Item>) applyFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(searchResultsProvider);
    final query = ref.watch(itemSearchQueryProvider);

    return resultsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (err, _) => Center(
        child: Text(
          'Something went wrong',
          style: TextStyle(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
      ),
      data: (items) {
        final filtered = applyFilter(items);
        if (filtered.isEmpty) {
          return _EmptyState(query: query, isDark: isDark);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppDimensions.spacingMd),
          itemCount: filtered.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppDimensions.spacingMd),
          itemBuilder: (context, i) {
            final item = filtered[i];
            if (item.imagePaths.isNotEmpty) {
              return _RichResultCard(item: item, isDark: isDark);
            }
            return _CompactResultItem(item: item, isDark: isDark);
          },
        );
      },
    );
  }
}

// ── Rich result card (with photo thumbnail) ────────────────────────────────────

class _RichResultCard extends StatelessWidget {
  const _RichResultCard({required this.item, required this.isDark});

  final Item item;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.itemDetailPath(item.uuid)),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spacingMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: metadata + actions
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Saved timestamp
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: AppDimensions.iconSm,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _savedLabel(item.savedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spacingXs),
                    // Item name
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppDimensions.spacingSm),
                    // Location badge
                    if (item.locationName != null || item.locationFullPath != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.spacingSm,
                          vertical: AppDimensions.spacingXs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusSm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: AppDimensions.iconSm,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                item.locationName ??
                                    item.locationFullPath ??
                                    '',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppDimensions.spacingMd),
                    // Action buttons
                    Row(
                      children: [
                        _ActionButton(
                          icon: Icons.edit_outlined,
                          isDark: isDark,
                          onTap: () =>
                              context.push(AppRoutes.itemDetailPath(item.uuid)),
                        ),
                        const SizedBox(width: AppDimensions.spacingSm),
                        _ActionButton(
                          icon: Icons.bookmark_border,
                          isDark: isDark,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimensions.spacingMd),
              // Right: thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                child: SizedBox(
                  width: AppDimensions.thumbnailLarge + 8,
                  height: AppDimensions.thumbnailLarge + 8,
                  child: Image.file(
                    File(item.imagePaths.first),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _ThumbnailPlaceholder(isDark: isDark),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _savedLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Saved just now';
    if (diff.inMinutes < 60) return 'Saved ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Saved ${diff.inHours}h ago';
    if (diff.inDays < 7) return 'Saved ${diff.inDays}d ago';
    if (diff.inDays < 30) return 'Saved ${(diff.inDays / 7).floor()}w ago';
    return 'Saved ${(diff.inDays / 30).floor()}mo ago';
  }
}

// ── Compact result item (no photo) ────────────────────────────────────────────

class _CompactResultItem extends StatelessWidget {
  const _CompactResultItem({required this.item, required this.isDark});

  final Item item;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.itemDetailPath(item.uuid)),
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.spacingMd),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon container
            Container(
              width: AppDimensions.thumbnailSmall,
              height: AppDimensions.thumbnailSmall,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppDimensions.spacingMd),
            // Name + location
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.locationName != null || item.locationFullPath != null)
                    Text(
                      'Location: ${item.locationName ?? item.locationFullPath}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small action button ────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.spacingSm),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        ),
        child: Icon(icon, size: 20, color: AppColors.primary),
      ),
    );
  }
}

// ── Thumbnail placeholder ─────────────────────────────────────────────────────

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: AppDimensions.iconLg,
          color: isDark ? AppColors.textDisabledDark : AppColors.textDisabledLight,
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query, required this.isDark});

  final String query;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: AppDimensions.iconXl + 8,
            color: isDark ? AppColors.textDisabledDark : AppColors.textDisabledLight,
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          Text(
            query.isEmpty ? 'Start typing to search' : 'No results for "$query"',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          if (query.isNotEmpty) ...[
            const SizedBox(height: AppDimensions.spacingSm),
            Text(
              'Try a different name or location',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.textDisabledDark
                    : AppColors.textDisabledLight,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
