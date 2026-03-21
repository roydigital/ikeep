import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ikeep/domain/models/item.dart';
import 'package:ikeep/domain/models/item_visibility.dart';

void main() {
  /// Canonical item used across most tests.
  Item createTestItem({
    String uuid = 'test-uuid-123',
    String name = 'Battery Pack',
    String? locationUuid = 'loc-001',
    List<String> imagePaths = const ['/img/a.jpg', '/img/b.jpg'],
    List<String> tags = const ['electronics', 'travel'],
    DateTime? savedAt,
    DateTime? updatedAt,
    double? latitude = 12.97,
    double? longitude = 77.59,
    DateTime? expiryDate,
    bool isArchived = false,
    String? notes = 'spare charger',
    String? cloudId = 'cloud-001',
    DateTime? lastSyncedAt,
    bool isBackedUp = true,
    bool isLent = false,
    String? lentTo,
    DateTime? lentOn,
    DateTime? expectedReturnDate,
    String seasonCategory = 'all_year',
    int? lentReminderAfterDays,
    bool isAvailableForLending = false,
    ItemVisibility visibility = ItemVisibility.private_,
    String? householdId,
    List<String> sharedWithMemberUuids = const [],
  }) {
    return Item(
      uuid: uuid,
      name: name,
      locationUuid: locationUuid,
      imagePaths: imagePaths,
      tags: tags,
      savedAt: savedAt ?? DateTime(2025, 6, 15, 10, 30),
      updatedAt: updatedAt ?? DateTime(2025, 6, 16, 8, 0),
      latitude: latitude,
      longitude: longitude,
      expiryDate: expiryDate ?? DateTime(2026, 6, 15),
      isArchived: isArchived,
      notes: notes,
      cloudId: cloudId,
      lastSyncedAt: lastSyncedAt ?? DateTime(2025, 6, 16, 9, 0),
      isBackedUp: isBackedUp,
      isLent: isLent,
      lentTo: lentTo,
      lentOn: lentOn,
      expectedReturnDate: expectedReturnDate,
      seasonCategory: seasonCategory,
      lentReminderAfterDays: lentReminderAfterDays,
      isAvailableForLending: isAvailableForLending,
      visibility: visibility,
      householdId: householdId,
      sharedWithMemberUuids: sharedWithMemberUuids,
    );
  }

  group('Item.toMap / Item.fromMap (SQLite round-trip)', () {
    test('round-trips all fields correctly', () {
      final item = createTestItem();
      final map = item.toMap();
      final restored = Item.fromMap(map);

      expect(restored.uuid, item.uuid);
      expect(restored.name, item.name);
      expect(restored.locationUuid, item.locationUuid);
      expect(restored.imagePaths, item.imagePaths);
      expect(restored.tags, item.tags);
      expect(restored.savedAt, item.savedAt);
      expect(restored.updatedAt, item.updatedAt);
      expect(restored.latitude, item.latitude);
      expect(restored.longitude, item.longitude);
      expect(restored.expiryDate, item.expiryDate);
      expect(restored.isArchived, item.isArchived);
      expect(restored.notes, item.notes);
      expect(restored.cloudId, item.cloudId);
      expect(restored.lastSyncedAt, item.lastSyncedAt);
      expect(restored.isBackedUp, item.isBackedUp);
      expect(restored.isLent, item.isLent);
      expect(restored.seasonCategory, item.seasonCategory);
      expect(restored.isAvailableForLending, item.isAvailableForLending);
      expect(restored.visibility, item.visibility);
      expect(restored.sharedWithMemberUuids, item.sharedWithMemberUuids);
    });

    test('stores booleans as integers (SQLite convention)', () {
      final map = createTestItem(
        isArchived: true,
        isBackedUp: true,
        isLent: true,
        isAvailableForLending: true,
      ).toMap();

      expect(map['is_archived'], 1);
      expect(map['is_backed_up'], 1);
      expect(map['is_lent'], 1);
      expect(map['is_available_for_lending'], 1);
    });

    test('stores false booleans as 0', () {
      final map = createTestItem(
        isArchived: false,
        isBackedUp: false,
        isLent: false,
        isAvailableForLending: false,
      ).toMap();

      expect(map['is_archived'], 0);
      expect(map['is_backed_up'], 0);
      expect(map['is_lent'], 0);
      expect(map['is_available_for_lending'], 0);
    });

    test('stores dates as millisecondsSinceEpoch', () {
      final item = createTestItem();
      final map = item.toMap();

      expect(map['saved_at'], item.savedAt.millisecondsSinceEpoch);
      expect(map['updated_at'], item.updatedAt!.millisecondsSinceEpoch);
      expect(map['expiry_date'], item.expiryDate!.millisecondsSinceEpoch);
    });

    test('encodes imagePaths and tags as JSON strings', () {
      final map = createTestItem().toMap();

      expect(map['image_paths'], isA<String>());
      expect(map['tags'], isA<String>());
      expect(jsonDecode(map['image_paths'] as String), ['/img/a.jpg', '/img/b.jpg']);
      expect(jsonDecode(map['tags'] as String), ['electronics', 'travel']);
    });

    test('handles null optional fields gracefully', () {
      // Build directly to avoid createTestItem's default ?? values.
      final item = Item(
        uuid: 'null-test',
        name: 'Minimal',
        savedAt: DateTime(2025, 1, 1),
      );
      final map = item.toMap();
      final restored = Item.fromMap(map);

      expect(restored.locationUuid, isNull);
      expect(restored.updatedAt, isNull);
      expect(restored.expiryDate, isNull);
      expect(restored.notes, isNull);
      expect(restored.cloudId, isNull);
      expect(restored.lastSyncedAt, isNull);
      expect(restored.lentTo, isNull);
      expect(restored.lentOn, isNull);
      expect(restored.expectedReturnDate, isNull);
      expect(restored.lentReminderAfterDays, isNull);
      expect(restored.householdId, isNull);
    });

    test('handles empty lists correctly', () {
      final item = createTestItem(
        imagePaths: const [],
        tags: const [],
        sharedWithMemberUuids: const [],
      );
      final restored = Item.fromMap(item.toMap());

      expect(restored.imagePaths, isEmpty);
      expect(restored.tags, isEmpty);
      expect(restored.sharedWithMemberUuids, isEmpty);
    });

    test('fromMap defaults missing boolean columns to false/0', () {
      // Simulate a row where boolean columns are missing entirely.
      final minimalMap = {
        'uuid': 'u1',
        'name': 'Test',
        'saved_at': DateTime.now().millisecondsSinceEpoch,
      };
      final item = Item.fromMap(minimalMap);

      expect(item.isArchived, false);
      expect(item.isBackedUp, false);
      expect(item.isLent, false);
      expect(item.isAvailableForLending, false);
    });

    test('stores visibility as its string value', () {
      final map = createTestItem(visibility: ItemVisibility.household).toMap();
      expect(map['visibility'], 'household');
    });

    test('round-trips household visibility', () {
      final item = createTestItem(visibility: ItemVisibility.household);
      final restored = Item.fromMap(item.toMap());
      expect(restored.visibility, ItemVisibility.household);
    });

    test('does not include joined display fields in toMap', () {
      final map = createTestItem().toMap();
      expect(map.containsKey('location_name'), isFalse);
      expect(map.containsKey('location_full_path'), isFalse);
    });

    test('fromMap reads joined display fields when present', () {
      final map = createTestItem().toMap();
      map['location_name'] = 'Kitchen';
      map['location_full_path'] = 'Home > Kitchen';

      final item = Item.fromMap(map);
      expect(item.locationName, 'Kitchen');
      expect(item.locationFullPath, 'Home > Kitchen');
    });

    test('round-trips lending fields', () {
      final item = createTestItem(
        isLent: true,
        lentTo: 'Alice',
        lentOn: DateTime(2025, 7, 1),
        expectedReturnDate: DateTime(2025, 8, 1),
        lentReminderAfterDays: 7,
        isAvailableForLending: true,
      );
      final restored = Item.fromMap(item.toMap());

      expect(restored.isLent, true);
      expect(restored.lentTo, 'Alice');
      expect(restored.lentOn, DateTime(2025, 7, 1));
      expect(restored.expectedReturnDate, DateTime(2025, 8, 1));
      expect(restored.lentReminderAfterDays, 7);
      expect(restored.isAvailableForLending, true);
    });
  });

  group('Item.toJson / Item.fromJson (cloud sync round-trip)', () {
    test('round-trips all fields correctly', () {
      final item = createTestItem();
      final json = item.toJson();
      final restored = Item.fromJson(json);

      expect(restored.uuid, item.uuid);
      expect(restored.name, item.name);
      expect(restored.locationUuid, item.locationUuid);
      expect(restored.imagePaths, item.imagePaths);
      expect(restored.tags, item.tags);
      expect(restored.savedAt.toIso8601String(), item.savedAt.toIso8601String());
      expect(restored.latitude, item.latitude);
      expect(restored.longitude, item.longitude);
      expect(restored.isArchived, item.isArchived);
      expect(restored.notes, item.notes);
      expect(restored.cloudId, item.cloudId);
      expect(restored.isBackedUp, item.isBackedUp);
      expect(restored.visibility, item.visibility);
      expect(restored.seasonCategory, item.seasonCategory);
    });

    test('uses ISO 8601 strings for dates', () {
      final json = createTestItem().toJson();

      expect(json['savedAt'], isA<String>());
      expect(json['updatedAt'], isA<String>());
      expect(json['expiryDate'], isA<String>());
    });

    test('stores lists directly (not JSON-encoded strings)', () {
      final json = createTestItem().toJson();

      expect(json['imagePaths'], isA<List>());
      expect(json['tags'], isA<List>());
      expect(json['sharedWithMemberUuids'], isA<List>());
    });

    test('stores booleans as native booleans (not ints)', () {
      final json = createTestItem(isArchived: true, isBackedUp: true).toJson();

      expect(json['isArchived'], isA<bool>());
      expect(json['isArchived'], true);
      expect(json['isBackedUp'], true);
    });

    test('handles null optional fields', () {
      // Build directly to avoid createTestItem's default ?? values.
      final json = Item(
        uuid: 'null-test',
        name: 'Minimal',
        savedAt: DateTime(2025, 1, 1),
      ).toJson();

      expect(json['locationUuid'], isNull);
      expect(json['updatedAt'], isNull);
      expect(json['expiryDate'], isNull);
      expect(json['notes'], isNull);
      expect(json['cloudId'], isNull);
      expect(json['lastSyncedAt'], isNull);
      expect(json['householdId'], isNull);
    });

    test('fromJson handles missing list fields as empty', () {
      final json = createTestItem().toJson();
      json.remove('imagePaths');
      json.remove('tags');
      json.remove('sharedWithMemberUuids');

      final restored = Item.fromJson(json);
      expect(restored.imagePaths, isEmpty);
      expect(restored.tags, isEmpty);
      expect(restored.sharedWithMemberUuids, isEmpty);
    });

    test('fromJson handles num latitude/longitude (API returns int or double)', () {
      final json = createTestItem().toJson();
      json['latitude'] = 13; // int, not double
      json['longitude'] = 77; // int, not double

      final restored = Item.fromJson(json);
      expect(restored.latitude, 13.0);
      expect(restored.longitude, 77.0);
    });

    test('does not include joined display fields', () {
      final json = createTestItem().toJson();
      expect(json.containsKey('locationName'), isFalse);
      expect(json.containsKey('locationFullPath'), isFalse);
    });
  });

  group('Item.copyWith', () {
    test('returns a new instance (immutability)', () {
      final original = createTestItem();
      final copy = original.copyWith(name: 'New Name');

      expect(identical(original, copy), isFalse);
      expect(original.name, 'Battery Pack');
      expect(copy.name, 'New Name');
    });

    test('preserves all fields when called with no arguments', () {
      final original = createTestItem();
      final copy = original.copyWith();

      expect(copy.uuid, original.uuid);
      expect(copy.name, original.name);
      expect(copy.locationUuid, original.locationUuid);
      expect(copy.imagePaths, original.imagePaths);
      expect(copy.tags, original.tags);
      expect(copy.savedAt, original.savedAt);
      expect(copy.updatedAt, original.updatedAt);
      expect(copy.latitude, original.latitude);
      expect(copy.longitude, original.longitude);
      expect(copy.expiryDate, original.expiryDate);
      expect(copy.isArchived, original.isArchived);
      expect(copy.notes, original.notes);
      expect(copy.cloudId, original.cloudId);
      expect(copy.lastSyncedAt, original.lastSyncedAt);
      expect(copy.isBackedUp, original.isBackedUp);
      expect(copy.isLent, original.isLent);
      expect(copy.seasonCategory, original.seasonCategory);
      expect(copy.visibility, original.visibility);
      expect(copy.householdId, original.householdId);
      expect(copy.sharedWithMemberUuids, original.sharedWithMemberUuids);
    });

    test('clearLocationUuid sets locationUuid to null', () {
      final item = createTestItem(locationUuid: 'loc-001');
      final copy = item.copyWith(clearLocationUuid: true);

      expect(copy.locationUuid, isNull);
    });

    test('clearExpiryDate sets expiryDate to null', () {
      final item = createTestItem(expiryDate: DateTime(2026, 1, 1));
      final copy = item.copyWith(clearExpiryDate: true);

      expect(copy.expiryDate, isNull);
    });

    test('clearNotes sets notes to null', () {
      final item = createTestItem(notes: 'some notes');
      final copy = item.copyWith(clearNotes: true);

      expect(copy.notes, isNull);
    });

    test('clearCloudId sets cloudId to null', () {
      final item = createTestItem(cloudId: 'cloud-001');
      final copy = item.copyWith(clearCloudId: true);

      expect(copy.cloudId, isNull);
    });

    test('clearLastSyncedAt sets lastSyncedAt to null', () {
      final item = createTestItem(lastSyncedAt: DateTime.now());
      final copy = item.copyWith(clearLastSyncedAt: true);

      expect(copy.lastSyncedAt, isNull);
    });

    test('clearLentTo sets lentTo to null', () {
      final item = createTestItem(lentTo: 'Alice');
      final copy = item.copyWith(clearLentTo: true);

      expect(copy.lentTo, isNull);
    });

    test('clearLentOn sets lentOn to null', () {
      final item = createTestItem(lentOn: DateTime.now());
      final copy = item.copyWith(clearLentOn: true);

      expect(copy.lentOn, isNull);
    });

    test('clearExpectedReturnDate sets expectedReturnDate to null', () {
      final item = createTestItem(expectedReturnDate: DateTime.now());
      final copy = item.copyWith(clearExpectedReturnDate: true);

      expect(copy.expectedReturnDate, isNull);
    });

    test('clearLentReminderAfterDays sets lentReminderAfterDays to null', () {
      final item = createTestItem(lentReminderAfterDays: 7);
      final copy = item.copyWith(clearLentReminderAfterDays: true);

      expect(copy.lentReminderAfterDays, isNull);
    });

    test('clearHouseholdId sets householdId to null', () {
      final item = createTestItem(householdId: 'hh-001');
      final copy = item.copyWith(clearHouseholdId: true);

      expect(copy.householdId, isNull);
    });

    test('clear flag takes precedence over a new value', () {
      final item = createTestItem(notes: 'old');
      final copy = item.copyWith(notes: 'new', clearNotes: true);

      // clearNotes = true should win
      expect(copy.notes, isNull);
    });

    test('updates multiple fields simultaneously', () {
      final item = createTestItem();
      final copy = item.copyWith(
        name: 'Updated',
        isArchived: true,
        visibility: ItemVisibility.household,
        tags: ['new-tag'],
      );

      expect(copy.name, 'Updated');
      expect(copy.isArchived, true);
      expect(copy.visibility, ItemVisibility.household);
      expect(copy.tags, ['new-tag']);
      // Unchanged fields remain
      expect(copy.uuid, item.uuid);
      expect(copy.imagePaths, item.imagePaths);
    });
  });

  group('Item equality and hashCode', () {
    test('two items with same uuid are equal', () {
      final a = createTestItem(uuid: 'same-id', name: 'Item A');
      final b = createTestItem(uuid: 'same-id', name: 'Item B');

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('two items with different uuids are not equal', () {
      final a = createTestItem(uuid: 'id-1');
      final b = createTestItem(uuid: 'id-2');

      expect(a, isNot(equals(b)));
    });
  });

  group('Computed getters', () {
    test('isShared is always false (social sharing disabled)', () {
      final item = createTestItem(visibility: ItemVisibility.household);
      expect(item.isShared, false);
    });

    test('isNearby is always false (nearby sharing disabled)', () {
      final item = createTestItem();
      expect(item.isNearby, false);
    });
  });

  group('ItemVisibility', () {
    test('fromString returns private_ for null', () {
      expect(ItemVisibility.fromString(null), ItemVisibility.private_);
    });

    test('fromString returns private_ for unknown string', () {
      expect(ItemVisibility.fromString('unknown'), ItemVisibility.private_);
    });

    test('fromString parses household', () {
      expect(ItemVisibility.fromString('household'), ItemVisibility.household);
    });

    test('fromString parses private', () {
      expect(ItemVisibility.fromString('private'), ItemVisibility.private_);
    });

    test('convenience getters', () {
      expect(ItemVisibility.household.isHousehold, true);
      expect(ItemVisibility.household.isPrivate, false);
      expect(ItemVisibility.private_.isPrivate, true);
      expect(ItemVisibility.private_.isHousehold, false);
    });
  });
}
