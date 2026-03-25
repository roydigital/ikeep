import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/area.dart';
import '../domain/models/room.dart';
import '../domain/models/sync_status.dart';
import '../domain/models/zone.dart';
import 'location_providers.dart';
import 'repository_providers.dart';
import 'service_providers.dart';
import 'sync_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Read providers
// ─────────────────────────────────────────────────────────────────────────────

/// All top-level areas, sorted by usage count desc then name asc.
final areasProvider = FutureProvider<List<Area>>((ref) {
  return ref.watch(locationHierarchyRepositoryProvider).getAreas();
});

/// Rooms belonging to a specific area UUID.
/// Auto-refreshes when [allLocationsProvider] is invalidated (i.e. after any
/// save / update / delete via [locationsNotifierProvider]).
final roomsForAreaProvider =
    FutureProvider.family<List<Room>, String>((ref, areaUuid) {
  // Watch allLocationsProvider so this cache invalidates whenever any location
  // is mutated — keeps room lists in sync without manual invalidation.
  ref.watch(allLocationsProvider);
  return ref
      .watch(locationHierarchyRepositoryProvider)
      .getRoomsForArea(areaUuid);
});

/// Zones whose direct parent is a room.
final zonesForRoomProvider =
    FutureProvider.family<List<Zone>, String>((ref, roomUuid) {
  ref.watch(allLocationsProvider);
  return ref
      .watch(locationHierarchyRepositoryProvider)
      .getZonesForRoom(roomUuid);
});

/// Zones attached directly to an area (no room parent).
/// Used for Garages, Storerooms, etc. where rooms aren't needed.
final directZonesForAreaProvider =
    FutureProvider.family<List<Zone>, String>((ref, areaUuid) {
  ref.watch(allLocationsProvider);
  return ref
      .watch(locationHierarchyRepositoryProvider)
      .getDirectZonesForArea(areaUuid);
});

/// Resolves a [Zone] by UUID with all hierarchy fields populated
/// (areaUuid, roomUuid, areaName, roomName).
/// Returns null if the UUID doesn't exist or isn't a zone.
final resolvedZoneProvider =
    FutureProvider.family<Zone?, String>((ref, zoneUuid) {
  ref.watch(allLocationsProvider);
  return ref
      .watch(locationHierarchyRepositoryProvider)
      .resolveZone(zoneUuid);
});

// ─────────────────────────────────────────────────────────────────────────────
// Write notifier
// ─────────────────────────────────────────────────────────────────────────────

/// Handles typed create / update / delete for Areas, Rooms, and Zones.
///
/// After every mutation it invalidates [allLocationsProvider] so all
/// downstream FutureProviders (areasProvider, roomsForAreaProvider, etc.)
/// automatically reload.
class LocationHierarchyNotifier extends StateNotifier<bool> {
  LocationHierarchyNotifier(this._ref) : super(false);

  final Ref _ref;

  // ── Areas ────────────────────────────────────────────────────────────────

  Future<String?> saveArea(Area area) async {
    final failure = await _ref
        .read(locationHierarchyRepositoryProvider)
        .saveArea(area);
    if (failure != null) return failure.message;
    await _syncAndRefresh(area.toLocation());
    return null;
  }

  Future<String?> updateArea(Area area) async {
    final failure = await _ref
        .read(locationHierarchyRepositoryProvider)
        .updateArea(area);
    if (failure != null) return failure.message;
    await _syncAndRefresh(area.toLocation());
    return null;
  }

  Future<String?> deleteArea(String areaUuid) async {
    final failure = await _ref
        .read(locationHierarchyRepositoryProvider)
        .deleteArea(areaUuid);
    if (failure != null) return failure.message;
    await _syncDeleteAndRefresh(areaUuid);
    return null;
  }

  // ── Rooms ────────────────────────────────────────────────────────────────

  Future<String?> saveRoom(Room room) async {
    final failure = await _ref
        .read(locationHierarchyRepositoryProvider)
        .saveRoom(room);
    if (failure != null) return failure.message;
    await _syncAndRefresh(room.toLocation());
    return null;
  }

  Future<String?> updateRoom(Room room) async {
    final failure = await _ref
        .read(locationHierarchyRepositoryProvider)
        .updateRoom(room);
    if (failure != null) return failure.message;
    await _syncAndRefresh(room.toLocation());
    return null;
  }

  Future<String?> deleteRoom(String roomUuid) async {
    final failure = await _ref
        .read(locationHierarchyRepositoryProvider)
        .deleteRoom(roomUuid);
    if (failure != null) return failure.message;
    await _syncDeleteAndRefresh(roomUuid);
    return null;
  }

  // ── Zones ────────────────────────────────────────────────────────────────

  Future<String?> saveZone(Zone zone) async {
    final failure = await _ref
        .read(locationHierarchyRepositoryProvider)
        .saveZone(zone);
    if (failure != null) return failure.message;
    await _syncAndRefresh(zone.toLocation());
    return null;
  }

  Future<String?> updateZone(Zone zone) async {
    final failure = await _ref
        .read(locationHierarchyRepositoryProvider)
        .updateZone(zone);
    if (failure != null) return failure.message;
    await _syncAndRefresh(zone.toLocation());
    return null;
  }

