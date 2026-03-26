import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ikeep/data/database/item_dao.dart';
import 'package:ikeep/domain/models/item.dart';
import 'package:ikeep/domain/models/sync_status.dart';
import 'package:ikeep/providers/database_provider.dart';
import 'package:ikeep/providers/item_providers.dart';
import 'package:ikeep/providers/restore_provider.dart';
import 'package:ikeep/providers/service_providers.dart';
import 'package:ikeep/providers/settings_provider.dart';
import 'package:ikeep/providers/sync_providers.dart';
import 'package:ikeep/services/sync_service.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

class MockItemDao extends Mock implements ItemDao {}

class MockSyncService extends Mock implements SyncService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoRestoreNotifier', () {
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockItemDao mockItemDao;
    late MockSyncService mockSyncService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      mockItemDao = MockItemDao();
      mockSyncService = MockSyncService();

      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockAuth.authStateChanges())
          .thenAnswer((_) => Stream<User?>.value(mockUser));
      when(() => mockItemDao.getAllItems()).thenAnswer((_) async => const []);
      when(() => mockItemDao.countBackedUpItems()).thenAnswer((_) async => 5);
      when(() => mockSyncService.hasRemoteBackup())
          .thenAnswer((_) async => true);
      when(() => mockSyncService.fullSync())
          .thenAnswer((_) async => SyncResult.success());
      when(() => mockSyncService.getLastSyncedAt())
          .thenAnswer((_) async => null);
    });

    test(
        'checkAndRestore invalidates cached item data after a successful restore',
        () async {
      var allItemsLoads = 0;
      final localContainer = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          itemDaoProvider.overrideWithValue(mockItemDao),
          syncServiceProvider.overrideWithValue(mockSyncService),
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier(initialSettings: const AppSettings()),
          ),
          allItemsProvider.overrideWith((ref) async {
            allItemsLoads++;
            return const <Item>[];
          }),
        ],
      );
      addTearDown(localContainer.dispose);

      await localContainer.read(allItemsProvider.future);
      expect(allItemsLoads, 1);

      await localContainer.read(autoRestoreProvider.notifier).checkAndRestore();
      await localContainer.read(allItemsProvider.future);

      expect(allItemsLoads, 2);
      expect(localContainer.read(syncStatusProvider).isSuccess, isTrue);
      expect(localContainer.read(settingsProvider).isBackupEnabled, isTrue);
    });
  });
}
