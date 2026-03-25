import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/location_hierarchy_utils.dart';
import '../core/utils/uuid_generator.dart';
import '../domain/models/item.dart';
import '../domain/models/location_model.dart';
import '../providers/item_providers.dart';
import '../providers/location_providers.dart';
import '../theme/app_colors.dart';

// ── Public API ────────────────────────────────────────────────────────────────

/// Opens a bottom sheet guiding the user through three progressive steps:
///   1. Select / create an **Area** (top-level: House, Office, Garage…)
///   2. Optionally select / create a **Room** within that area
///   3. Select / create a **Zone** — the exact spot where the item lives
///
/// Returns the UUID of the chosen zone, or `null` if dismissed.
Future<String?> showLocationPickerSheet(
  BuildContext context, {
  String? initialSelectedLocationUuid,
  String title = 'Select Location',
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _LocationPickerSheet(
        title: title,
        initialSelectedLocationUuid: initialSelectedLocationUuid,
      ),
    ),
  );
}

// ── Step tracking enum ────────────────────────────────────────────────────────

enum _PickerStep { area, room, zone }

// ── Main sheet widget ─────────────────────────────────────────────────────────

class _LocationPickerSheet extends ConsumerStatefulWidget {
  const _LocationPickerSheet({
    required this.title,
    this.initialSelectedLocationUuid,
  });

  final String title;
  final String? initialSelectedLocationUuid;

  @override
  ConsumerState<_LocationPickerSheet> createState() =>
      _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<_LocationPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String? _selectedAreaUuid;
  String? _selectedRoomUuid;
  String? _selectedZoneUuid;
  bool _didSyncInitialSelection = false;
  bool _isSaving = false;

  /// Which accordion step is currently expanded.
  _PickerStep _openStep = _PickerStep.area;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Initial selection sync ──────────────────────────────────────────────────

  void _syncInitialSelection(LocationHierarchy hierarchy) {
    if (_didSyncInitialSelection) return;
    _didSyncInitialSelection = true;

    final initialUuid = widget.initialSelectedLocationUuid;
    if (initialUuid == null || initialUuid.isEmpty) return;

    final initialLocation = hierarchy.byUuid[initialUuid];
    if (initialLocation == null) return;

    if (initialLocation.isAssignableToItem) {
      _applyZoneSelection(hierarchy, initialLocation);
      return;
    }

    // If the UUID points to an area/room, select its first descendant zone.
    final descendantZone = hierarchy
        .descendantsOf(initialLocation.uuid)
        .where((l) => l.isAssignableToItem)
        .cast<LocationModel?>()
        .firstWhere((_) => true, orElse: () => null);

    if (descendantZone != null) {
      _applyZoneSelection(hierarchy, descendantZone);
    }
  }

  /// Applies a zone selection and opens the zone step (used for initial sync).
  void _applyZoneSelection(LocationHierarchy hierarchy, LocationModel zone) {
    _selectedAreaUuid = hierarchy.areaFor(zone.uuid)?.uuid;
    _selectedRoomUuid = hierarchy.roomFor(zone.uuid)?.uuid;
    _selectedZoneUuid = zone.uuid;
    _openStep = _PickerStep.zone;
  }

  // ── Selection handlers ──────────────────────────────────────────────────────

  void _selectArea(LocationHierarchy hierarchy, LocationModel area) {
    setState(() {
      _selectedAreaUuid = area.uuid;

      // Clear room/zone if they don't belong under this area.
      final currentRoom = _selectedRoomUuid == null
          ? null
          : hierarchy.byUuid[_selectedRoomUuid!];
      if (currentRoom?.parentUuid != area.uuid) {
        _selectedRoomUuid = null;
        _selectedZoneUuid = null;
      } else {
        final currentZoneArea = _selectedZoneUuid == null
            ? null
            : hierarchy.areaFor(_selectedZoneUuid!);
        if (currentZoneArea?.uuid != area.uuid) _selectedZoneUuid = null;
      }

      _openStep = _PickerStep.room;
    });
  }

