import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/location_hierarchy_utils.dart';
import '../../core/utils/uuid_generator.dart';
import '../../domain/models/location_model.dart';
import '../../providers/item_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/location_usage_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/service_providers.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';
import '../../widgets/app_nav_bar.dart';

import 'add_new_room_screen.dart';
import 'rooms_loading_overlay.dart';


const List<_RoomsSuggestionTemplate> _kFeaturedAreaTemplates = [
  _RoomsSuggestionTemplate(
    label: 'Home',
    icon: Icons.home_work_outlined,
  ),
  _RoomsSuggestionTemplate(
    label: 'Office',
    icon: Icons.business_center_outlined,
  ),
  _RoomsSuggestionTemplate(
    label: 'Garage',
    icon: Icons.garage_outlined,
  ),
  _RoomsSuggestionTemplate(
    label: 'Storage',
    icon: Icons.warehouse_outlined,
  ),
];

const List<_RoomsStarterPack> _kRoomsStarterPacks = [
  _RoomsStarterPack(
    label: 'Home Starter',
    areaName: 'Home',
    icon: Icons.home_rounded,
    accentColor: AppColors.info,
    description: 'Creates the everyday rooms and zones most homes need first.',
    rooms: [
      _RoomsStarterRoomSeed(
        name: 'Bedroom',
        iconName: 'bed',
        zones: ['Closet', 'Under Bed'],
      ),
      _RoomsStarterRoomSeed(
        name: 'Kitchen',
        iconName: 'kitchen',
        zones: ['Pantry Shelf', 'Kitchen Cabinet', 'Refrigerator'],
      ),
      _RoomsStarterRoomSeed(
        name: 'Bathroom',
        iconName: 'bath',
        zones: ['Bathroom Cabinet'],
      ),
    ],
  ),
  _RoomsStarterPack(
    label: 'Office Starter',
    areaName: 'Office',
    icon: Icons.business_center_rounded,
    accentColor: AppColors.success,
    description:
        'Sets up shared workspaces, storage spots and filing zones quickly.',
    rooms: [
      _RoomsStarterRoomSeed(
        name: 'Meeting Room',
        iconName: 'office',
        zones: ['Filing Cabinet'],
      ),
      _RoomsStarterRoomSeed(
        name: 'Work Area',
        iconName: 'office',
        zones: ['Desk Drawer', 'Bookshelf'],
      ),
      _RoomsStarterRoomSeed(
        name: 'Storage Room',
        iconName: 'garage',
        zones: ['Storage Box'],
      ),
    ],
  ),
  _RoomsStarterPack(
    label: 'Garage Starter',
    areaName: 'Garage',
    icon: Icons.garage_rounded,
    accentColor: AppColors.warning,
    description: 'Good for tools, workshop gear and larger storage items.',
    directZones: ['Wall Hook'],
    rooms: [
      _RoomsStarterRoomSeed(
        name: 'Tool Room',
        iconName: 'garage',
        zones: ['Tool Box', 'Workbench'],
      ),
      _RoomsStarterRoomSeed(
        name: 'Storage Bay',
        iconName: 'garage',
        zones: ['Garage Shelf', 'Storage Bin'],
      ),
    ],
  ),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  final Set<String> _expandedAreas = {};
  final Set<String> _expandedRooms = {};
  final TextEditingController _roomsSearchController = TextEditingController();
  final FocusNode _roomsSearchFocusNode = FocusNode();
  bool _isRoomsSearchVisible = false;
  String _roomsSearchQuery = '';

  final Map<String, String> _locationImageByUuid = {};

  bool _isBusy = false;
  String _busyLabel = 'Syncing changes...';

  Future<T> _runWithLoading<T>({
    required String label,
    required Future<T> Function() action,
  }) async {
    setState(() {
      _isBusy = true;
      _busyLabel = label;
    });

    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyLabel = 'Syncing changes...';
        });
      }
    }
  }

  Future<void> _openAddRoomFlow() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final topInset = MediaQuery.of(sheetContext).viewPadding.top;

        return Padding(
          padding: EdgeInsets.only(top: topInset + 8),
          child: const FractionallySizedBox(
            heightFactor: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              child: AddNewRoomScreen(),
            ),
          ),
        );
      },
    );

    if (created == true) {
      ref.invalidate(allLocationsProvider);
      ref.invalidate(rootLocationsProvider);
    }
  }

  void _showInfo(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );

  Future<void> _addArea({String? initialName}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: initialName ?? '');

    final areaName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: Text(
          'Create Area',
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
          decoration: InputDecoration(
            hintText: 'e.g. Home, Office, Garage',
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Create',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || areaName == null || areaName.isEmpty) return;
    await _createAreaQuick(areaName);
  }

  /// Normalize a name for duplicate comparison: trim, collapse whitespace,
  /// lowercase.
  static String _normalize(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  Future<void> _createAreaQuick(String name) async {
    if (_isBusy) return;

    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final locations = ref.read(allLocationsProvider).valueOrNull ?? const [];
    LocationModel? existingArea;
    final normalizedName = _normalize(trimmed);
    for (final location in locations) {
      if (location.type == LocationType.area &&
          _normalize(location.name) == normalizedName) {
        existingArea = location;
        break;
      }
    }

    if (existingArea != null) {
      final area = existingArea;
      setState(() => _expandedAreas.add(area.uuid));
      _showInfo('An area with this name already exists.');
      return;
    }

    final area = LocationModel(
      uuid: generateUuid(),
      name: trimmed,
      type: LocationType.area,
      parentUuid: null,
      iconName: 'folder',
      createdAt: DateTime.now(),
    );

    final error = await _runWithLoading<String?>(
      label: 'Creating area...',
      action: () =>
          ref.read(locationsNotifierProvider.notifier).saveLocation(area),
    );

    if (!mounted) return;
    if (error != null) {
      _showError(error);
      return;
    }

    setState(() => _expandedAreas.add(area.uuid));
    _showInfo('Area created');
  }

  Future<void> _editLocationName(
    LocationModel location, {
    required String label,
  }) async {
    if (_isBusy) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: location.name);
    final errorNotifier = ValueNotifier<String?>(null);

    final updatedName = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ValueListenableBuilder<String?>(
          valueListenable: errorNotifier,
          builder: (ctx, errorText, _) => AlertDialog(
            backgroundColor:
                isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            title: Text(
              'Edit $label',
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                  onChanged: (_) {
                    if (errorNotifier.value != null) {
                      errorNotifier.value = null;
                    }
                  },
                  decoration: InputDecoration(
                    hintText: '$label name',
                    filled: true,
                    fillColor: isDark
                        ? AppColors.backgroundDark
                        : AppColors.backgroundLight,
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
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText,
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  if (name == location.name) {
                    Navigator.pop(ctx);
                    return;
                  }

                  // Check for duplicate sibling name.
                  final duplicate = await ref
                      .read(locationRepositoryProvider)
                      .hasSiblingWithName(
                        name: name,
                        locationType: location.type.value,
                        parentUuid: location.parentUuid,
                        excludeUuid: location.uuid,
                      );
                  if (duplicate) {
                    errorNotifier.value =
                        _duplicateMessage(location.type, label);
                    return;
                  }

                  if (ctx.mounted) Navigator.pop(ctx, name);
                },
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
        ),
      ),
    );

    if (!mounted || updatedName == null || updatedName.isEmpty) return;
    if (updatedName == location.name) return;

    final error = await _runWithLoading<String?>(
      label: 'Updating $label...',
      action: () => ref
          .read(locationsNotifierProvider.notifier)
          .updateLocation(location.copyWith(name: updatedName)),
    );

    if (!mounted) return;
    if (error != null) {
      _showError(error);
      return;
    }
    _showInfo('$label updated');
  }

  /// Returns a user-friendly duplicate message for UI display.
  static String _duplicateMessage(LocationType type, String label) {
    switch (type) {
      case LocationType.area:
        return 'An area with this name already exists.';
      case LocationType.room:
        return 'A room with this name already exists in this area.';
      case LocationType.zone:
        return 'A zone with this name already exists in this room.';
    }
  }

  Future<void> _deleteLocation(
    LocationModel location, {
    required String label,
    bool cascades = false,
  }) async {
    if (_isBusy) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor:
                isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            title: Text(
              'Delete $label?',
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              cascades
                  ? 'This will delete ${location.name} and all locations under it.'
                  : 'This action cannot be undone.',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted || !confirmed) return;

    final existingImage = _locationImageByUuid[location.uuid];
    final error = await _runWithLoading<String?>(
      label: 'Deleting $label...',
      action: () async {
        final deleteError = await ref
            .read(locationsNotifierProvider.notifier)
            .deleteLocation(location.uuid);
        if (deleteError != null) return deleteError;

        if (existingImage != null && !existingImage.startsWith('http')) {
          await ref.read(imageServiceProvider).deleteImage(existingImage);
        }
        return null;
      },
    );

    if (!mounted) return;
    if (error != null) {
      _showError(error);
      return;
    }

    setState(() => _locationImageByUuid.remove(location.uuid));
    _showInfo('$label deleted');
  }

  Future<void> _addZone(LocationModel parent) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    final zoneName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: Text(
          'Add Zone to ${parent.name}',
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. Top Shelf, Left Drawer',
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Add',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted || zoneName == null || zoneName.isEmpty) return;
    await _createZoneQuick(parent, zoneName);
  }

  Future<void> _createZoneQuick(
    LocationModel parent,
    String zoneName, {
    String? iconName,
  }) async {
    if (_isBusy) return;

    final trimmed = zoneName.trim();
    if (trimmed.isEmpty) return;

    final locations = ref.read(allLocationsProvider).valueOrNull ?? const [];
    LocationModel? existingZone;
    for (final location in locations) {
      if (location.parentUuid == parent.uuid &&
          location.type == LocationType.zone &&
          _normalize(location.name) == _normalize(trimmed)) {
        existingZone = location;
        break;
      }
    }

    if (existingZone != null) {
      setState(() {
        if (parent.type == LocationType.room) {
          if (parent.parentUuid != null) {
            _expandedAreas.add(parent.parentUuid!);
          }
          _expandedRooms.add(parent.uuid);
        } else {
          _expandedAreas.add(parent.uuid);
        }
      });
      _showInfo('A zone with this name already exists in ${parent.name}.');
      return;
    }

    final zone = LocationModel(
      uuid: generateUuid(),
      name: trimmed,
      type: LocationType.zone,
      parentUuid: parent.uuid,
      iconName: iconName ?? _iconKeyForZoneName(trimmed),
      createdAt: DateTime.now(),
    );

    final error = await _runWithLoading<String?>(
      label: 'Adding zone...',
      action: () =>
          ref.read(locationsNotifierProvider.notifier).saveLocation(zone),
    );

    if (!mounted) return;
    if (error != null) {
      _showError(error);
      return;
    }

    setState(() {
      if (parent.type == LocationType.room) {
        if (parent.parentUuid != null) {
          _expandedAreas.add(parent.parentUuid!);
        }
        _expandedRooms.add(parent.uuid);
      } else {
        _expandedAreas.add(parent.uuid);
      }
    });
    _showInfo('Zone added to ${parent.name}');
  }

  Future<void> _addRoom(LocationModel area) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    final roomName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: Text(
          'Add Room to ${area.name}',
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. Bedroom, Kitchen, Store Room',
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Add',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted || roomName == null || roomName.isEmpty) return;
    await _createRoomQuick(area, roomName);
  }

  Future<void> _createRoomQuick(
    LocationModel area,
    String roomName, {
    String? iconName,
  }) async {
    if (_isBusy) return;

    final trimmed = roomName.trim();
    if (trimmed.isEmpty) return;

    final locations = ref.read(allLocationsProvider).valueOrNull ?? const [];
    LocationModel? existingRoom;
    for (final location in locations) {
      if (location.parentUuid == area.uuid &&
          location.type == LocationType.room &&
          _normalize(location.name) == _normalize(trimmed)) {
        existingRoom = location;
        break;
      }
    }

    if (existingRoom != null) {
      final room = existingRoom;
      setState(() {
        _expandedAreas.add(area.uuid);
        _expandedRooms.add(room.uuid);
      });
      _showInfo('A room with this name already exists in ${area.name}.');
      return;
    }

    final room = LocationModel(
      uuid: generateUuid(),
      name: trimmed,
      type: LocationType.room,
      parentUuid: area.uuid,
      iconName: iconName ?? _iconKeyForRoomName(trimmed),
      createdAt: DateTime.now(),
    );

    final error = await _runWithLoading<String?>(
      label: 'Adding room...',
      action: () =>
          ref.read(locationsNotifierProvider.notifier).saveLocation(room),
    );

    if (!mounted) return;
    if (error != null) {
      _showError(error);
      return;
    }

    setState(() {
      _expandedAreas.add(area.uuid);
      _expandedRooms.add(room.uuid);
    });
    _showInfo('Room added to ${area.name}');
  }

  LocationModel? _findLocationByName(
    List<LocationModel> locations, {
    required LocationType type,
    required String name,
    String? parentUuid,
  }) {
    final normalizedName = name.trim().toLowerCase();
    for (final location in locations) {
      if (location.type == type &&
          location.parentUuid == parentUuid &&
          location.name.trim().toLowerCase() == normalizedName) {
        return location;
      }
    }
    return null;
  }

  String _countLabel(
    int count,
    String singular, {
    String? plural,
  }) {
    final pluralLabel = plural ?? '${singular}s';
    return '$count ${count == 1 ? singular : pluralLabel}';
  }

  Future<void> _applyStarterPack(_RoomsStarterPack pack) async {
    if (_isBusy) return;

    await _runWithLoading<void>(
      label: 'Applying ${pack.label}...',
      action: () async {
        final notifier = ref.read(locationsNotifierProvider.notifier);
        var locations = await ref.read(allLocationsProvider.future);

        LocationModel? area = _findLocationByName(
          locations,
          type: LocationType.area,
          name: pack.areaName,
        );

        var createdAreaCount = 0;
        var createdRoomCount = 0;
        var createdZoneCount = 0;
        final expandedRoomUuids = <String>{};

        Future<bool> saveLocation(LocationModel location) async {
          final error = await notifier.saveLocation(location);
          if (!mounted) return false;
          if (error != null) {
            _showError(error);
            return false;
          }
          locations = [...locations, location];
          return true;
        }

        if (area == null) {
          final createdArea = LocationModel(
            uuid: generateUuid(),
            name: pack.areaName,
            type: LocationType.area,
            parentUuid: null,
            iconName: 'folder',
            createdAt: DateTime.now(),
          );
          if (!await saveLocation(createdArea)) return;
          area = createdArea;
          createdAreaCount += 1;
        }

        final targetArea = area;

        for (final roomSeed in pack.rooms) {
          var room = _findLocationByName(
            locations,
            type: LocationType.room,
            name: roomSeed.name,
            parentUuid: targetArea.uuid,
          );

          if (room == null) {
            final createdRoom = LocationModel(
              uuid: generateUuid(),
              name: roomSeed.name,
              type: LocationType.room,
              parentUuid: targetArea.uuid,
              iconName: roomSeed.iconName ?? _iconKeyForRoomName(roomSeed.name),
              createdAt: DateTime.now(),
            );
            if (!await saveLocation(createdRoom)) return;
            room = createdRoom;
            createdRoomCount += 1;
          }

          final targetRoom = room;

          expandedRoomUuids.add(targetRoom.uuid);

          for (final zoneName in roomSeed.zones) {
            final existingZone = _findLocationByName(
              locations,
              type: LocationType.zone,
              name: zoneName,
              parentUuid: targetRoom.uuid,
            );
            if (existingZone != null) continue;

            final createdZone = LocationModel(
              uuid: generateUuid(),
              name: zoneName,
              type: LocationType.zone,
              parentUuid: targetRoom.uuid,
              iconName: _iconKeyForZoneName(zoneName),
              createdAt: DateTime.now(),
            );
            if (!await saveLocation(createdZone)) return;
            createdZoneCount += 1;
          }
        }

        for (final zoneName in pack.directZones) {
          final existingZone = _findLocationByName(
            locations,
            type: LocationType.zone,
            name: zoneName,
            parentUuid: targetArea.uuid,
          );
          if (existingZone != null) continue;

          final createdZone = LocationModel(
            uuid: generateUuid(),
            name: zoneName,
            type: LocationType.zone,
            parentUuid: targetArea.uuid,
            iconName: _iconKeyForZoneName(zoneName),
            createdAt: DateTime.now(),
          );
          if (!await saveLocation(createdZone)) return;
          createdZoneCount += 1;
        }

        if (!mounted) return;

        setState(() {
          _expandedAreas.add(targetArea.uuid);
          _expandedRooms.addAll(expandedRoomUuids);
        });

        if (createdAreaCount == 0 &&
            createdRoomCount == 0 &&
            createdZoneCount == 0) {
          _showInfo('${pack.label} is already set up');
          return;
        }

        final parts = <String>[
          if (createdAreaCount > 0) _countLabel(createdAreaCount, 'area'),
          if (createdRoomCount > 0) _countLabel(createdRoomCount, 'room'),
          if (createdZoneCount > 0) _countLabel(createdZoneCount, 'zone'),
        ];
        _showInfo('${pack.label} added ${parts.join(', ')}');
      },
    );
  }

  String? _imagePath(String uuid) => _locationImageByUuid[uuid];

  void _openRoomsSearch() {
    if (_isRoomsSearchVisible) return;
    setState(() => _isRoomsSearchVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _roomsSearchFocusNode.requestFocus();
      }
    });
  }

  void _clearRoomsSearch() {
    if (_roomsSearchQuery.isEmpty && _roomsSearchController.text.isEmpty) {
      return;
    }
    _roomsSearchController.clear();
    setState(() => _roomsSearchQuery = '');
  }

  void _closeRoomsSearch() {
    _roomsSearchController.clear();
    _roomsSearchFocusNode.unfocus();
    setState(() {
      _roomsSearchQuery = '';
      _isRoomsSearchVisible = false;
    });
  }

  String _iconKeyForRoomName(String roomName) {
    final lower = roomName.toLowerCase();
    if (lower.contains('bed')) return 'bed';
    if (lower.contains('kitchen') || lower.contains('pantry')) return 'kitchen';
    if (lower.contains('garage') ||
        lower.contains('workshop') ||
        lower.contains('tool')) {
      return 'garage';
    }
    if (lower.contains('bath')) return 'bath';
    if (lower.contains('office') ||
        lower.contains('study') ||
        lower.contains('meeting') ||
        lower.contains('work')) {
      return 'office';
    }
    if (lower.contains('dining')) return 'dining';
    if (lower.contains('living') || lower.contains('lounge')) return 'living';
    return 'folder';
  }

  String _iconKeyForZoneName(String zoneName) {
    final lower = zoneName.toLowerCase();
    if (lower.contains('shelf') || lower.contains('rack')) return 'shelves';
    if (lower.contains('closet') ||
        lower.contains('wardrobe') ||
        lower.contains('cabinet') ||
        lower.contains('locker')) {
      return 'door';
    }
    if (lower.contains('fridge') ||
        lower.contains('freezer') ||
        lower.contains('pantry')) {
      return 'kitchen';
    }
    if (lower.contains('tool') || lower.contains('workbench')) return 'garage';
    return 'folder';
  }

  List<_RoomsSuggestionTemplate> _roomTemplatesForArea(LocationModel area) {
    final lower = area.name.toLowerCase();

    if (lower.contains('office') ||
        lower.contains('shop') ||
        lower.contains('clinic') ||
        lower.contains('studio')) {
      return const [
        _RoomsSuggestionTemplate(
          label: 'Meeting Room',
          icon: Icons.groups_2_outlined,
          iconName: 'office',
        ),
        _RoomsSuggestionTemplate(
          label: 'Work Area',
          icon: Icons.work_outline_rounded,
          iconName: 'office',
        ),
        _RoomsSuggestionTemplate(
          label: 'Storage Room',
          icon: Icons.inventory_2_outlined,
          iconName: 'garage',
        ),
      ];
    }

    if (lower.contains('garage') ||
        lower.contains('warehouse') ||
        lower.contains('shed') ||
        lower.contains('workshop') ||
        lower.contains('storage')) {
      return const [
        _RoomsSuggestionTemplate(
          label: 'Tool Room',
          icon: Icons.handyman_outlined,
          iconName: 'garage',
        ),
        _RoomsSuggestionTemplate(
          label: 'Storage Bay',
          icon: Icons.warehouse_outlined,
          iconName: 'garage',
        ),
        _RoomsSuggestionTemplate(
          label: 'Workbench Area',
          icon: Icons.build_circle_outlined,
          iconName: 'garage',
        ),
      ];
    }

    return const [
      _RoomsSuggestionTemplate(
        label: 'Bedroom',
        icon: Icons.bed_rounded,
        iconName: 'bed',
      ),
      _RoomsSuggestionTemplate(
        label: 'Kitchen',
        icon: Icons.kitchen_rounded,
        iconName: 'kitchen',
      ),
      _RoomsSuggestionTemplate(
        label: 'Bathroom',
        icon: Icons.bathtub_outlined,
        iconName: 'bath',
      ),
    ];
  }

  List<_RoomsSuggestionTemplate> _zoneTemplatesForParent(LocationModel parent) {
    final lower = parent.name.toLowerCase();

    if (lower.contains('kitchen') || lower.contains('pantry')) {
      return const [
        _RoomsSuggestionTemplate(
          label: 'Pantry Shelf',
          icon: Icons.table_rows_rounded,
          iconName: 'shelves',
        ),
        _RoomsSuggestionTemplate(
          label: 'Kitchen Cabinet',
          icon: Icons.door_sliding_outlined,
          iconName: 'door',
        ),
        _RoomsSuggestionTemplate(
          label: 'Refrigerator',
          icon: Icons.kitchen_rounded,
          iconName: 'kitchen',
        ),
      ];
    }

    if (lower.contains('bed') || lower.contains('closet')) {
      return const [
        _RoomsSuggestionTemplate(
          label: 'Closet',
          icon: Icons.door_sliding_outlined,
          iconName: 'door',
        ),
        _RoomsSuggestionTemplate(
          label: 'Under Bed',
          icon: Icons.bed_rounded,
          iconName: 'bed',
        ),
        _RoomsSuggestionTemplate(
          label: 'Dresser Drawer',
          icon: Icons.inventory_2_outlined,
          iconName: 'folder',
        ),
      ];
    }

    if (lower.contains('office') ||
        lower.contains('study') ||
        lower.contains('meeting') ||
        lower.contains('work')) {
      return const [
        _RoomsSuggestionTemplate(
          label: 'Desk Drawer',
          icon: Icons.inventory_2_outlined,
          iconName: 'folder',
        ),
        _RoomsSuggestionTemplate(
          label: 'Filing Cabinet',
          icon: Icons.door_sliding_outlined,
          iconName: 'door',
        ),
        _RoomsSuggestionTemplate(
          label: 'Bookshelf',
          icon: Icons.table_rows_rounded,
          iconName: 'shelves',
        ),
      ];
    }

    if (lower.contains('bath')) {
      return const [
        _RoomsSuggestionTemplate(
          label: 'Bathroom Cabinet',
          icon: Icons.door_sliding_outlined,
          iconName: 'door',
        ),
        _RoomsSuggestionTemplate(
          label: 'Vanity',
          icon: Icons.inventory_2_outlined,
          iconName: 'folder',
        ),
        _RoomsSuggestionTemplate(
          label: 'Top Shelf',
          icon: Icons.table_rows_rounded,
          iconName: 'shelves',
        ),
      ];
    }

    if (lower.contains('garage') ||
        lower.contains('tool') ||
        lower.contains('storage') ||
        lower.contains('workshop')) {
      return const [
        _RoomsSuggestionTemplate(
          label: 'Tool Box',
          icon: Icons.handyman_outlined,
          iconName: 'garage',
        ),
        _RoomsSuggestionTemplate(
          label: 'Garage Shelf',
          icon: Icons.table_rows_rounded,
          iconName: 'shelves',
        ),
        _RoomsSuggestionTemplate(
          label: 'Workbench',
          icon: Icons.build_outlined,
          iconName: 'garage',
        ),
      ];
    }

    return const [
      _RoomsSuggestionTemplate(
        label: 'Top Shelf',
        icon: Icons.table_rows_rounded,
        iconName: 'shelves',
      ),
      _RoomsSuggestionTemplate(
        label: 'Main Closet',
        icon: Icons.door_sliding_outlined,
        iconName: 'door',
      ),
      _RoomsSuggestionTemplate(
        label: 'Storage Box',
        icon: Icons.inventory_2_outlined,
        iconName: 'folder',
      ),
    ];
  }

  IconData _iconForLocation(String iconName) {
    switch (iconName) {
      case 'bed':
        return Icons.bed_rounded;
      case 'living':
        return Icons.chair_rounded;
      case 'kitchen':
        return Icons.kitchen_rounded;
      case 'garage':
        return Icons.garage_rounded;
      case 'bath':
        return Icons.bathtub_outlined;
      case 'office':
        return Icons.work_outline_rounded;
      case 'dining':
        return Icons.restaurant_rounded;
      case 'door':
        return Icons.door_sliding_outlined;
      case 'shelves':
        return Icons.table_rows_rounded;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  @override
  void dispose() {
    _roomsSearchController.dispose();
    _roomsSearchFocusNode.dispose();
    super.dispose();
  }

  Widget _buildZoneRow(
    LocationModel zone, {
    required bool isDark,
    bool isSearchMatch = false,
  }) {
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final chipColor = isDark
        ? AppColors.accentSurfaceDark
        : AppColors.primary.withValues(alpha: 0.12);
    final chipIconColor = isDark ? AppColors.primaryLight : AppColors.primary;
    final rowBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final imagePath = _imagePath(zone.uuid);
    final isNetworkImage = imagePath?.startsWith('http') ?? false;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Dismissible(
        key: ValueKey('rooms-zone-${zone.uuid}'),
        direction: DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await _editLocationName(zone, label: 'Zone');
          } else {
            await _deleteLocation(zone, label: 'Zone');
          }
          return false;
        },
        background: _SwipeActionBackground(isEdit: true, borderRadius: 14),
        secondaryBackground:
            _SwipeActionBackground(isEdit: false, borderRadius: 14),
        child: InkWell(
          onTap: () => context.push(
            AppRoutes.search,
            extra: {'initialLocationUuid': zone.uuid},
          ),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: rowBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSearchMatch
                    ? AppColors.primary.withValues(alpha: 0.42)
                    : (isDark
                        ? AppColors.borderDark
                        : AppColors.primary.withValues(alpha: 0.18)),
                width: isSearchMatch ? 1.2 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: chipColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: imagePath == null
                      ? Icon(
                          _iconForLocation(zone.iconName),
                          color: chipIconColor,
                          size: 16,
                        )
                      : (isNetworkImage
                          ? Image.network(
                              imagePath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                _iconForLocation(zone.iconName),
                                color: chipIconColor,
                                size: 16,
                              ),
                            )
                          : Image.file(
                              File(imagePath),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                _iconForLocation(zone.iconName),
                                color: chipIconColor,
                                size: 16,
                              ),
                            )),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    zone.name,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (zone.usageCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${zone.usageCount}',
                      style: TextStyle(
                        color:
                            isDark ? AppColors.primaryLight : AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: textSecondary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomRow(
    LocationHierarchy hierarchy,
    LocationModel room, {
    required bool isDark,
    required _RoomsLocationSearchState searchState,
  }) {
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final roomBg =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;
    final roomMatchesSearch = searchState.isRoomMatch(room.uuid);

    var zones = hierarchy.zonesForRoom(room.uuid);
    if (searchState.isActive && !roomMatchesSearch) {
      zones = zones
          .where((zone) => searchState.isZoneVisible(zone.uuid))
          .toList(growable: false);
    }

    final autoExpandedBySearch =
        searchState.isActive && (roomMatchesSearch || zones.isNotEmpty);
    final isExpanded =
        _expandedRooms.contains(room.uuid) || autoExpandedBySearch;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Dismissible(
        key: ValueKey('rooms-room-${room.uuid}'),
        direction: DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await _editLocationName(room, label: 'Room');
          } else {
            await _deleteLocation(room, label: 'Room', cascades: true);
          }
          return false;
        },
        background: _SwipeActionBackground(isEdit: true, borderRadius: 14),
        secondaryBackground:
            _SwipeActionBackground(isEdit: false, borderRadius: 14),
        child: Container(
          decoration: BoxDecoration(
            color: roomBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: roomMatchesSearch
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : (isExpanded
                      ? AppColors.primary.withValues(alpha: 0.5)
                      : (isDark
                          ? AppColors.borderDark
                          : AppColors.primary.withValues(alpha: 0.18))),
              width: roomMatchesSearch ? 1.2 : 1.0,
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() {
                  if (isExpanded) {
                    _expandedRooms.remove(room.uuid);
                  } else {
                    _expandedRooms.add(room.uuid);
                  }
                }),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isExpanded
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _iconForLocation(room.iconName),
                          color: isExpanded ? Colors.white : AppColors.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.name,
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _RoomsMetricPill(
                                  icon: Icons.widgets_outlined,
                                  label:
                                      '${zones.length} zone${zones.length == 1 ? '' : 's'}',
                                  isDark: isDark,
                                  isHighlighted: zones.isNotEmpty,
                                ),
                                _RoomsMetricPill(
                                  icon: Icons.inventory_2_outlined,
                                  label:
                                      '${room.usageCount} item${room.usageCount == 1 ? '' : 's'}',
                                  isDark: isDark,
                                  isHighlighted: room.usageCount > 0,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: isExpanded ? AppColors.primary : textSecondary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                child: isExpanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(
                          children: [
                            Divider(
                              height: 1,
                              color: isDark ? Colors.white10 : Colors.black12,
                            ),
                            const SizedBox(height: 10),
                            if (zones.isEmpty)
                              _RoomsNestedEmptyHint(
                                isDark: isDark,
                                icon: searchState.isActive
                                    ? Icons.search_off_rounded
                                    : Icons.widgets_outlined,
                                title: searchState.isActive
                                    ? 'No matching zones'
                                    : 'This room needs a few exact spots',
                                message: searchState.isActive
                                    ? 'Try another keyword or clear the search to see everything in this room.'
                                    : 'Add zones like shelves, drawers or cabinets so items can be saved with precise location memory.',
                                suggestions: searchState.isActive
                                    ? const []
                                    : _zoneTemplatesForParent(room),
                                onSuggestionTap: searchState.isActive
                                    ? null
                                    : (template) => _createZoneQuick(
                                          room,
                                          template.label,
                                          iconName: template.iconName,
                                        ),
                              )
                            else
                              ...zones.map(
                                (zone) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _buildZoneRow(
                                    zone,
                                    isDark: isDark,
                                    isSearchMatch:
                                        searchState.isZoneMatch(zone.uuid),
                                  ),
                                ),
                              ),
                            if (!searchState.isActive) ...[
                              const SizedBox(height: 4),
                              _buildAddButton(
                                label: '+ Add Zone',
                                onTap: () => _addZone(room),
                                isDark: isDark,
                              ),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAreaCard(
    LocationHierarchy hierarchy,
    LocationModel area, {
    required bool isDark,
    required _RoomsLocationSearchState searchState,
  }) {
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    var rooms = hierarchy.roomsForArea(area.uuid);
    if (searchState.isActive) {
      rooms = rooms
          .where((room) => searchState.isRoomVisible(room.uuid))
          .toList(growable: false);
    }

    var directZones = hierarchy.directZonesForArea(area.uuid);
    if (searchState.isActive) {
      directZones = directZones
          .where((zone) => searchState.isZoneVisible(zone.uuid))
          .toList(growable: false);
    }

    final visibleZoneCount = directZones.length +
        rooms.fold<int>(0, (sum, room) {
          var roomZones = hierarchy.zonesForRoom(room.uuid);
          if (searchState.isActive && !searchState.isRoomMatch(room.uuid)) {
            roomZones = roomZones
                .where((zone) => searchState.isZoneVisible(zone.uuid))
                .toList(growable: false);
          }
          return sum + roomZones.length;
        });

    final totalChildren = rooms.length + directZones.length;
    final areaHasSearchResults = searchState.isActive && totalChildren > 0;
    final isExpanded =
        _expandedAreas.contains(area.uuid) || areaHasSearchResults;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Dismissible(
        key: ValueKey('rooms-area-${area.uuid}'),
        direction: DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await _editLocationName(area, label: 'Area');
          } else {
            await _deleteLocation(area, label: 'Area', cascades: true);
          }
          return false;
        },
        background: _SwipeActionBackground(isEdit: true, borderRadius: 20),
        secondaryBackground:
            _SwipeActionBackground(isEdit: false, borderRadius: 20),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: areaHasSearchResults
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : (isExpanded
                      ? AppColors.primary.withValues(alpha: 0.55)
                      : (isDark
                          ? AppColors.borderDark
                          : AppColors.primary.withValues(alpha: 0.22))),
              width: areaHasSearchResults || isExpanded ? 1.5 : 1.0,
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() {
                  if (isExpanded) {
                    _expandedAreas.remove(area.uuid);
                  } else {
                    _expandedAreas.add(area.uuid);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: isExpanded
                              ? AppColors.primaryGradient
                              : LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.primary.withValues(alpha: 0.18),
                                    AppColors.secondary.withValues(alpha: 0.08),
                                  ],
                                ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: isExpanded
                              ? [
                                  BoxShadow(
                                    color:
                                        AppColors.primary.withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          Icons.home_work_outlined,
                          color: isExpanded
                              ? Colors.white
                              : AppColors.primaryLight,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              area.name,
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _RoomsMetricPill(
                                  icon: Icons.meeting_room_outlined,
                                  label:
                                      '${rooms.length} room${rooms.length == 1 ? '' : 's'}',
                                  isDark: isDark,
                                  isHighlighted: rooms.isNotEmpty,
                                ),
                                _RoomsMetricPill(
                                  icon: Icons.widgets_outlined,
                                  label:
                                      '$visibleZoneCount zone${visibleZoneCount == 1 ? '' : 's'}',
                                  isDark: isDark,
                                  isHighlighted: visibleZoneCount > 0,
                                ),
                                _RoomsMetricPill(
                                  icon: Icons.inventory_2_outlined,
                                  label:
                                      '${area.usageCount} item${area.usageCount == 1 ? '' : 's'}',
                                  isDark: isDark,
                                  isHighlighted: area.usageCount > 0,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: isExpanded ? AppColors.primary : textSecondary,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                child: isExpanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                        child: Column(
                          children: [
                            Divider(
                              height: 1,
                              color: isDark ? Colors.white10 : Colors.black12,
                            ),
                            const SizedBox(height: 10),
                            if (rooms.isNotEmpty)
                              ...rooms.map(
                                (room) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _buildRoomRow(
                                    hierarchy,
                                    room,
                                    isDark: isDark,
                                    searchState: searchState,
                                  ),
                                ),
                              ),
                            if (directZones.isNotEmpty) ...[
                              if (rooms.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.subdirectory_arrow_right_rounded,
                                        color: textSecondary,
                                        size: 15,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Direct zones',
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ...directZones.map(
                                (zone) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _buildZoneRow(
                                    zone,
                                    isDark: isDark,
                                    isSearchMatch:
                                        searchState.isZoneMatch(zone.uuid),
                                  ),
                                ),
                              ),
                            ],
                            if (rooms.isEmpty && directZones.isEmpty)
                              _RoomsNestedEmptyHint(
                                isDark: isDark,
                                icon: searchState.isActive
                                    ? Icons.search_off_rounded
                                    : Icons.home_work_outlined,
                                title: searchState.isActive
                                    ? 'No matching rooms or zones'
                                    : 'This area is waiting for structure',
                                message: searchState.isActive
                                    ? 'Try a different keyword or clear the search to show everything inside this area.'
                                    : 'Start with a room template below, or create a direct zone if this area only needs shelves or bins.',
                                suggestions: searchState.isActive
                                    ? const []
                                    : _roomTemplatesForArea(area),
                                onSuggestionTap: searchState.isActive
                                    ? null
                                    : (template) => _createRoomQuick(
                                          area,
                                          template.label,
                                          iconName: template.iconName,
                                        ),
                              )
                            else if (!searchState.isActive && rooms.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _RoomsNestedEmptyHint(
                                  isDark: isDark,
                                  icon: Icons.auto_awesome_rounded,
                                  title:
                                      'Add a room to make this area easier to scan',
                                  message:
                                      'Direct zones work, but rooms create a clearer mental map when this area grows.',
                                  suggestions: _roomTemplatesForArea(area),
                                  onSuggestionTap: (template) =>
                                      _createRoomQuick(
                                    area,
                                    template.label,
                                    iconName: template.iconName,
                                  ),
                                ),
                              ),
                            if (!searchState.isActive) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildAddButton(
                                      label: '+ Add Room',
                                      onTap: () => _addRoom(area),
                                      isDark: isDark,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildAddButton(
                                      label: '+ Add Zone',
                                      onTap: () => _addZone(area),
                                      isDark: isDark,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton({
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isDark
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.primary.withValues(alpha: 0.04),
          border: Border.all(
            color: isDark
                ? AppColors.primaryLight.withValues(alpha: 0.4)
                : AppColors.primary.withValues(alpha: 0.32),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isDark ? AppColors.primaryLight : AppColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(locationsWithDerivedUsageProvider);
    final itemsAsync = ref.watch(allItemsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kBg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final kMuted =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Stack(
          children: [
            Scaffold(
              backgroundColor: kBg,
              body: Column(
                children: [
                  _TopHeader(
                    onAddTap: _openAddRoomFlow,
                    isSearchVisible: _isRoomsSearchVisible,
                    searchQuery: _roomsSearchQuery,
                    searchController: _roomsSearchController,
                    searchFocusNode: _roomsSearchFocusNode,
                    onSearchTap: _isRoomsSearchVisible
                        ? _closeRoomsSearch
                        : _openRoomsSearch,
                    onSearchChanged: (value) =>
                        setState(() => _roomsSearchQuery = value),
                    onSearchClear: _clearRoomsSearch,
                  ),
                  Expanded(
                    child: locationsAsync.when(
                      loading: () => const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.primary),
                      ),
                      error: (error, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Failed to load locations.\n$error',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kMuted),
                          ),
                        ),
                      ),
                      data: (allLocations) {
                        final hierarchy =
                            LocationHierarchy.fromLocations(allLocations);
                        final searchState = _RoomsLocationSearchState.fromQuery(
                          hierarchy,
                          _roomsSearchQuery,
                        );
                        final areas = searchState.isActive
                            ? hierarchy.areas
                                .where(
                                  (area) =>
                                      searchState.isAreaVisible(area.uuid),
                                )
                                .toList(growable: false)
                            : hierarchy.areas;

                        final activeItemCount = itemsAsync.valueOrNull
                                ?.where((item) => !item.isArchived)
                                .length ??
                            allLocations
                                .where((location) =>
                                    location.type == LocationType.zone)
                                .fold<int>(
                                  0,
                                  (sum, location) => sum + location.usageCount,
                                );

                        final overview = _RoomsOverview.fromHierarchy(
                          hierarchy,
                          allLocations,
                          activeItemCount,
                        );

                        final areaTemplates = _kFeaturedAreaTemplates
                            .where(
                              (template) => !hierarchy.areas.any(
                                (area) =>
                                    area.name.trim().toLowerCase() ==
                                    template.label.toLowerCase(),
                              ),
                            )
                            .toList(growable: false);

                        final nextIncompleteStep = overview.areaCount == 0
                            ? 0
                            : overview.roomCount == 0
                                ? 1
                                : overview.zoneCount == 0
                                    ? 2
                                    : overview.itemCount == 0
                                        ? 3
                                        : -1;
                        final showSetupProgress = !searchState.isActive &&
                            areas.isNotEmpty &&
                            nextIncompleteStep != -1;
                        final setupSteps = <_RoomsSetupTask>[
                          _RoomsSetupTask(
                            icon: Icons.home_work_outlined,
                            title: overview.areaCount == 0
                                ? 'Create your first area'
                                : _countLabel(overview.areaCount, 'area'),
                            description: overview.areaCount == 0
                                ? 'Start with the biggest space you remember naturally, like Home, Office or Garage.'
                                : 'Areas are the top-level map of your spaces, and they are ready.',
                            isComplete: overview.areaCount > 0,
                            actionLabel:
                                overview.areaCount == 0 ? 'Create' : null,
                            onTap: overview.areaCount == 0
                                ? () => _addArea()
                                : null,
                            isRecommended: nextIncompleteStep == 0,
                          ),
                          _RoomsSetupTask(
                            icon: Icons.meeting_room_outlined,
                            title: overview.roomCount == 0
                                ? 'Add your first room'
                                : _countLabel(overview.roomCount, 'room'),
                            description: overview.roomCount == 0
                                ? overview.areaCount == 0
                                    ? 'Use guided setup to create a room as soon as your first area exists.'
                                    : 'Break ${overview.firstAreaWithoutRooms?.name ?? 'your area'} into real rooms so the screen feels structured.'
                                : 'Rooms split bigger areas into memorable places people actually think about.',
                            isComplete: overview.roomCount > 0,
                            actionLabel: overview.roomCount == 0
                                ? (overview.areaCount == 0
                                    ? 'Guided setup'
                                    : 'Add room')
                                : null,
                            onTap: overview.roomCount == 0
                                ? (overview.areaCount == 0
                                    ? _openAddRoomFlow
                                    : () => _addRoom(
                                          overview.firstAreaWithoutRooms ??
                                              hierarchy.areas.first,
                                        ))
                                : null,
                            isRecommended: nextIncompleteStep == 1,
                          ),
                          _RoomsSetupTask(
                            icon: Icons.widgets_outlined,
                            title: overview.zoneCount == 0
                                ? 'Add your first zone'
                                : _countLabel(overview.zoneCount, 'zone'),
                            description: overview.zoneCount == 0
                                ? overview.roomCount == 0
                                    ? 'Create a room first, then add the exact shelf, drawer or cabinet where items live.'
                                    : 'Zones make item locations precise. Start with ${overview.firstRoomWithoutZones?.name ?? 'your next room'}.'
                                : 'Zones are the exact places search and item saving rely on.',
                            isComplete: overview.zoneCount > 0,
                            actionLabel: overview.zoneCount == 0
                                ? (overview.roomCount == 0
                                    ? 'Add room'
                                    : 'Add zone')
                                : null,
                            onTap: overview.zoneCount == 0
                                ? (overview.roomCount == 0
                                    ? () => _addRoom(
                                          overview.firstAreaWithoutRooms ??
                                              hierarchy.areas.first,
                                        )
                                    : () => _addZone(
                                          overview.firstRoomWithoutZones!,
                                        ))
                                : null,
                            isRecommended: nextIncompleteStep == 2,
                          ),
                          _RoomsSetupTask(
                            icon: Icons.inventory_2_outlined,
                            title: overview.itemCount == 0
                                ? 'Save your first item'
                                : _countLabel(overview.itemCount, 'item'),
                            description: overview.itemCount == 0
                                ? overview.zoneCount == 0
                                    ? 'Finish one zone first, then save a real item into it.'
                                    : 'Your structure is ready. Add one real item so search and recall become useful immediately.'
                                : 'Items are already connected to your location map.',
                            isComplete: overview.itemCount > 0,
                            actionLabel: overview.itemCount == 0
                                ? (overview.zoneCount == 0
                                    ? (overview.roomCount == 0
                                        ? 'Add room'
                                        : 'Add zone')
                                    : 'Save item')
                                : null,
                            onTap: overview.itemCount == 0
                                ? (overview.zoneCount == 0
                                    ? (overview.roomCount == 0
                                        ? () => _addRoom(
                                              overview.firstAreaWithoutRooms ??
                                                  hierarchy.areas.first,
                                            )
                                        : () => _addZone(
                                              overview.firstRoomWithoutZones!,
                                            ))
                                    : () => context.push(AppRoutes.save))
                                : null,
                            isRecommended: nextIncompleteStep == 3,
                          ),
                        ];

                        final guidanceArea = areas.isNotEmpty
                            ? overview.firstAreaWithoutRooms
                            : null;
                        final guidanceRoom = areas.isNotEmpty
                            ? overview.firstRoomWithoutZones
                            : null;

                        return ListView(
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: AppDimensions.spacingSm,
                            bottom: AppNavBar.contentBottomSpacing(context),
                          ),
                          children: [
                            if (_isRoomsSearchVisible)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _RoomsSearchSummary(
                                  query: searchState.query,
                                  matchCount: searchState.matchCount,
                                  isDark: isDark,
                                ),
                              ),
                            if (showSetupProgress)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _RoomsSetupProgressCard(
                                  isDark: isDark,
                                  steps: setupSteps,
                                ),
                              ),
                            if (!searchState.isActive && areas.isEmpty)
                              _RoomsEmptyState(
                                isDark: isDark,
                                suggestedAreas: areaTemplates.isEmpty
                                    ? _kFeaturedAreaTemplates
                                    : areaTemplates,
                                starterPacks: _kRoomsStarterPacks,
                                onCreateAreaTap: () => _addArea(),
                                onGuidedAddTap: _openAddRoomFlow,
                                onSuggestionTap: (template) =>
                                    _createAreaQuick(template.label),
                                onStarterPackTap: _applyStarterPack,
                              )
                            else ...[
                              if (!searchState.isActive && guidanceArea != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _RoomsGuidanceCard(
                                    isDark: isDark,
                                    icon: Icons.auto_awesome_rounded,
                                    title:
                                        'Quick room ideas for ${guidanceArea.name}',
                                    description:
                                        'Tap once to create common rooms and make this area feel organized immediately.',
                                    suggestions:
                                        _roomTemplatesForArea(guidanceArea),
                                    onSuggestionTap: (template) =>
                                        _createRoomQuick(
                                      guidanceArea,
                                      template.label,
                                      iconName: template.iconName,
                                    ),
                                  ),
                                )
                              else if (!searchState.isActive &&
                                  guidanceRoom != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _RoomsGuidanceCard(
                                    isDark: isDark,
                                    icon: Icons.tips_and_updates_outlined,
                                    title:
                                        'Smart zone ideas for ${guidanceRoom.name}',
                                    description:
                                        'Create exact spots now so saving and finding items later feels effortless.',
                                    suggestions:
                                        _zoneTemplatesForParent(guidanceRoom),
                                    onSuggestionTap: (template) =>
                                        _createZoneQuick(
                                      guidanceRoom,
                                      template.label,
                                      iconName: template.iconName,
                                    ),
                                  ),
                                )
                              else if (!searchState.isActive &&
                                  overview.areaCount <= 2 &&
                                  areaTemplates.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _RoomsGuidanceCard(
                                    isDark: isDark,
                                    icon: Icons.add_home_work_outlined,
                                    title: 'Popular area templates',
                                    description:
                                        'Grow your structure with one tap instead of leaving the screen feeling empty.',
                                    suggestions: areaTemplates,
                                    onSuggestionTap: (template) =>
                                        _createAreaQuick(template.label),
                                  ),
                                ),
                              ...areas.map(
                                (area) => Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _buildAreaCard(
                                    hierarchy,
                                    area,
                                    isDark: isDark,
                                    searchState: searchState,
                                  ),
                                ),
                              ),
                              if (searchState.isActive && areas.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 32),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.search_off_rounded,
                                        color: kMuted,
                                        size: 48,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No rooms or zones found.',
                                        style: TextStyle(
                                          color: kMuted,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Try another search term to find a room or zone.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: kMuted, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_isBusy) RoomsLoadingOverlay(label: _busyLabel),
          ],
        );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.onAddTap,
    required this.isSearchVisible,
    required this.searchQuery,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchTap,
    required this.onSearchChanged,
    required this.onSearchClear,
  });

  final VoidCallback onAddTap;
  final bool isSearchVisible;
  final String searchQuery;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onSearchTap;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        border: Border(
          bottom: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 0.6,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.grid_view_rounded,
                    color: AppColors.primary,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rooms & Zones',
                          style: TextStyle(
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!isSearchVisible)
                          Text(
                            'Build a clear map of where things belong',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onSearchTap,
                    icon: Icon(
                      isSearchVisible
                          ? Icons.close_rounded
                          : Icons.search_rounded,
                      color: isSearchVisible
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight),
                    ),
                  ),
                  InkWell(
                      onTap: onAddTap,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.add,
                            color: Colors.white, size: 30),
                      ),
                    ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                child: isSearchVisible
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceDark
                                : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.24),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: TextField(
                            controller: searchController,
                            focusNode: searchFocusNode,
                            onChanged: onSearchChanged,
                            textInputAction: TextInputAction.search,
                            cursorColor: AppColors.primary,
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search rooms or zones',
                              hintStyle: TextStyle(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: AppColors.primary,
                              ),
                              suffixIcon: searchQuery.isNotEmpty
                                  ? IconButton(
                                      onPressed: onSearchClear,
                                      icon: Icon(
                                        Icons.close_rounded,
                                        color: isDark
                                            ? AppColors.textSecondaryDark
                                            : AppColors.textSecondaryLight,
                                      ),
                                    )
                                  : null,
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomsSearchSummary extends StatelessWidget {
  const _RoomsSearchSummary({
    required this.query,
    required this.matchCount,
    required this.isDark,
  });

  final String query;
  final int matchCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final hasQuery = query.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              !hasQuery
                  ? 'Search this screen by room or zone name.'
                  : matchCount == 0
                      ? 'No rooms or zones matched "$query".'
                      : '$matchCount match${matchCount == 1 ? '' : 'es'} for "$query".',
              style: TextStyle(
                color: hasQuery && matchCount == 0
                    ? Colors.red.shade400
                    : (hasQuery ? textPrimary : textSecondary),
                fontSize: 13,
                fontWeight: hasQuery ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomsLocationSearchState {
  const _RoomsLocationSearchState._({
    required this.query,
    required this.matches,
    required this.matchedRoomUuids,
    required this.matchedZoneUuids,
    required this.visibleAreaUuids,
    required this.visibleRoomUuids,
    required this.visibleZoneUuids,
  });

  factory _RoomsLocationSearchState.fromQuery(
    LocationHierarchy hierarchy,
    String query,
  ) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const _RoomsLocationSearchState._(
        query: '',
        matches: <LocationModel>[],
        matchedRoomUuids: <String>{},
        matchedZoneUuids: <String>{},
        visibleAreaUuids: <String>{},
        visibleRoomUuids: <String>{},
        visibleZoneUuids: <String>{},
      );
    }

    // Search rooms and zones by name.
    final matches = hierarchy.searchLocations(
      normalizedQuery,
      types: const {LocationType.room, LocationType.zone},
      pathMatchMinTokenCount: 2,
    );
    final matchedRoomUuids = <String>{};
    final matchedZoneUuids = <String>{};
    final visibleAreaUuids = <String>{};
    final visibleRoomUuids = <String>{};
    final visibleZoneUuids = <String>{};

    // Also check if the query matches any area name — if so, show all
    // children of that area so users can search by area (e.g. "home").
    final matchedAreas = hierarchy.searchLocations(
      normalizedQuery,
      types: const {LocationType.area},
      pathMatchMinTokenCount: 2,
    );
    for (final area in matchedAreas) {
      visibleAreaUuids.add(area.uuid);
      final rooms = hierarchy.roomsForArea(area.uuid);
      for (final room in rooms) {
        matchedRoomUuids.add(room.uuid);
        visibleRoomUuids.add(room.uuid);
        for (final zone in hierarchy.zonesForRoom(room.uuid)) {
          matchedZoneUuids.add(zone.uuid);
          visibleZoneUuids.add(zone.uuid);
        }
      }
      for (final zone in hierarchy.directZonesForArea(area.uuid)) {
        matchedZoneUuids.add(zone.uuid);
        visibleZoneUuids.add(zone.uuid);
      }
    }

    for (final location in matches) {
      if (location.type == LocationType.room) {
        matchedRoomUuids.add(location.uuid);
        visibleRoomUuids.add(location.uuid);
        final area = hierarchy.areaFor(location.uuid);
        if (area != null) {
          visibleAreaUuids.add(area.uuid);
        }
        continue;
      }

      if (location.type == LocationType.zone) {
        matchedZoneUuids.add(location.uuid);
        visibleZoneUuids.add(location.uuid);
        final room = hierarchy.roomFor(location.uuid);
        if (room != null) {
          visibleRoomUuids.add(room.uuid);
        }
        final area = hierarchy.areaFor(location.uuid);
        if (area != null) {
          visibleAreaUuids.add(area.uuid);
        }
      }
    }

    // Combine direct matches with area-matched children for total count.
    final allMatchUuids = <String>{
      ...matches.map((l) => l.uuid),
      ...matchedRoomUuids,
      ...matchedZoneUuids,
    };

    return _RoomsLocationSearchState._(
      query: normalizedQuery,
      matches: allMatchUuids
          .map((uuid) => hierarchy.byUuid[uuid])
          .whereType<LocationModel>()
          .toList(),
      matchedRoomUuids: matchedRoomUuids,
      matchedZoneUuids: matchedZoneUuids,
      visibleAreaUuids: visibleAreaUuids,
      visibleRoomUuids: visibleRoomUuids,
      visibleZoneUuids: visibleZoneUuids,
    );
  }

  final String query;
  final List<LocationModel> matches;
  final Set<String> matchedRoomUuids;
  final Set<String> matchedZoneUuids;
  final Set<String> visibleAreaUuids;
  final Set<String> visibleRoomUuids;
  final Set<String> visibleZoneUuids;

  bool get isActive => query.isNotEmpty;
  int get matchCount => matches.length;

  bool isAreaVisible(String uuid) {
    return !isActive || visibleAreaUuids.contains(uuid);
  }

  bool isRoomVisible(String uuid) {
    return !isActive || visibleRoomUuids.contains(uuid);
  }

  bool isZoneVisible(String uuid) {
    return !isActive || visibleZoneUuids.contains(uuid);
  }

  bool isRoomMatch(String uuid) {
    return matchedRoomUuids.contains(uuid);
  }

  bool isZoneMatch(String uuid) {
    return matchedZoneUuids.contains(uuid);
  }
}

class _RoomsSuggestionTemplate {
  const _RoomsSuggestionTemplate({
    required this.label,
    required this.icon,
    this.iconName,
  });

  final String label;
  final IconData icon;
  final String? iconName;
}

class _RoomsSetupTask {
  const _RoomsSetupTask({
    required this.icon,
    required this.title,
    required this.description,
    required this.isComplete,
    this.actionLabel,
    this.onTap,
    this.isRecommended = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool isComplete;
  final String? actionLabel;
  final VoidCallback? onTap;
  final bool isRecommended;
}

class _RoomsStarterRoomSeed {
  const _RoomsStarterRoomSeed({
    required this.name,
    required this.zones,
    this.iconName,
  });

  final String name;
  final List<String> zones;
  final String? iconName;
}

class _RoomsStarterPack {
  const _RoomsStarterPack({
    required this.label,
    required this.areaName,
    required this.icon,
    required this.accentColor,
    required this.description,
    required this.rooms,
    this.directZones = const [],
  });

  final String label;
  final String areaName;
  final IconData icon;
  final Color accentColor;
  final String description;
  final List<_RoomsStarterRoomSeed> rooms;
  final List<String> directZones;

  int get roomCount => rooms.length;

  int get zoneCount =>
      directZones.length +
      rooms.fold<int>(0, (sum, room) => sum + room.zones.length);
}

class _RoomsOverview {
  const _RoomsOverview({
    required this.areaCount,
    required this.roomCount,
    required this.zoneCount,
    required this.itemCount,
    required this.areasWithoutRoomsCount,
    required this.roomsWithoutZonesCount,
    required this.zonesWithItemsCount,
    required this.firstAreaWithoutRooms,
    required this.firstRoomWithoutZones,
  });

  factory _RoomsOverview.fromHierarchy(
    LocationHierarchy hierarchy,
    List<LocationModel> allLocations,
    int itemCount,
  ) {
    final rooms = allLocations
        .where((location) => location.type == LocationType.room)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final zones = allLocations
        .where((location) => location.type == LocationType.zone)
        .toList(growable: false);

    LocationModel? firstAreaWithoutRooms;
    var areasWithoutRoomsCount = 0;
    for (final area in hierarchy.areas) {
      if (hierarchy.roomsForArea(area.uuid).isEmpty) {
        areasWithoutRoomsCount += 1;
        firstAreaWithoutRooms ??= area;
      }
    }

    LocationModel? firstRoomWithoutZones;
    var roomsWithoutZonesCount = 0;
    for (final room in rooms) {
      if (hierarchy.zonesForRoom(room.uuid).isEmpty) {
        roomsWithoutZonesCount += 1;
        firstRoomWithoutZones ??= room;
      }
    }

    return _RoomsOverview(
      areaCount: hierarchy.areas.length,
      roomCount: rooms.length,
      zoneCount: zones.length,
      itemCount: itemCount,
      areasWithoutRoomsCount: areasWithoutRoomsCount,
      roomsWithoutZonesCount: roomsWithoutZonesCount,
      zonesWithItemsCount: zones.where((zone) => zone.usageCount > 0).length,
      firstAreaWithoutRooms: firstAreaWithoutRooms,
      firstRoomWithoutZones: firstRoomWithoutZones,
    );
  }

  final int areaCount;
  final int roomCount;
  final int zoneCount;
  final int itemCount;
  final int areasWithoutRoomsCount;
  final int roomsWithoutZonesCount;
  final int zonesWithItemsCount;
  final LocationModel? firstAreaWithoutRooms;
  final LocationModel? firstRoomWithoutZones;
}

class _RoomsSetupProgressCard extends StatelessWidget {
  const _RoomsSetupProgressCard({
    required this.isDark,
    required this.steps,
  });

  final bool isDark;
  final List<_RoomsSetupTask> steps;

  @override
  Widget build(BuildContext context) {
    final completedCount = steps.where((step) => step.isComplete).length;
    final progress = steps.isEmpty ? 0.0 : completedCount / steps.length;
    final cardColor =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceLight;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: isDark ? 0.24 : 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.task_alt_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Setup progress',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$completedCount of ${steps.length} milestones completed',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: progress,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.primary.withValues(alpha: 0.08),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),
          ...steps.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RoomsSetupStepRow(
                step: step,
                isDark: isDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomsSetupStepRow extends StatelessWidget {
  const _RoomsSetupStepRow({
    required this.step,
    required this.isDark,
  });

  final _RoomsSetupTask step;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final rowColor = step.isRecommended
        ? AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.08)
        : (isDark
            ? Colors.white.withValues(alpha: 0.04)
            : AppColors.primary.withValues(alpha: 0.04));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: rowColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: step.isRecommended
              ? AppColors.primary.withValues(alpha: isDark ? 0.34 : 0.22)
              : Colors.transparent,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: step.isComplete
                  ? AppColors.success.withValues(alpha: 0.14)
                  : AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              step.isComplete ? Icons.check_rounded : step.icon,
              color: step.isComplete ? AppColors.success : AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.description,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                if (step.isRecommended) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Recommended next',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.primaryLight
                          : AppColors.primaryDark,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (step.isComplete)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Done',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else if (step.actionLabel != null && step.onTap != null)
            TextButton(
              onPressed: step.onTap,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                step.actionLabel!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoomsGuidanceCard extends StatelessWidget {
  const _RoomsGuidanceCard({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.description,
    required this.suggestions,
    required this.onSuggestionTap,
  });

  final bool isDark;
  final IconData icon;
  final String title;
  final String description;
  final List<_RoomsSuggestionTemplate> suggestions;
  final ValueChanged<_RoomsSuggestionTemplate> onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    final cardColor =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions
                .map(
                  (template) => _RoomsQuickCreateChip(
                    template: template,
                    isDark: isDark,
                    onTap: () => onSuggestionTap(template),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _RoomsEmptyState extends StatelessWidget {
  const _RoomsEmptyState({
    required this.isDark,
    required this.suggestedAreas,
    required this.starterPacks,
    required this.onCreateAreaTap,
    required this.onGuidedAddTap,
    required this.onSuggestionTap,
    required this.onStarterPackTap,
  });

  final bool isDark;
  final List<_RoomsSuggestionTemplate> suggestedAreas;
  final List<_RoomsStarterPack> starterPacks;
  final VoidCallback onCreateAreaTap;
  final VoidCallback onGuidedAddTap;
  final ValueChanged<_RoomsSuggestionTemplate> onSuggestionTap;
  final ValueChanged<_RoomsStarterPack> onStarterPackTap;

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: isDark ? 0.24 : 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.08),
                  ),
                ),
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.12),
                  ),
                ),
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                  ),
                  child: const Icon(
                    Icons.home_work_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Start with the spaces you naturally remember',
            style: TextStyle(
              color: textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'A clean structure makes the whole app feel smarter. Create an area first, then rooms, then exact zones where items live.',
            style: TextStyle(
              color: textSecondary,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          _RoomsSetupStep(
            number: '1',
            icon: Icons.home_work_outlined,
            title: 'Create an area',
            description: 'Examples: Home, Office, Garage, Storage.',
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _RoomsSetupStep(
            number: '2',
            icon: Icons.meeting_room_outlined,
            title: 'Add real rooms',
            description: 'Bedroom, Kitchen, Meeting Room, Tool Room.',
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _RoomsSetupStep(
            number: '3',
            icon: Icons.widgets_outlined,
            title: 'Finish with zones',
            description: 'Shelves, drawers, cabinets, bins and closets.',
            isDark: isDark,
          ),
          const SizedBox(height: 18),
          Text(
            'Quick starting points',
            style: TextStyle(
              color: textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestedAreas
                .map(
                  (template) => _RoomsQuickCreateChip(
                    template: template,
                    isDark: isDark,
                    onTap: () => onSuggestionTap(template),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 20),
          Text(
            'Ready-made starter layouts',
            style: TextStyle(
              color: textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'One tap builds a usable structure instead of leaving this screen empty.',
            style: TextStyle(
              color: textSecondary,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          ...starterPacks.map(
            (pack) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RoomsStarterPackTile(
                pack: pack,
                isDark: isDark,
                onTap: () => onStarterPackTap(pack),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCreateAreaTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.34),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.add_home_work_rounded, size: 18),
                  label: const Text(
                    'Create custom area',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onGuidedAddTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text(
                    'Guided setup',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoomsStarterPackTile extends StatelessWidget {
  const _RoomsStarterPackTile({
    required this.pack,
    required this.isDark,
    required this.onTap,
  });

  final _RoomsStarterPack pack;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            pack.accentColor.withValues(alpha: isDark ? 0.24 : 0.18),
            AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: pack.accentColor.withValues(alpha: isDark ? 0.40 : 0.22),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            pack.accentColor.withValues(alpha: 0.3),
                            pack.accentColor.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: pack.accentColor.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        pack.icon,
                        color: pack.accentColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pack.label,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pack.areaName,
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: onTap,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: pack.accentColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Use starter',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  pack.description,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _RoomsMetricPill(
                      icon: Icons.meeting_room_outlined,
                      label: '${pack.roomCount} rooms',
                      isDark: isDark,
                      isHighlighted: true,
                    ),
                    _RoomsMetricPill(
                      icon: Icons.widgets_outlined,
                      label: '${pack.zoneCount} zones',
                      isDark: isDark,
                      isHighlighted: true,
                    ),
                    _RoomsMetricPill(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Built for quick start',
                      isDark: isDark,
                      isHighlighted: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomsNestedEmptyHint extends StatelessWidget {
  const _RoomsNestedEmptyHint({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.message,
    required this.suggestions,
    this.onSuggestionTap,
  });

  final bool isDark;
  final IconData icon;
  final String title;
  final String message;
  final List<_RoomsSuggestionTemplate> suggestions;
  final ValueChanged<_RoomsSuggestionTemplate>? onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark
        ? AppColors.backgroundDark.withValues(alpha: 0.32)
        : AppColors.primary.withValues(alpha: 0.045);
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: isDark ? 0.20 : 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: textSecondary,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          if (suggestions.isNotEmpty && onSuggestionTap != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: suggestions
                  .map(
                    (template) => _RoomsQuickCreateChip(
                      template: template,
                      isDark: isDark,
                      onTap: () => onSuggestionTap!(template),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoomsQuickCreateChip extends StatelessWidget {
  const _RoomsQuickCreateChip({
    required this.template,
    required this.isDark,
    required this.onTap,
  });

  final _RoomsSuggestionTemplate template;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceDark
              : AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: isDark ? 0.28 : 0.16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(template.icon, color: AppColors.primary, size: 16),
            const SizedBox(width: 6),
            Text(
              template.label,
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomsMetricPill extends StatelessWidget {
  const _RoomsMetricPill({
    required this.icon,
    required this.label,
    required this.isDark,
    this.isHighlighted = false,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final bgColor = isHighlighted
        ? AppColors.primary.withValues(alpha: isDark ? 0.20 : 0.10)
        : (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : AppColors.primary.withValues(alpha: 0.05));
    final textColor = isHighlighted
        ? (isDark ? AppColors.primaryLight : AppColors.primary)
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomsSetupStep extends StatelessWidget {
  const _RoomsSetupStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
    required this.isDark,
  });

  final String number;
  final IconData icon;
  final String title;
  final String description;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Swipe action helpers ──────────────────────────────────────────────────────

class _SwipeActionBackground extends StatelessWidget {
  const _SwipeActionBackground({
    required this.isEdit,
    required this.borderRadius,
  });

  final bool isEdit;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isEdit ? AppColors.primary : Colors.red,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: isEdit ? Alignment.centerLeft : Alignment.centerRight,
      child: Text(
        isEdit ? 'EDIT' : 'DELETE',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
