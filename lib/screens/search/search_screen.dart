import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../core/constants/feature_limits.dart';
import '../../domain/models/item.dart';
import '../../domain/models/location_model.dart';
import '../../domain/models/shared_item.dart';
import '../../domain/models/zone.dart';
import '../../providers/history_providers.dart';
import '../../providers/home_tour_provider.dart';
import '../../providers/household_providers.dart';
import '../../providers/main_tab_provider.dart';
import '../../providers/item_providers.dart';
import '../../providers/location_hierarchy_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/repository_providers.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';
import '../../widgets/adaptive_image.dart';
import '../../widgets/app_action_button.dart';
import '../../widgets/app_nav_bar.dart';
import '../../widgets/app_showcase.dart';

enum _FilterType { all, recent, location, tags }

Color _searchResultLocationColor(bool isDark) {
  return isDark ? AppColors.secondary : AppColors.primaryDark;
}

Color _searchResultLocationBackground(bool isDark) {
  return isDark
      ? AppColors.secondary.withValues(alpha: 0.12)
      : AppColors.primary.withValues(alpha: 0.08);
}

Color _searchResultDetailColor(bool isDark) {
  return Color.lerp(
    isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
    isDark ? AppColors.primaryLight : AppColors.primary,
    isDark ? 0.12 : 0.08,
  )!;
}