  void _selectRoom(LocationHierarchy hierarchy, LocationModel? room) {
    if (room == null) {
      // User tapped "Skip — no room".
      setState(() {
        _selectedRoomUuid = null;
        // Keep zone only if it is a direct zone under the area.
        final currentZone = _selectedZoneUuid == null
            ? null
            : hierarchy.byUuid[_selectedZoneUuid!];
        if (currentZone != null && !hierarchy.isDirectZone(currentZone)) {
          _selectedZoneUuid = null;
        }
        _openStep = _PickerStep.zone;
      });
      return;
    }

    setState(() {
      _selectedAreaUuid = room.parentUuid;
      _selectedRoomUuid = room.uuid;
      final currentZone = _selectedZoneUuid == null
          ? null
          : hierarchy.byUuid[_selectedZoneUuid!];
      if (currentZone?.parentUuid != room.uuid) _selectedZoneUuid = null;
      _openStep = _PickerStep.zone;
    });
  }

  void _selectZone(LocationHierarchy hierarchy, LocationModel zone) {
    setState(() {
      _selectedAreaUuid = hierarchy.areaFor(zone.uuid)?.uuid;
      _selectedRoomUuid = hierarchy.roomFor(zone.uuid)?.uuid;
      _selectedZoneUuid = zone.uuid;
      // Stay on zone step — user can still change their mind.
    });
  }

  // ── Dialog helpers ──────────────────────────────────────────────────────────

