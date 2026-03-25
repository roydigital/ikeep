import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ikeep/domain/models/item.dart';
import 'package:ikeep/providers/home_tour_provider.dart';
import 'package:ikeep/providers/item_providers.dart';
import 'package:ikeep/providers/service_providers.dart';
import 'package:ikeep/providers/settings_provider.dart';
import 'package:ikeep/screens/settings/settings_screen.dart';
import 'package:ikeep/services/sync_service.dart';
import 'package:ikeep/domain/models/sync_status.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

class MockSyncService extends Mock implements SyncService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFirebaseAuth mockAuth;
  late MockUser mockUser;
  late MockSyncService mockSyncService;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      HomeTourKeys.hasSeenSettingsTour: true,
    });

    mockAuth = MockFirebaseAuth();
    mockUser = MockUser();
    mockSyncService = MockSyncService();

    when(() => mockUser.uid).thenReturn('user-1');
    when(() => mockUser.displayName).thenReturn('Hrishikesh Roy');
    when(() => mockUser.photoURL).thenReturn(null);
    when(() => mockUser.email).thenReturn('roy@example.com');

    when(() => mockAuth.currentUser).thenReturn(null);
    when(() => mockAuth.authStateChanges())
        .thenAnswer((_) => Stream<User?>.value(null));
    when(() => mockSyncService.fullSync())
        .thenAnswer((_) async => SyncResult.success());
    when(() => mockSyncService.getLastSyncedAt()).thenAnswer((_) async => null);
  });

  testWidgets('settings screen shows neutral cloud and family copy',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier(initialSettings: const AppSettings()),
          ),
          backedUpItemsCountProvider.overrideWith(
            (ref) => Future<int>.value(0),
          ),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('0 / 1000 cloud backups used'), findsOneWidget);
    expect(find.textContaining('Ikeep Plus'), findsNothing);
    expect(find.text('Manage Subscription'), findsNothing);
    expect(find.text('Restore Purchases'), findsNothing);
  });

  testWidgets(
      'settings screen shows backed up item previews when items already exist',
      (tester) async {
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockAuth.authStateChanges())
        .thenAnswer((_) => Stream<User?>.value(mockUser));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          syncServiceProvider.overrideWithValue(mockSyncService),
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier(initialSettings: const AppSettings()),
          ),
          backedUpItemsCountProvider.overrideWith(
            (ref) => Future<int>.value(2),
          ),
          backedUpItemsProvider.overrideWith(
            (ref) => Future<List<Item>>.value(
              [
                Item(
                  uuid: '1',
                  name: 'Passport',
                  savedAt: DateTime(2026, 3, 23),
                  isBackedUp: true,
                ),
                Item(
                  uuid: '2',
                  name: 'Laptop',
                  savedAt: DateTime(2026, 3, 22),
                  isBackedUp: true,
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('2 / 1000 cloud backups used'), findsOneWidget);
    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('Laptop'), findsOneWidget);
  });

  testWidgets(
      'online backup tap triggers sync even when legacy backup flag is off',
      (tester) async {
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockAuth.authStateChanges())
        .thenAnswer((_) => Stream<User?>.value(mockUser));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          syncServiceProvider.overrideWithValue(mockSyncService),
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier(initialSettings: const AppSettings()),
          ),
          backedUpItemsCountProvider.overrideWith(
            (ref) => Future<int>.value(0),
          ),
          backedUpItemsProvider.overrideWith(
            (ref) => Future<List<Item>>.value(const []),
          ),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Online Backup'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final syncCard = find.ancestor(
      of: find.text('Online Backup'),
      matching: find.byType(InkWell),
    );
    tester.widget<InkWell>(syncCard.first).onTap?.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    verify(() => mockSyncService.fullSync()).called(1);
  });
}