Widget _buildListingTourStep({
  required GlobalKey showcaseKey,
  required String title,
  required String description,
  required Widget child,
  TooltipPosition? tooltipPosition,
}) {
  return Showcase(
    key: showcaseKey,
    title: title,
    description: description,
    tooltipPosition: tooltipPosition,
    tooltipBackgroundColor: AppColors.surfaceDark,
    textColor: AppColors.textPrimaryDark,
    titleTextStyle: const TextStyle(
      color: AppColors.textPrimaryDark,
      fontSize: 18,
      fontWeight: FontWeight.w800,
    ),
    descTextStyle: const TextStyle(
      color: AppColors.textSecondaryDark,
      fontSize: 14,
      height: 1.45,
    ),
    tooltipBorderRadius: BorderRadius.circular(AppDimensions.radiusLg),
    targetBorderRadius: BorderRadius.circular(AppDimensions.radiusLg),
    targetPadding: const EdgeInsets.all(6),
    overlayOpacity: 0.78,
    disableDefaultTargetGestures: true,
    child: child,
  );
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    this.initialQuery = '',
    this.startInHouseholdMode = false,
    this.initialLocationUuid,
    this.isEmbedded = false,
  });

  final String initialQuery;
  final bool startInHouseholdMode;

  /// When set, the screen opens pre-filtered to this location UUID.
  /// Accepts any level: area, room, or zone UUID.
  final String? initialLocationUuid;

  /// True when this screen is embedded inside [MainScreen]'s [PageView].
  /// Hides the back arrow and adds bottom padding for the fixed nav bar.
  final bool isEmbedded;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;
  final GlobalKey _searchInputShowcaseKey = GlobalKey();
  final GlobalKey _filterShowcaseKey = GlobalKey();
  final GlobalKey _resultsShowcaseKey = GlobalKey();
  _FilterType _activeFilter = _FilterType.all;

  // Location filter — two parallel fields:
  // _selectedLocationPath  → display string shown in the chip label
  // _selectedLocationUuid  → UUID used for precise FK-based filtering
  // Both are set together in _onLocationSelected.
  String? _selectedLocationPath;
  String? _selectedLocationUuid;

  // Cached from the last allLocationsProvider resolution.
  // Used for reverse-lookup (display path → UUID) in _onLocationSelected,
  // and for forward-lookup (UUID → path) when initialLocationUuid is applied.
  List<LocationModel> _cachedLocationModels = [];
  bool _initialLocationApplied = false;

  String? _selectedTag;
  late bool _isHouseholdMode;
  bool _itemListingTourQueued = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _isHouseholdMode = false;
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

  void _onPrimaryFilterSelected(_FilterType filter) {
    setState(() {
      _activeFilter = filter;
    });
  }

  void _onLocationSelected(String? locationPath) {
    setState(() {
      _selectedLocationPath = locationPath;
      // Reverse-lookup the UUID from the cached list so _applyFilter can
      // use precise FK matching instead of fragile string comparison.
      if (locationPath == null) {
        _selectedLocationUuid = null;
      } else {
        final match = _cachedLocationModels.where((l) {
          return (l.fullPath ?? l.name).trim() == locationPath.trim();
        }).firstOrNull;
        _selectedLocationUuid = match?.uuid;
      }
      _activeFilter =
          locationPath == null ? _FilterType.all : _FilterType.location;
    });
  }

  void _onTagSelected(String? tag) {
    setState(() {
      _selectedTag = tag;
      _activeFilter = tag == null ? _FilterType.all : _FilterType.tags;
    });
  }

  Future<void> _openNormalSaveForZone(String zoneUuid) async {
    await context.push(
      AppRoutes.save,
      extra: {'initialZoneUuid': zoneUuid},
    );
  }

  Future<void> _openQuickAddForZone(String zoneUuid) async {
    final message = await context.push<String>(
      AppRoutes.zoneQuickAddPath(zoneUuid),
    );
    if (!mounted || message == null || message.trim().isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _startItemListingTour(BuildContext context) {
    if (_itemListingTourQueued) return;
    _itemListingTourQueued = true;

    ShowCaseWidget.of(context).startShowCase([
      _searchInputShowcaseKey,
      _filterShowcaseKey,
      _resultsShowcaseKey,
    ]);

    ref.read(itemListingTourControllerProvider.notifier).markSeen();
  }

  List<Item> _applyFilter(List<Item> items) {
    var filtered = [...items];

    switch (_activeFilter) {
      case _FilterType.recent:
        filtered.sort((a, b) => b.savedAt.compareTo(a.savedAt));
        return filtered;
      case _FilterType.all:
        return filtered;
      case _FilterType.location:
        if (_selectedLocationPath == null) return filtered;
        return filtered.where((item) {
          // UUID-first: check zoneUuid / locationUuid against the selected UUID
          if (_selectedLocationUuid != null) {
            if (item.zoneUuid == _selectedLocationUuid) return true;
            if (item.areaUuid == _selectedLocationUuid) return true;
            if (item.roomUuid == _selectedLocationUuid) return true;
            if (item.locationUuid == _selectedLocationUuid) return true;
          }
          // String fallback for legacy items that have no UUID set yet.
          final displayPath =
              (item.locationName ?? item.locationFullPath ?? '').trim();
          return displayPath == _selectedLocationPath;
        }).toList();
      case _FilterType.tags:
        if (_selectedTag == null) return filtered;
        return filtered.where((item) {
          return item.tags.any((tag) => tag.trim() == _selectedTag);
        }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locationOptionsAsync = ref.watch(allLocationsProvider);
    final tagOptionsAsync = ref.watch(itemTagsProvider);
    final hasSeenItemListingTour = ref.watch(itemListingTourControllerProvider);
    // Only start the tour when the Search tab (index 2) is actually visible.
    final activeTab = ref.watch(mainTabProvider);

    // Sync external query changes (e.g. voice search from Home) into the
    // TextEditingController so the text field and provider stay in sync.
    ref.listen<String>(itemSearchQueryProvider, (prev, next) {
      if (_controller.text != next) {
        _controller.text = next;
        _controller.selection = TextSelection.collapsed(offset: next.length);
      }
    });

    // Handle "View All" from Home → switch to Recent filter and show items.
    ref.listen<bool>(viewAllRecentRequestedProvider, (prev, next) {
      if (next) {
        ref.read(viewAllRecentRequestedProvider.notifier).state = false;
        _controller.clear();
        ref.read(itemSearchQueryProvider.notifier).state = '';
        setState(() {
          _activeFilter = _FilterType.recent;
          _selectedLocationPath = null;
          _selectedLocationUuid = null;
          _selectedTag = null;
        });
      }
    });

    final locationOptions = locationOptionsAsync.maybeWhen(
      data: (locations) {
        // Cache the raw models for UUID reverse-lookup and initial-filter apply.
        _cachedLocationModels = locations;

        // Apply initialLocationUuid once, after the first data load.
        if (!_initialLocationApplied && widget.initialLocationUuid != null) {
          _initialLocationApplied = true;
          final match = locations.firstWhere(
            (l) => l.uuid == widget.initialLocationUuid,
            orElse: () => locations.first,
          );
          // Only apply if a real match was found.
          if (match.uuid == widget.initialLocationUuid) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _selectedLocationPath = (match.fullPath ?? match.name).trim();
                _selectedLocationUuid = match.uuid;
                _activeFilter = _FilterType.location;
              });
            });
          }
        }

        final labels = locations
            .map((location) => (location.fullPath ?? location.name).trim())
            .where((label) => label.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        return labels;
      },
      orElse: () => const <String>[],
    );
    final tagOptions = tagOptionsAsync.maybeWhen(
      data: (tags) => tags,
      orElse: () => const <String>[],
    );
    final shouldAutofocusSearch = hasSeenItemListingTour.valueOrNull == true;
    final selectedLocationModel = _selectedLocationUuid == null
        ? null
        : _cachedLocationModels
            .where((location) => location.uuid == _selectedLocationUuid)
            .firstOrNull;
    final selectedZoneUuid =
        selectedLocationModel?.type == LocationType.zone
            ? selectedLocationModel!.uuid
            : null;
    final selectedZoneAsync = selectedZoneUuid == null
        ? const AsyncValue<Zone?>.data(null)
        : ref.watch(resolvedZoneProvider(selectedZoneUuid));

    return ShowCaseWidget(
      blurValue: 1.5,
      enableAutoScroll: true,
      globalTooltipActionConfig: appShowcaseTooltipActionConfig,
      globalTooltipActions: appShowcaseTooltipActions(),
      builder: (tourContext) {
        if (activeTab == AppNavTab.search.index &&
            hasSeenItemListingTour.valueOrNull == false &&
            !_itemListingTourQueued) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _itemListingTourQueued) return;
            _startItemListingTour(tourContext);
          });
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              _SearchHeader(
                controller: _controller,
                isDark: isDark,
                isHouseholdMode: false,
                isSignedIn: false,
                activeFilter: _activeFilter,
                selectedLocation: _selectedLocationPath,
                selectedTag: _selectedTag,
                locationOptions: locationOptions,
                tagOptions: tagOptions,
                searchShowcaseKey: _searchInputShowcaseKey,
                filterShowcaseKey: _filterShowcaseKey,
                shouldAutofocusSearch: shouldAutofocusSearch,
                onQueryChanged: _onQueryChanged,
                onClear: _clearQuery,
                onFilterSelected: _onPrimaryFilterSelected,
                onLocationSelected: _onLocationSelected,
                onTagSelected: _onTagSelected,
                onModeChanged: (_) {},
                showBackButton: !widget.isEmbedded,
              ),
              Expanded(
                child: _ResultsList(
                  isDark: isDark,
                  applyFilter: _applyFilter,
                  activeFilter: _activeFilter,
                  resultsShowcaseKey: _resultsShowcaseKey,
                  bottomPadding: widget.isEmbedded
                      ? AppNavBar.contentBottomSpacing(context)
                      : MediaQuery.paddingOf(context).bottom,
                  header: selectedZoneUuid == null
                      ? null
                      : _ZoneContextBanner(
                          isDark: isDark,
                          zoneAsync: selectedZoneAsync,
                          onAddItemHere: () =>
                              _openNormalSaveForZone(selectedZoneUuid),
                          onQuickAddMultiple: () =>
                              _openQuickAddForZone(selectedZoneUuid),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ZoneContextBanner extends StatelessWidget {
  const _ZoneContextBanner({
    required this.isDark,
    required this.zoneAsync,
    required this.onAddItemHere,
    required this.onQuickAddMultiple,
  });

  final bool isDark;
  final AsyncValue<Zone?> zoneAsync;
  final VoidCallback onAddItemHere;
  final VoidCallback onQuickAddMultiple;

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final background = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return zoneAsync.when(
      data: (zone) {
        if (zone == null) {
          return const SizedBox.shrink();
        }
        final locationLine = <String>[
          if (zone.areaName?.trim().isNotEmpty == true) zone.areaName!.trim(),
          if (zone.roomName?.trim().isNotEmpty == true) zone.roomName!.trim(),
          zone.name,
        ].join(' > ');

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDimensions.spacingMd),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                zone.name,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingXs),
              Text(
                locationLine,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingSm),
              Text(
                'All items added here will be saved in this zone automatically.',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingMd),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceVariantDark.withValues(alpha: 0.50)
                      : AppColors.primary.withValues(alpha: 0.045),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
                  border: Border.all(
                    color: AppColors.primary.withValues(
                      alpha: isDark ? 0.22 : 0.10,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: AppActionButton(
                        isDark: isDark,
                        isPrimary: true,
                        icon: Icons.add_rounded,
                        label: 'Add Item Here',
                        onPressed: onAddItemHere,
                        trailing: Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: AppColors.onPrimary.withValues(alpha: 0.94),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingSm),
                    SizedBox(
                      width: double.infinity,
                      child: AppActionButton(
                        isDark: isDark,
                        isPrimary: false,
                        icon: Icons.playlist_add_rounded,
                        label: 'Quick Add Multiple',
                        onPressed: onQuickAddMultiple,
                        trailing: Icon(
                          Icons.north_east_rounded,
                          size: 16,
                          color: (isDark
                                  ? AppColors.primaryLight
                                  : AppColors.primary)
                              .withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppDimensions.spacingMd),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        ),
        child: const LinearProgressIndicator(color: AppColors.primary),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ── Sticky header (back, title, search input, filter chips) ────────────────────

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.isDark,
    required this.isHouseholdMode,
    required this.isSignedIn,
    required this.activeFilter,
    required this.selectedLocation,
    required this.selectedTag,
    required this.locationOptions,
    required this.tagOptions,
    required this.searchShowcaseKey,
    required this.filterShowcaseKey,
    required this.shouldAutofocusSearch,
    required this.onQueryChanged,
    required this.onClear,
    required this.onFilterSelected,
    required this.onLocationSelected,
    required this.onTagSelected,
    required this.onModeChanged,
    this.showBackButton = true,
  });

  final TextEditingController controller;
  final bool isDark;
  final bool isHouseholdMode;
  final bool isSignedIn;
  final _FilterType activeFilter;
  final String? selectedLocation;
  final String? selectedTag;
  final List<String> locationOptions;
  final List<String> tagOptions;
  final GlobalKey searchShowcaseKey;
  final GlobalKey filterShowcaseKey;
  final bool shouldAutofocusSearch;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final ValueChanged<_FilterType> onFilterSelected;
  final ValueChanged<String?> onLocationSelected;
  final ValueChanged<String?> onTagSelected;
  final ValueChanged<bool> onModeChanged;
  final bool showBackButton;

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
            // Top row: back + title
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.spacingSm,
                AppDimensions.spacingSm,
                AppDimensions.spacingSm,
                0,
              ),
              child: Row(
                children: [
                  if (showBackButton)
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
              child: _buildListingTourStep(
                showcaseKey: searchShowcaseKey,
                title: 'Search Your Items',
                description:
                    'Type a name, tag, or location to narrow the list instantly.',
                tooltipPosition: TooltipPosition.bottom,
                child: _SearchInput(
                  controller: controller,
                  isDark: isDark,
                  shouldAutofocus: shouldAutofocusSearch,
                  onChanged: onQueryChanged,
                  onClear: onClear,
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            _buildListingTourStep(
              showcaseKey: filterShowcaseKey,
              title: 'Refine the List',
              description:
                  'Use these quick filters to jump to recent items or narrow the list by location and tags.',
              tooltipPosition: TooltipPosition.bottom,
              child: SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingMd,
                  ),
                  children: _FilterType.values.map((f) {
                    if (f == _FilterType.location) {
                      return _DropdownFilterChip(
                        label: selectedLocation == null
                            ? 'Location'
                            : 'Location: $selectedLocation',
                        isActive: activeFilter == f,
                        isDark: isDark,
                        options: locationOptions,
                        allOptionLabel: 'All locations',
                        onSelected: onLocationSelected,
                        onActivated: () =>
                            onFilterSelected(_FilterType.location),
                      );
                    }

                    if (f == _FilterType.tags) {
                      return _DropdownFilterChip(
                        label:
                            selectedTag == null ? 'Tags' : 'Tag: $selectedTag',
                        isActive: activeFilter == f,
                        isDark: isDark,
                        options: tagOptions,
                        allOptionLabel: 'All tags',
                        onSelected: onTagSelected,
                        onActivated: () => onFilterSelected(_FilterType.tags),
                      );
                    }

                    return _FilterChip(
                      label: _filterLabel(f),
                      isActive: activeFilter == f,
                      isDark: isDark,
                      onTap: () => onFilterSelected(f),
                    );
                  }).toList(),
                ),
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
    required this.shouldAutofocus,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool isDark;
  final bool shouldAutofocus;
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
          Icon(Icons.search,
              color: AppColors.primary, size: AppDimensions.iconMd),
          const SizedBox(width: AppDimensions.spacingSm),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: shouldAutofocus,
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
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isCollapsed: true,
                isDense: true,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) {
              if (value.text.isEmpty) {
                return const SizedBox(width: AppDimensions.spacingMd);
              }
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: AppDimensions.spacingSm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingMd,
          vertical: AppDimensions.spacingXs + 3,
        ),
        decoration: BoxDecoration(
          gradient: isActive ? AppColors.primaryGradient : null,
          color: isActive
              ? null
              : AppColors.primary.withValues(alpha: isDark ? 0.1 : 0.06),
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          border: isActive
              ? null
              : Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18),
                ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
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

class _DropdownFilterChip extends StatelessWidget {
  const _DropdownFilterChip({
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.options,
    required this.allOptionLabel,
    required this.onSelected,
    required this.onActivated,
  });

  static const _allOptionValue = '__all__';

  final String label;
  final bool isActive;
  final bool isDark;
  final List<String> options;
  final String allOptionLabel;
  final ValueChanged<String?> onSelected;
  final VoidCallback onActivated;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onOpened: onActivated,
      onSelected: (value) {
        if (value == _allOptionValue) {
          onSelected(null);
          return;
        }
        onSelected(value);
      },
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: _allOptionValue,
            child: Text(allOptionLabel),
          ),
        ];

        if (options.isEmpty) {
          items.add(
            const PopupMenuItem<String>(
              enabled: false,
              value: '',
              child: Text('No options available'),
            ),
          );
        } else {
          items.addAll(
            options.map(
              (option) => PopupMenuItem<String>(
                value: option,
                child: Text(option, overflow: TextOverflow.ellipsis),
              ),
            ),
          );
        }

        return items;
      },
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
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
                overflow: TextOverflow.ellipsis,
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

// ── My Inventory results list ─────────────────────────────────────────────────

class _ResultsList extends ConsumerStatefulWidget {
  const _ResultsList({
    required this.isDark,
    required this.applyFilter,
    required this.activeFilter,
    required this.resultsShowcaseKey,
    this.bottomPadding = 0,
    this.header,
  });

  final bool isDark;
  final List<Item> Function(List<Item>) applyFilter;
  final _FilterType activeFilter;
  final GlobalKey resultsShowcaseKey;

  /// Extra bottom padding when embedded in MainScreen (accounts for fixed nav bar).
  final double bottomPadding;

  /// Optional widget pinned at the top of the scroll view (e.g. zone banner).
  /// Kept inside the scroll view so it cannot fight the keyboard for fixed
  /// height, which previously caused a vertical overflow when the keyboard
  /// opened over the zone-filtered search screen.
  final Widget? header;

  @override
  ConsumerState<_ResultsList> createState() => _ResultsListState();
}

class _ResultsListState extends ConsumerState<_ResultsList> {
  static const int _pageSize = 10;
  static const double _loadMoreThreshold = 240;

  late final ScrollController _scrollController;
  final List<Item> _lazyItems = <Item>[];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  Object? _loadingError;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshLazyItems();
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ResultsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeFilter != widget.activeFilter) {
      _refreshLazyItems();
    }
  }

  Future<void> _refreshLazyItems() async {
    final query = ref.read(itemSearchQueryProvider);
    _lastQuery = query;
    if (!_usesLazyLoading(widget.activeFilter, query)) {
      if (!mounted) return;
      setState(() {
        _lazyItems.clear();
        _isInitialLoading = false;
        _isLoadingMore = false;
        _hasMore = true;
        _loadingError = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _lazyItems.clear();
      _isInitialLoading = true;
      _isLoadingMore = false;
      _hasMore = true;
      _loadingError = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final query = ref.read(itemSearchQueryProvider);
    if (!_usesLazyLoading(widget.activeFilter, query) ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingMore = true;
        _loadingError = null;
      });
    }

    try {
      final nextPage = await ref.read(itemRepositoryProvider).getItemsPage(
            limit: _pageSize,
            offset: _lazyItems.length,
          );
      if (!mounted) return;
      setState(() {
        _lazyItems.addAll(nextPage);
        _hasMore = nextPage.length == _pageSize;
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingError = error;
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final query = ref.read(itemSearchQueryProvider);
    if (!_usesLazyLoading(widget.activeFilter, query)) return;
    final position = _scrollController.position;
    if (position.extentAfter > _loadMoreThreshold) return;
    _loadMore();
  }

  bool _usesLazyLoading(_FilterType activeFilter, String query) {
    return query.trim().isEmpty &&
        activeFilter != _FilterType.location &&
        activeFilter != _FilterType.tags;
  }

  EdgeInsets _resultsListPadding() {
    return EdgeInsets.fromLTRB(
      AppDimensions.spacingMd,
      AppDimensions.spacingSm,
      AppDimensions.spacingMd,
      AppDimensions.spacingMd + widget.bottomPadding,
    );
  }

  Widget _buildResultsShowcaseAnchor() {
    return _buildListingTourStep(
      showcaseKey: widget.resultsShowcaseKey,
      title: 'Browse Everything',
      description:
          'Your items appear here. Open any card to view details, edit information, or jump back to where it is stored.',
      tooltipPosition: TooltipPosition.bottom,
      child: const SizedBox(
        height: 1,
        width: double.infinity,
      ),
    );
  }

  Widget _buildResultsState(Widget child) {
    return ListView(
      controller: _scrollController,
      padding: _resultsListPadding(),
      children: [
        if (widget.header != null) widget.header!,
        _buildResultsShowcaseAnchor(),
        const SizedBox(height: AppDimensions.spacingSm),
        child,
      ],
    );
  }

  Widget _buildResultsListView(
    List<Item> filtered, {
    bool isLoadingMore = false,
  }) {
    final hasHeader = widget.header != null;
    final headerOffset = hasHeader ? 1 : 0;
    final showcaseIndex = headerOffset; // 0 or 1
    final firstItemIndex = showcaseIndex + 1;

    return ListView.separated(
      controller: _scrollController,
      padding: _resultsListPadding(),
      itemCount:
          filtered.length + (isLoadingMore ? 1 : 0) + 1 + headerOffset,
      separatorBuilder: (_, index) => SizedBox(
        height: index == showcaseIndex
            ? AppDimensions.spacingSm
            : AppDimensions.spacingMd,
      ),
      itemBuilder: (context, i) {
        if (hasHeader && i == 0) {
          return widget.header!;
        }
        if (i == showcaseIndex) {
          // Keep the showcase target inside the results scroll view so it
          // does not reserve a fixed blank strip below the header.
          return _buildResultsShowcaseAnchor();
        }

        final resultIndex = i - firstItemIndex;
        if (isLoadingMore && resultIndex >= filtered.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppDimensions.spacingSm),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final item = filtered[resultIndex];
        if (item.imagePaths.isNotEmpty) {
          return _RichResultCard(item: item, isDark: widget.isDark);
        }
        return _CompactResultItem(item: item, isDark: widget.isDark);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(itemSearchQueryProvider);
    if (query != _lastQuery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshLazyItems();
        }
      });
    }
    final useLazyLoading = _usesLazyLoading(widget.activeFilter, query);

    if (useLazyLoading) {
      if (_isInitialLoading) {
        return _buildResultsState(const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ));
      }
      if (_loadingError != null && _lazyItems.isEmpty) {
        return _buildResultsState(Center(
          child: Text(
            'Something went wrong',
            style: TextStyle(
              color: widget.isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
        ));
      }

      final filtered = widget.applyFilter(_lazyItems);
      if (filtered.isEmpty) {
        return _buildResultsState(_EmptyState(
          query: query,
          isDark: widget.isDark,
          isHouseholdMode: false,
        ));
      }

      return _buildResultsListView(filtered, isLoadingMore: _isLoadingMore);
    }

    final sourceItemsAsync = ref.watch(allItemsProvider);

    return sourceItemsAsync.when(
      loading: () => _buildResultsState(const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      )),
      error: (err, _) => _buildResultsState(Center(
        child: Text(
          'Something went wrong',
          style: TextStyle(
            color: widget.isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
      )),
      data: (items) {
        final queryLower = query.trim().toLowerCase();
        final queryFiltered = queryLower.isEmpty
            ? items
            : items.where((item) {
                final tags = item.tags.join(' ').toLowerCase();
                final location =
                    '${item.locationName ?? ''} ${item.locationFullPath ?? ''}'
                        .toLowerCase();
                return item.name.toLowerCase().contains(queryLower) ||
                    tags.contains(queryLower) ||
                    location.contains(queryLower);
              }).toList();
        final filtered = widget.applyFilter(queryFiltered);
        if (filtered.isEmpty) {
          return _buildResultsState(_EmptyState(
            query: query,
            isDark: widget.isDark,
            isHouseholdMode: false,
          ));
        }
        return _buildResultsListView(filtered);
      },
    );
  }
}

// ── Household shared items results list ───────────────────────────────────────

class _HouseholdResultsList extends ConsumerWidget {
  const _HouseholdResultsList({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(itemSearchQueryProvider);
    final sharedItemsAsync = ref.watch(householdSharedItemsProvider);

    return sharedItemsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (err, _) => Center(
        child: Text(
          'Could not load household items',
          style: TextStyle(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
      ),
      data: (sharedItems) {
        // Apply search filter on shared items
        final queryLower = query.trim().toLowerCase();
        final filtered = queryLower.isEmpty
            ? sharedItems
            : sharedItems.where((si) {
                final tags = si.tags.join(' ').toLowerCase();
                return si.name.toLowerCase().contains(queryLower) ||
                    si.locationName.toLowerCase().contains(queryLower) ||
                    si.ownerName.toLowerCase().contains(queryLower) ||
                    tags.contains(queryLower);
              }).toList();

        if (filtered.isEmpty) {
          return _EmptyState(
            query: query,
            isDark: isDark,
            isHouseholdMode: true,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(AppDimensions.spacingMd),
          itemCount: filtered.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppDimensions.spacingMd),
          itemBuilder: (context, i) =>
              _SharedItemCard(item: filtered[i], isDark: isDark),
        );
      },
    );
  }
}

// ── Mode switcher (My Inventory / Household) ──────────────────────────────────

class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({
    required this.isDark,
    required this.isHouseholdMode,
    required this.isSignedIn,
    required this.onChanged,
  });

  final bool isDark;
  final bool isHouseholdMode;
  final bool isSignedIn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final background =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModePill(
              label: 'My Inventory',
              subtitle: 'Everything you saved',
              active: !isHouseholdMode,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _ModePill(
              label: 'Household',
              subtitle:
                  isSignedIn ? 'Items shared by members' : 'Sign in to access',
              active: isHouseholdMode,
              onTap: isSignedIn ? () => onChanged(true) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.subtitle,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? Colors.white70 : AppColors.textSecondaryLight,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared item card (Household tab) ──────────────────────────────────────────

class _SharedItemCard extends ConsumerWidget {
  const _SharedItemCard({
    required this.item,
    required this.isDark,
  });

  final SharedItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAvailable = item.isAvailable;

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Owner row
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  item.ownerName.isNotEmpty
                      ? item.ownerName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.ownerName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ),
              // Availability badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isAvailable
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                ),
                child: Text(
                  isAvailable ? 'Available' : 'Lent out',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isAvailable ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingSm),
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
          // Location
          if (item.locationName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: AppDimensions.iconSm,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    item.locationName,
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
          ],
          // Tags
          if (item.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: item.tags.take(5).map((tag) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusFull),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          // Lent info
          if (!isAvailable && item.lentToName != null) ...[
            const SizedBox(height: 6),
            Text(
              'Lent to ${item.lentToName}'
              '${item.expectedReturnDate != null ? ' — return by ${DateFormat('dd MMM').format(item.expectedReturnDate!)}' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: AppDimensions.spacingMd),
          // Action button
          SizedBox(
            width: double.infinity,
            child: isAvailable
                ? FilledButton.icon(
                    onPressed: () =>
                        _showBorrowRequestSheet(context, ref, item),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    icon: const Icon(Icons.handshake_outlined, size: 18),
                    label: const Text('Request to Borrow'),
                  )
                : OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.hourglass_top, size: 18),
                    label: const Text('Currently unavailable'),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Borrow request bottom sheet (Household tab) ──────────────────────────────

Future<void> _showBorrowRequestSheet(
  BuildContext context,
  WidgetRef ref,
  SharedItem item,
) async {
  final noteController = TextEditingController();
  DateTime? requestedReturnDate;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 18,
              ),
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
                    'Request to Borrow',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${item.name} — from ${item.ownerName}',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    maxLines: 3,
                    maxLength: itemNotesMaxLength,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(itemNotesMaxLength),
                    ],
                    buildCounter: (context,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        null,
                    decoration: const InputDecoration(
                      hintText: 'Optional note — tell them why you need it.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: requestedReturnDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked == null) return;
                      setSheetState(() => requestedReturnDate = picked);
                    },
                    icon: const Icon(Icons.event_available),
                    label: Text(
                      requestedReturnDate == null
                          ? 'Suggest a return date'
                          : 'Return by ${DateFormat('dd MMM yyyy').format(requestedReturnDate!)}',
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      child: const Text('Send request'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ) ??
      false;

  final note = noteController.text.trim();
  noteController.dispose();
  if (!confirmed) return;

  // Send borrow request via Firestore through HouseholdNotifier
  final error =
      await ref.read(householdNotifierProvider.notifier).requestToBorrow(
            item: item,
            requestedReturnDate: requestedReturnDate,
            note: note.isEmpty ? null : note,
          );

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error ?? 'Borrow request sent!'),
      backgroundColor: error == null ? AppColors.success : AppColors.error,
    ),
  );
}

// ── Rich result card (with photo thumbnail — My Inventory) ──────────────────

class _RichResultCard extends ConsumerWidget {
  const _RichResultCard({
    required this.item,
    required this.isDark,
  });

  final Item item;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestHistoryAsync = ref.watch(itemLatestHistoryProvider(item.uuid));
    final locationColor = _searchResultLocationColor(isDark);
    final detailColor = _searchResultDetailColor(isDark);
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
              // Left: metadata
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
                    if (item.locationName != null ||
                        item.locationFullPath != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.spacingSm,
                          vertical: AppDimensions.spacingXs,
                        ),
                        decoration: BoxDecoration(
                          color: _searchResultLocationBackground(isDark),
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusSm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: AppDimensions.iconSm,
                              color: locationColor,
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
                                ).copyWith(color: locationColor),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppDimensions.spacingSm),
                    latestHistoryAsync.when(
                      data: (entry) {
                        if (entry == null) return const SizedBox.shrink();
                        final who =
                            (entry.movedByName?.trim().isNotEmpty ?? false)
                                ? entry.movedByName!
                                : 'Someone';
                        return Text(
                          '$who moved it to ${entry.locationName} ${_ago(entry.movedAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: detailColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),
                    _ActionButton(
                      icon: Icons.open_in_new,
                      isDark: isDark,
                      onTap: () =>
                          context.push(AppRoutes.itemDetailPath(item.uuid)),
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
                  child: AdaptiveImage(
                    path: item.imagePaths.first,
                    itemUuid: item.uuid,
                    imageIndex: 0,
                    variant: AdaptiveImageVariant.thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (_) => _ThumbnailPlaceholder(isDark: isDark),
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

  static String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }
}

// ── Compact result item (no photo — My Inventory) ─────────────────────────────

class _CompactResultItem extends ConsumerWidget {
  const _CompactResultItem({
    required this.item,
    required this.isDark,
  });

  final Item item;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestHistoryAsync = ref.watch(itemLatestHistoryProvider(item.uuid));
    final locationColor = _searchResultLocationColor(isDark);
    final detailColor = _searchResultDetailColor(isDark);
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
                  if (item.locationName != null ||
                      item.locationFullPath != null)
                    Text(
                      'Location: ${item.locationName ?? item.locationFullPath}',
                      style: TextStyle(
                        fontSize: 12,
                        color: locationColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  latestHistoryAsync.when(
                    data: (entry) {
                      if (entry == null) return const SizedBox.shrink();
                      final who =
                          (entry.movedByName?.trim().isNotEmpty ?? false)
                              ? entry.movedByName!
                              : 'Someone';
                      return Text(
                        'Last seen by $who ${_RichResultCard._ago(entry.movedAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: detailColor,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
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
      color:
          isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: AppDimensions.iconLg,
          color:
              isDark ? AppColors.textDisabledDark : AppColors.textDisabledLight,
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.query,
    required this.isDark,
    required this.isHouseholdMode,
  });

  final String query;
  final bool isDark;
  final bool isHouseholdMode;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isHouseholdMode ? Icons.people_outline : Icons.search_off,
            size: AppDimensions.iconXl + 8,
            color: isDark
                ? AppColors.textDisabledDark
                : AppColors.textDisabledLight,
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          Text(
            query.isEmpty
                ? (isHouseholdMode
                    ? 'No shared items from household members yet'
                    : 'No items saved yet')
                : 'No results for "$query"',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
            textAlign: TextAlign.center,
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
          if (query.isEmpty && isHouseholdMode) ...[
            const SizedBox(height: AppDimensions.spacingSm),
            Text(
              'Members can share items from their inventory',
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
