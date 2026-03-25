import 'package:flutter_test/flutter_test.dart';
import 'package:ikeep/core/utils/location_hierarchy_utils.dart';
import 'package:ikeep/domain/models/location_model.dart';

void main() {
  group('LocationHierarchy.searchLocations', () {
    late LocationHierarchy hierarchy;

    setUp(() {
      final createdAt = DateTime(2024, 1, 1);
      hierarchy = LocationHierarchy.fromLocations([
        LocationModel(
          uuid: 'area-home',
          name: 'Home',
          type: LocationType.area,
          fullPath: 'Home',
          createdAt: createdAt,
        ),
        LocationModel(
          uuid: 'room-bedroom',
          name: 'Bedroom',
          type: LocationType.room,
          parentUuid: 'area-home',
          fullPath: 'Home > Bedroom',
          createdAt: createdAt,
        ),
        LocationModel(
          uuid: 'room-pantry',
          name: 'Pantry',
          type: LocationType.room,
          parentUuid: 'area-home',
          fullPath: 'Home > Pantry',
          createdAt: createdAt,
        ),
        LocationModel(
          uuid: 'zone-bed-drawer',
          name: 'Left Drawer',
          type: LocationType.zone,
          parentUuid: 'room-bedroom',
          fullPath: 'Home > Bedroom > Left Drawer',
          createdAt: createdAt,
        ),
        LocationModel(
          uuid: 'zone-pantry-shelf',
          name: 'Top Shelf',
          type: LocationType.zone,
          parentUuid: 'room-pantry',
          fullPath: 'Home > Pantry > Top Shelf',
          createdAt: createdAt,
        ),
      ]);
    });

    test('finds direct room name matches within scoped types', () {
      final results = hierarchy.searchLocations(
        'pantry',
        types: const {LocationType.room, LocationType.zone},
        pathMatchMinTokenCount: 2,
      );

      expect(results.map((location) => location.uuid), ['room-pantry']);
    });

    test('allows multi-token path matches for deeper room and zone queries',
        () {
      final results = hierarchy.searchLocations(
        'bedroom drawer',
        types: const {LocationType.room, LocationType.zone},
        pathMatchMinTokenCount: 2,
      );

      expect(
        results.map((location) => location.uuid),
        contains('zone-bed-drawer'),
      );
    });

    test('does not match descendant zones for single-token room queries', () {
      final results = hierarchy.searchLocations(
        'bedroom',
        types: const {LocationType.room, LocationType.zone},
        pathMatchMinTokenCount: 2,
      );

      expect(results.map((location) => location.uuid), ['room-bedroom']);
    });
  });

  group('LocationHierarchy.searchZones', () {
    test('still matches zone paths for single-token queries', () {
      final createdAt = DateTime(2024, 1, 1);
      final hierarchy = LocationHierarchy.fromLocations([
        LocationModel(
          uuid: 'area-home',
          name: 'Home',
          type: LocationType.area,
          fullPath: 'Home',
          createdAt: createdAt,
        ),
        LocationModel(
          uuid: 'room-bedroom',
          name: 'Bedroom',
          type: LocationType.room,
          parentUuid: 'area-home',
          fullPath: 'Home > Bedroom',
          createdAt: createdAt,
        ),
        LocationModel(
          uuid: 'zone-bed-drawer',
          name: 'Left Drawer',
          type: LocationType.zone,
          parentUuid: 'room-bedroom',
          fullPath: 'Home > Bedroom > Left Drawer',
          createdAt: createdAt,
        ),
      ]);

      expect(
        hierarchy.searchZones('bedroom').map((location) => location.uuid),
        ['zone-bed-drawer'],
      );
    });
  });
}
