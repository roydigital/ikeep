import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/location_model.dart';
import 'repository_providers.dart';

// ── Data providers ────────────────────────────────────────────────────────────

final allLocationsProvider = FutureProvider<List<LocationModel>>((ref) async {
  return ref.watch(locationRepositoryProvider).getAllLocations();
});

final rootLocationsProvider = FutureProvider<List<LocationModel>>((ref) async {
  return ref.watch(locationRepositoryProvider).getRootLocations();
});

final childLocationsProvider =
    FutureProvider.family<List<LocationModel>, String>(
        (ref, parentUuid) async {
  return ref.watch(locationRepositoryProvider).getChildLocations(parentUuid);
});

final singleLocationProvider =
    FutureProvider.family<LocationModel?, String>((ref, uuid) async {
  return ref.watch(locationRepositoryProvider).getLocation(uuid);
});

/// The currently selected/highlighted location in the location picker UI.
final selectedLocationProvider = StateProvider<LocationModel?>((ref) => null);

// ── Notifier for mutations ────────────────────────────────────────────────────

class LocationsNotifier extends StateNotifier<bool> {
  LocationsNotifier(this._ref) : super(false);

  final Ref _ref;

  Future<String?> saveLocation(LocationModel location) async {
    final failure =
        await _ref.read(locationRepositoryProvider).saveLocation(location);
    if (failure != null) return failure.message;
    _ref.invalidate(allLocationsProvider);
    _ref.invalidate(rootLocationsProvider);
    return null;
  }

  Future<String?> updateLocation(LocationModel location) async {
    final failure =
        await _ref.read(locationRepositoryProvider).updateLocation(location);
    if (failure != null) return failure.message;
    _ref.invalidate(allLocationsProvider);
    _ref.invalidate(singleLocationProvider(location.uuid));
    return null;
  }

  Future<String?> deleteLocation(String uuid) async {
    final failure =
        await _ref.read(locationRepositoryProvider).deleteLocation(uuid);
    if (failure != null) return failure.message;
    _ref.invalidate(allLocationsProvider);
    _ref.invalidate(rootLocationsProvider);
    return null;
  }
}

final locationsNotifierProvider =
    StateNotifierProvider<LocationsNotifier, bool>(
        (ref) => LocationsNotifier(ref));
