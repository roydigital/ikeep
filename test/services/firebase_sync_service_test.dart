import 'package:flutter_test/flutter_test.dart';
import 'package:ikeep/domain/models/location_model.dart';
import 'package:ikeep/services/firebase_sync_service.dart';

void main() {
  group('orderLocationsForLocalUpsert', () {
    test('orders parent locations before children', () {
      final parent = LocationModel(
        uuid: 'room',
        name: 'Bedroom',
        type: LocationType.room,
        fullPath: 'Home > Bedroom',
        createdAt: DateTime(2026, 3, 23, 10),
      );
      final child = LocationModel(
        uuid: 'bed',
        name: 'Pihu Room',
        type: LocationType.zone,
        fullPath: 'Home > Bedroom > Pihu Room',
        parentUuid: 'room',
        createdAt: DateTime(2026, 3, 23, 11),
      );

      final ordered = orderLocationsForLocalUpsert(
        locations: [child, parent],
        existingLocationUuids: const {},
      );

      expect(ordered.map((location) => location.uuid).toList(), [
        'room',
        'bed',
      ]);
    });

    test('promotes orphaned location to root instead of blocking restore', () {
      final orphan = LocationModel(
        uuid: 'child',
        name: 'Loose Shelf',
        type: LocationType.room,
        fullPath: 'Home > Missing Parent > Loose Shelf',
        parentUuid: 'missing-parent',
        createdAt: DateTime(2026, 3, 23, 12),
      );
      final dependentChild = LocationModel(
        uuid: 'grandchild',
        name: 'Drawer',
        type: LocationType.zone,
        fullPath: 'Home > Missing Parent > Loose Shelf > Drawer',
        parentUuid: 'child',
        createdAt: DateTime(2026, 3, 23, 13),
      );

      final ordered = orderLocationsForLocalUpsert(
        locations: [dependentChild, orphan],
        existingLocationUuids: const {},
      );

      expect(ordered.first.uuid, 'child');
      expect(ordered.first.parentUuid, isNull);
      expect(ordered.last.uuid, 'grandchild');
      expect(ordered.last.parentUuid, 'child');
    });
  });
}