  Future<String?> deleteZone(String zoneUuid) async {
    final failure = await _ref
        .read(locationHierarchyRepositoryProvider)
        .deleteZone(zoneUuid);
    if (failure != null) return failure.message;
    await _syncDeleteAndRefresh(zoneUuid);
    return null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _syncAndRefresh(dynamic location) async {
    // Delegate to the existing sync pipeline so cloud backup stays consistent.
    final result =
        await _ref.read(syncServiceProvider).syncLocation(location);
    _ref.read(syncStatusProvider.notifier).state = result;
    _ref.invalidate(lastSyncedAtProvider);
    // Invalidate root provider — all downstream family providers auto-refresh.
    _ref.invalidate(allLocationsProvider);
  }

  Future<void> _syncDeleteAndRefresh(String uuid) async {
    final result =
        await _ref.read(syncServiceProvider).deleteRemoteLocation(uuid);
    if (result.status != SyncStatus.error) {
      _ref.read(syncStatusProvider.notifier).state = result;
      _ref.invalidate(lastSyncedAtProvider);
    }
    _ref.invalidate(allLocationsProvider);
  }
}

final locationHierarchyNotifierProvider =
    StateNotifierProvider<LocationHierarchyNotifier, bool>(
  (ref) => LocationHierarchyNotifier(ref),
);

// ─────────────────────────────────────────────────────────────────────────────
// LocationSelectionState — UI state for the cascading location picker
// ─────────────────────────────────────────────────────────────────────────────

/// Immutable snapshot of the user's current in-progress location selection.
///
/// The cascade rule:
/// - Changing [selectedAreaUuid] → resets room and zone.
/// - Changing [selectedRoomUuid] → resets zone only.
/// - Changing [selectedZoneUuid] → no cascade.
class LocationSelectionState {
  const LocationSelectionState({
    this.selectedAreaUuid,
    this.selectedRoomUuid,
    this.selectedZoneUuid,
  });

  final String? selectedAreaUuid;
  final String? selectedRoomUuid;
  final String? selectedZoneUuid;

  /// True once the user has chosen a zone — the minimum to save an item.
  bool get isComplete => selectedZoneUuid != null;

  bool get hasArea => selectedAreaUuid != null;
  bool get hasRoom => selectedRoomUuid != null;
  bool get hasZone => selectedZoneUuid != null;

  LocationSelectionState copyWith({
    String? selectedAreaUuid,
    String? selectedRoomUuid,
    String? selectedZoneUuid,
    bool clearArea = false,
    bool clearRoom = false,
    bool clearZone = false,
  }) {
    return LocationSelectionState(
      selectedAreaUuid:
          clearArea ? null : (selectedAreaUuid ?? this.selectedAreaUuid),
      selectedRoomUuid:
          clearRoom ? null : (selectedRoomUuid ?? this.selectedRoomUuid),
      selectedZoneUuid:
          clearZone ? null : (selectedZoneUuid ?? this.selectedZoneUuid),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocationSelectionState &&
          other.selectedAreaUuid == selectedAreaUuid &&
          other.selectedRoomUuid == selectedRoomUuid &&
          other.selectedZoneUuid == selectedZoneUuid);

  @override
  int get hashCode => Object.hash(
        selectedAreaUuid,
        selectedRoomUuid,
        selectedZoneUuid,
      );

  @override
  String toString() =>
      'LocationSelectionState(area: $selectedAreaUuid, '
      'room: $selectedRoomUuid, zone: $selectedZoneUuid)';
}

// ─────────────────────────────────────────────────────────────────────────────
// LocationSelectionController — notifier driving the cascading picker UI
// ─────────────────────────────────────────────────────────────────────────────

/// Manages which Area / Room / Zone the user has selected during item
/// creation or editing. Lives only as long as the screen that uses it
/// (auto-dispose).
///
/// Usage in a screen:
/// ```dart
/// final selection = ref.watch(locationSelectionProvider);
/// ref.read(locationSelectionProvider.notifier).selectArea(uuid);
/// ```
class LocationSelectionController
    extends AutoDisposeNotifier<LocationSelectionState> {
  @override
  LocationSelectionState build() => const LocationSelectionState();

  // ── Selection actions ─────────────────────────────────────────────────────

  /// Selects a new area. **Cascades**: resets room and zone to null.
  void selectArea(String areaUuid) {
    // Full reset — only the area is kept.
    state = LocationSelectionState(selectedAreaUuid: areaUuid);
  }

  /// Selects or deselects a room within the current area.
  /// Pass null to revert to "no room" (direct-area-zone mode).
  /// **Cascades**: resets zone to null.
  void selectRoom(String? roomUuid) {
    state = state.copyWith(
      selectedRoomUuid: roomUuid,
      clearRoom: roomUuid == null,
      clearZone: true,
    );
  }

  /// Selects the final zone. No cascade.
  void selectZone(String zoneUuid) {
    state = state.copyWith(selectedZoneUuid: zoneUuid);
  }

  // ── Bulk setters ──────────────────────────────────────────────────────────

  /// Pre-populates all three levels from an existing item's FK fields.
  /// Call this when opening the picker during item editing.
  void initFromItem({
    required String? areaUuid,
    required String? roomUuid,
    required String? zoneUuid,
  }) {
    state = LocationSelectionState(
      selectedAreaUuid: areaUuid,
      selectedRoomUuid: roomUuid,
      selectedZoneUuid: zoneUuid,
    );
  }

  /// Resets all selections back to empty.
  void clear() => state = const LocationSelectionState();
}

/// Auto-dispose: a fresh controller is created every time a new
/// Save/Edit screen is pushed, and torn down when the screen is popped.
final locationSelectionProvider = AutoDisposeNotifierProvider<
    LocationSelectionController, LocationSelectionState>(
  LocationSelectionController.new,
);