  Future<String?> _askForName({
    required String title,
    required String hintText,
    String initialValue = '',
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: initialValue);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: Text(
          title,
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
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon:
                const Icon(Icons.place_outlined, color: AppColors.primary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  // ── Create location helpers ─────────────────────────────────────────────────

  Future<void> _createArea(LocationHierarchy hierarchy) async {
    final name = await _askForName(
      title: 'Add Area',
      hintText: 'e.g. Home, Office, Garage',
    );
    if (name == null || !mounted) return;

    // Guard against duplicates: if an area with this name already exists,
    // select it instead of inserting a second row with a different UUID.
    final existing = hierarchy.areas.cast<LocationModel?>().firstWhere(
      (a) => a!.name.trim().toLowerCase() == name.toLowerCase(),
      orElse: () => null,
    );
    if (existing != null) {
      setState(() {
        _selectedAreaUuid = existing.uuid;
        _selectedRoomUuid = null;
        _selectedZoneUuid = null;
        _openStep = _PickerStep.room;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${existing.name}" already exists and has been selected.'),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final location = LocationModel(
      uuid: generateUuid(),
      name: name,
      type: LocationType.area,
      createdAt: DateTime.now(),
    );
    final error = await ref
        .read(locationsNotifierProvider.notifier)
        .saveLocation(location);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() {
      _selectedAreaUuid = location.uuid;
      _selectedRoomUuid = null;
      _selectedZoneUuid = null;
      _openStep = _PickerStep.room;
    });
  }

  Future<void> _createRoom(LocationHierarchy hierarchy) async {
    final areaUuid = _selectedAreaUuid;
    if (areaUuid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select an Area first'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final area = hierarchy.byUuid[areaUuid];
    final name = await _askForName(
      title: 'Add Room',
      hintText: 'e.g. Bedroom, Store Room, Kitchen',
    );
    if (name == null || area == null || !mounted) return;

    setState(() => _isSaving = true);
    final location = LocationModel(
      uuid: generateUuid(),
      name: name,
      type: LocationType.room,
      parentUuid: area.uuid,
      createdAt: DateTime.now(),
    );
    final error = await ref
        .read(locationsNotifierProvider.notifier)
        .saveLocation(location);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() {
      _selectedAreaUuid = area.uuid;
      _selectedRoomUuid = location.uuid;
      _selectedZoneUuid = null;
      _openStep = _PickerStep.zone;
    });
  }

  Future<void> _createZone(LocationHierarchy hierarchy) async {
    final parentUuid = _selectedRoomUuid ?? _selectedAreaUuid;
    if (parentUuid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select an Area first'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final parent = hierarchy.byUuid[parentUuid];
    final name = await _askForName(
      title: parent?.type == LocationType.room
          ? 'Add Zone to ${parent!.name}'
          : 'Add Zone',
      hintText: 'e.g. Top Shelf, Left Drawer, Under Bed',
    );
    if (name == null || parent == null || !mounted) return;

    setState(() => _isSaving = true);
    final location = LocationModel(
      uuid: generateUuid(),
      name: name,
      type: LocationType.zone,
      parentUuid: parent.uuid,
      createdAt: DateTime.now(),
    );
    final error = await ref
        .read(locationsNotifierProvider.notifier)
        .saveLocation(location);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() {
      _selectedAreaUuid ??= hierarchy.areaFor(parent.uuid)?.uuid;
      _selectedRoomUuid =
          parent.type == LocationType.room ? parent.uuid : null;
      _selectedZoneUuid = location.uuid;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  // ── Rename / delete ─────────────────────────────────────────────────────────

  Future<void> _renameLocation(LocationModel location) async {
    final updatedName = await _askForName(
      title: 'Edit ${location.type.label}',
      hintText: '${location.type.label} name',
      initialValue: location.name,
    );
    if (updatedName == null || updatedName == location.name || !mounted) return;

    final error = await ref
        .read(locationsNotifierProvider.notifier)
        .updateLocation(location.copyWith(name: updatedName));
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${location.type.label} updated'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _deleteLocation(
    LocationModel location,
    LocationHierarchy hierarchy,
    List<Item>? allItems,
  ) async {
    if (allItems == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for items to finish loading'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final descendantUuids =
        hierarchy.descendantsOf(location.uuid).map((e) => e.uuid).toSet();
    final impactedUuids = <String>{location.uuid, ...descendantUuids};
    final usedItemCount =
        allItems.where((i) => impactedUuids.contains(i.locationUuid)).length;

    if (usedItemCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot delete ${location.name} — used by '
            '$usedItemCount item${usedItemCount == 1 ? '' : 's'}.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final descendants = hierarchy.descendantsOf(location.uuid);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Delete ${location.type.label}?'),
            content: Text(
              descendants.isEmpty
                  ? 'Delete "${location.name}"? This cannot be undone.'
                  : 'Delete "${location.name}" and '
                      '${descendants.length} child location'
                      '${descendants.length == 1 ? '' : 's'} under it?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.error),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    final error = await ref
        .read(locationsNotifierProvider.notifier)
        .deleteLocation(location.uuid);
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() {
      if (impactedUuids.contains(_selectedZoneUuid)) _selectedZoneUuid = null;
      if (impactedUuids.contains(_selectedRoomUuid)) _selectedRoomUuid = null;
      if (impactedUuids.contains(_selectedAreaUuid)) _selectedAreaUuid = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${location.type.label} deleted'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  // ── Location tile (swipe to edit/delete) ────────────────────────────────────

  Widget _buildLocationTile({
    required LocationModel location,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    required Future<void> Function() onEdit,
    required Future<void> Function() onDelete,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected
        ? AppColors.primary.withValues(alpha: 0.14)
        : (isDark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight);
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Dismissible(
        key: ValueKey('picker-loc-${location.uuid}'),
        direction: DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await onEdit();
          } else {
            await onDelete();
          }
          return false;
        },
        background: _SwipeBackground(
          color: AppColors.primary,
          label: 'EDIT',
          alignment: Alignment.centerLeft,
        ),
        secondaryBackground: const _SwipeBackground(
          color: AppColors.error,
          label: 'DELETE',
          alignment: Alignment.centerRight,
        ),
        child: Material(
          color: bg,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected ? AppColors.primary : Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    location.type == LocationType.area
                        ? Icons.home_work_outlined
                        : location.type == LocationType.room
                            ? Icons.meeting_room_outlined
                            : Icons.place_outlined,
                    color: selected ? AppColors.primary : textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          location.name,
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle,
                        color: AppColors.primary, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Accordion step widget ───────────────────────────────────────────────────

  Widget _buildStep({
    required int stepNumber,
    required String label,
    required String emptyHint,
    required String? selectedLabel,
    required bool isExpanded,
    required bool isEnabled,
    required VoidCallback onHeaderTap,
    required List<Widget> tiles,
    required VoidCallback? onAdd,
    String? addLabel,
    Widget? skipTile,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final cardBg =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;

    final hasSelection = selectedLabel != null;
    final borderColor = isExpanded
        ? AppColors.primary
        : hasSelection
            ? AppColors.primary.withValues(alpha: 0.35)
            : (isDark ? AppColors.borderDark : AppColors.borderLight);

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.4,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: isExpanded ? 1.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          children: [
            // ── Header row ───────────────────────────────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isEnabled ? onHeaderTap : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    // Step badge
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isExpanded
                            ? AppColors.primary
                            : hasSelection
                                ? AppColors.success.withValues(alpha: 0.15)
                                : AppColors.primary.withValues(alpha: 0.10),
                      ),
                      alignment: Alignment.center,
                      child: hasSelection && !isExpanded
                          ? const Icon(Icons.check,
                              size: 14, color: AppColors.success)
                          : Text(
                              '$stepNumber',
                              style: TextStyle(
                                color: isExpanded
                                    ? Colors.white
                                    : textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    // Label + selection text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasSelection ? selectedLabel : emptyHint,
                            style: TextStyle(
                              color: hasSelection
                                  ? AppColors.primary
                                  : textSecondary,
                              fontSize: 12.5,
                              fontWeight: hasSelection
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Add button (shown only when step is expanded)
                    if (isExpanded && onAdd != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _isSaving ? null : onAdd,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add,
                                  size: 14, color: AppColors.primary),
                              const SizedBox(width: 3),
                              Text(
                                addLabel ?? 'Add',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    // Chevron (animated rotation)
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: isEnabled
                            ? (isExpanded
                                ? AppColors.primary
                                : textSecondary)
                            : textSecondary.withValues(alpha: 0.3),
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Body (animated expand/collapse) ──────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: isExpanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(
                          height: 1,
                          color: isDark ? Colors.white10 : Colors.black12,
                        ),
                        // Optional skip tile (room step only)
                        if (skipTile != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: skipTile,
                          ),
                        // Items list or empty message
                        if (tiles.isEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(14, 12, 14, 14),
                            child: Text(
                              'Nothing here yet. Tap + above to add one.',
                              style: TextStyle(
                                  color: textSecondary, fontSize: 13),
                            ),
                          )
                        else
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(12, 10, 12, 12),
                            child: Column(
                              children: [
                                for (int i = 0; i < tiles.length; i++) ...[
                                  tiles[i],
                                  if (i < tiles.length - 1)
                                    const SizedBox(height: 6),
                                ],
                              ],
                            ),
                          ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(allLocationsProvider);
    final itemsAsync = ref.watch(allItemsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final inputFill =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;

    return SafeArea(
      top: false,
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 18),
          // Title + saving indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 21,
                    ),
                  ),
                ),
                if (_isSaving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppColors.primary),
                hintText: 'Search zones by name or path',
                filled: true,
                fillColor: inputFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Content area
          Expanded(
            child: locationsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Could not load locations.\n$error',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textSecondary),
                  ),
                ),
              ),
              data: (locations) {
                final hierarchy =
                    LocationHierarchy.fromLocations(locations);
                _syncInitialSelection(hierarchy);

                final selectedZone = _selectedZoneUuid == null
                    ? null
                    : hierarchy.byUuid[_selectedZoneUuid!];
                final selectedArea = _selectedAreaUuid == null
                    ? null
                    : hierarchy.byUuid[_selectedAreaUuid!];
                final selectedRoom = _selectedRoomUuid == null
                    ? null
                    : hierarchy.byUuid[_selectedRoomUuid!];

                // Clean up stale UUID references after a location is deleted.
                if (selectedZone == null && _selectedZoneUuid != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _selectedZoneUuid = null);
                  });
                }

                final items = itemsAsync.valueOrNull;

                // ── Search mode: flat zone list ───────────────────────────
                if (_searchQuery.isNotEmpty) {
                  final searchResults = hierarchy.searchZones(_searchQuery);
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: searchResults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final zone = searchResults[index];
                      return _buildLocationTile(
                        location: zone,
                        subtitle: hierarchy.displayPath(zone),
                        selected: zone.uuid == _selectedZoneUuid,
                        onTap: () => _selectZone(hierarchy, zone),
                        onEdit: () => _renameLocation(zone),
                        onDelete: () =>
                            _deleteLocation(zone, hierarchy, items),
                      );
                    },
                  );
                }

                // ── Accordion mode ────────────────────────────────────────

                // Step 1: Area tiles
                final areaTiles = hierarchy.areas.map((area) {
                  return _buildLocationTile(
                    location: area,
                    subtitle: area.name,
                    selected: area.uuid == _selectedAreaUuid,
                    onTap: () => _selectArea(hierarchy, area),
                    onEdit: () => _renameLocation(area),
                    onDelete: () =>
                        _deleteLocation(area, hierarchy, items),
                  );
                }).toList();

                // Step 2: Room tiles (only for the selected area)
                final areaRooms = selectedArea == null
                    ? const <LocationModel>[]
                    : hierarchy.roomsForArea(selectedArea.uuid);

                final roomTiles = areaRooms.map((room) {
                  return _buildLocationTile(
                    location: room,
                    subtitle: '${selectedArea!.name} › ${room.name}',
                    selected: room.uuid == _selectedRoomUuid,
                    onTap: () => _selectRoom(hierarchy, room),
                    onEdit: () => _renameLocation(room),
                    onDelete: () =>
                        _deleteLocation(room, hierarchy, items),
                  );
                }).toList();

                // Step 3: Zone tiles (under room if selected, else direct under area)
                final zonesList = selectedRoom != null
                    ? hierarchy.zonesForRoom(selectedRoom.uuid)
                    : selectedArea != null
                        ? hierarchy.directZonesForArea(selectedArea.uuid)
                        : const <LocationModel>[];

                final zoneTiles = zonesList.map((zone) {
                  return _buildLocationTile(
                    location: zone,
                    subtitle: hierarchy.displayPath(zone),
                    selected: zone.uuid == _selectedZoneUuid,
                    onTap: () => _selectZone(hierarchy, zone),
                    onEdit: () => _renameLocation(zone),
                    onDelete: () =>
                        _deleteLocation(zone, hierarchy, items),
                  );
                }).toList();

                // Whether the room + zone steps are revealed
                final bool roomZoneRevealed = selectedArea != null;
                final bool zoneRevealed = selectedArea != null &&
                    (_openStep == _PickerStep.zone ||
                        selectedZone != null);

                // Room step selected label (handles "skipped" state)
                final String? roomSelectedLabel = selectedRoom != null
                    ? selectedRoom.name
                    : (zoneRevealed && _selectedRoomUuid == null)
                        ? 'No room — zone directly under area'
                        : null;

                // "Skip room" button shown inside room step
                final skipRoomButton = Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _selectRoom(hierarchy, null),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark
                              ? Colors.white12
                              : Colors.black12,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.not_listed_location_outlined,
                            size: 18,
                            color: textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Skip — zone is directly under this area',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    children: [
                      // Selected zone summary chip
                      if (selectedZone != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.primary
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selected zone',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                hierarchy.displayPath(selectedZone),
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // ── Step 1: Area ──────────────────────────────────
                      _buildStep(
                        stepNumber: 1,
                        label: 'Area',
                        emptyHint: 'House, Office, Garage…',
                        selectedLabel: selectedArea?.name,
                        isExpanded: _openStep == _PickerStep.area,
                        isEnabled: true,
                        onHeaderTap: () =>
                            setState(() => _openStep = _PickerStep.area),
                        tiles: areaTiles,
                        onAdd: () => _createArea(hierarchy),
                        addLabel: 'Add Area',
                      ),

                      // ── Step 2: Room (slides in after area selected) ───
                      AnimatedSize(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeInOutCubic,
                        alignment: Alignment.topCenter,
                        child: roomZoneRevealed
                            ? Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _buildStep(
                                  stepNumber: 2,
                                  label: 'Room (optional)',
                                  emptyHint:
                                      'Bedroom, Kitchen, Store Room…',
                                  selectedLabel: roomSelectedLabel,
                                  isExpanded:
                                      _openStep == _PickerStep.room,
                                  isEnabled: true,
                                  onHeaderTap: () => setState(
                                    () => _openStep = _PickerStep.room,
                                  ),
                                  tiles: roomTiles,
                                  onAdd: () => _createRoom(hierarchy),
                                  addLabel: 'Add Room',
                                  skipTile: skipRoomButton,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),

                      // ── Step 3: Zone (slides in after room step) ───────
                      AnimatedSize(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeInOutCubic,
                        alignment: Alignment.topCenter,
                        child: zoneRevealed
                            ? Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _buildStep(
                                  stepNumber: 3,
                                  label: 'Zone',
                                  emptyHint:
                                      'Top Shelf, Left Drawer, Corner…',
                                  selectedLabel: selectedZone?.name,
                                  isExpanded:
                                      _openStep == _PickerStep.zone,
                                  isEnabled: true,
                                  onHeaderTap: () => setState(
                                    () => _openStep = _PickerStep.zone,
                                  ),
                                  tiles: zoneTiles,
                                  onAdd: () => _createZone(hierarchy),
                                  addLabel: 'Add Zone',
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Save button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selectedZoneUuid == null || _isSaving
                    ? null
                    : () =>
                        Navigator.of(context).pop(_selectedZoneUuid),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Save Location'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Swipe action background ───────────────────────────────────────────────────

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: alignment,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
