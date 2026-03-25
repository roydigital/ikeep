import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ikeep/data/repositories/item_repository.dart';
import 'package:ikeep/domain/models/item.dart';
import 'package:ikeep/domain/models/sync_status.dart';
import 'package:ikeep/providers/item_providers.dart';
import 'package:ikeep/providers/repository_providers.dart';
import 'package:ikeep/providers/service_providers.dart';
import 'package:ikeep/providers/settings_provider.dart';
import 'package:ikeep/providers/sync_providers.dart';
import 'package:ikeep/services/ml_label_service.dart';
import 'package:ikeep/services/notification_service.dart';
import 'package:ikeep/services/sync_service.dart';

class MockItemRepository extends Mock implements ItemRepository {}

class MockSyncService extends Mock implements SyncService {}

class MockNotificationService extends Mock implements NotificationService {}

class MockMlLabelService extends Mock implements MlLabelService {}

class FakeItem extends Fake implements Item {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(FakeItem());
  });

  group('ItemsNotifier cloud sync status handling', () {
    late MockItemRepository mockItemRepository;
    late MockSyncService mockSyncService;
    late MockNotificationService mockNotificationService;
    late MockMlLabelService mockMlLabelService;
    late ProviderContainer container;

    setUp(() {
      mockItemRepository = MockItemRepository();
      mockSyncService = MockSyncService();
      mockNotificationService = MockNotificationService();
      mockMlLabelService = MockMlLabelService();

      when(() => mockSyncService.getLastSyncedAt())
          .thenAnswer((_) async => null);
      when(() => mockNotificationService.cancelExpiryReminder(any()))
          .thenAnswer((_) async {});
      when(() => mockNotificationService.cancelLentReminder(any()))
          .thenAnswer((_) async {});

      container = ProviderContainer(
        overrides: [
          itemRepositoryProvider.overrideWithValue(mockItemRepository),
          syncServiceProvider.overrideWithValue(mockSyncService),
          notificationServiceProvider
              .overrideWithValue(mockNotificationService),
          mlLabelServiceProvider.overrideWithValue(mockMlLabelService),
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier(
              initialSettings: const AppSettings(
                stillThereRemindersEnabled: false,
                expiryRemindersEnabled: false,
                seasonalRemindersEnabled: false,
                lentRemindersEnabled: false,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    test(
        'archive keeps prior sync status and returns a cloud warning when sync fails',
        () async {
      final archivedItem = Item(
        uuid: 'item-1',
        name: 'Passport',
        savedAt: DateTime(2026, 3, 24),
        updatedAt: DateTime(2026, 3, 24, 10),
        isArchived: true,
        isBackedUp: true,
        cloudId: 'cloud-1',
        lastSyncedAt: DateTime(2026, 3, 24, 9),
      );

      when(() => mockItemRepository.archiveItem('item-1'))
          .thenAnswer((_) async => null);
      when(() => mockItemRepository.getItem('item-1'))
          .thenAnswer((_) async => archivedItem);
      when(() => mockSyncService.syncItem(any())).thenAnswer(
        (_) async => const SyncResult.error('Cloud update failed'),
      );

      container.read(syncStatusProvider.notifier).state = SyncResult.success();

      final result =
          await container.read(itemsNotifierProvider.notifier).archiveItem(
                'item-1',
              );

      expect(result.hasFailure, isFalse);
      expect(result.cloudWarning, 'Cloud update failed');
      expect(container.read(syncStatusProvider).status, SyncStatus.success);
    });
  });

  group('dashboard item providers', () {
    late MockItemRepository mockItemRepository;
    late ProviderContainer container;

    setUp(() {
      mockItemRepository = MockItemRepository();
      container = ProviderContainer(
        overrides: [
          itemRepositoryProvider.overrideWithValue(mockItemRepository),
        ],
      );
      addTearDown(container.dispose);
    });

    test(
        'expiringSoonItemsProvider keeps only active items within the dashboard window and sorts by nearest expiry',
        () async {
      final today = dashboardDateOnly(DateTime.now());
      final items = [
        Item(
          uuid: 'expiring-2',
          name: 'Protein Powder',
          savedAt: today,
          expiryDate: today.add(const Duration(days: 5)),
        ),
        Item(
          uuid: 'expired',
          name: 'Old Medicine',
          savedAt: today,
          expiryDate: today.subtract(const Duration(days: 1)),
        ),
        Item(
          uuid: 'expiring-1',
          name: 'Milk',
          savedAt: today,
          expiryDate: today.add(const Duration(days: 1)),
        ),
        Item(
          uuid: 'archived',
          name: 'Archived Yogurt',
          savedAt: today,
          expiryDate: today.add(const Duration(days: 2)),
          isArchived: true,
        ),
        Item(
          uuid: 'later',
          name: 'Rice',
          savedAt: today,
          expiryDate: today.add(
            const Duration(days: dashboardExpiringSoonWindowDays + 1),
          ),
        ),
      ];

      when(() => mockItemRepository.getAllItems())
          .thenAnswer((_) async => items);

      final result = await container.read(expiringSoonItemsProvider.future);

      expect(result.map((item) => item.uuid), ['expiring-1', 'expiring-2']);
    });

    test(
        'lentItemsProvider places dated returns first by nearest due date and keeps undated shared items after them',
        () async {
      final today = dashboardDateOnly(DateTime.now());
      final items = [
        Item(
          uuid: 'no-date',
          name: 'Camping Stove',
          savedAt: today,
          isLent: true,
          lentOn: today.subtract(const Duration(days: 4)),
        ),
        Item(
          uuid: 'due-later',
          name: 'Projector',
          savedAt: today,
          isLent: true,
          expectedReturnDate: today.add(const Duration(days: 5)),
        ),
        Item(
          uuid: 'due-soon',
          name: 'Ladder',
          savedAt: today,
          isLent: true,
          expectedReturnDate: today.add(const Duration(days: 1)),
        ),
      ];

      when(() => mockItemRepository.getAllItems())
          .thenAnswer((_) async => items);

      final result = await container.read(lentItemsProvider.future);

      expect(result.map((item) => item.uuid),
          ['due-soon', 'due-later', 'no-date']);
    });
  });
}
