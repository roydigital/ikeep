import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ikeep/data/repositories/item_repository.dart';
import 'package:ikeep/domain/models/item.dart';
import 'package:ikeep/domain/models/location_model.dart';
import 'package:ikeep/providers/location_providers.dart';
import 'package:ikeep/providers/location_usage_providers.dart';
import 'package:ikeep/providers/ml_label_providers.dart';
import 'package:ikeep/providers/repository_providers.dart';
import 'package:ikeep/providers/service_providers.dart';
import 'package:ikeep/providers/settings_provider.dart';
import 'package:ikeep/screens/save/save_screen.dart';
import 'package:ikeep/services/image_service.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

/// [ItemRepository] is an abstract class so it can be implemented by Mock.
class MockItemRepository extends Mock implements ItemRepository {}

class FakeItem extends Fake implements Item {}

class FakeImageService extends ImageService {
  FakeImageService(this.pickedImagePath);

  final String pickedImagePath;

  @override
  Future<String> pickFromCamera() async => pickedImagePath;

  @override
  Future<String> pickFromGallery() async => pickedImagePath;

  @override
  Future<List<String>> pickMultipleFromGallery() async => [];

  @override
  Future<void> deleteImage(String imagePath) async {}

  @override
  Future<void> deleteImages(List<String> imagePaths) async {}
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Wraps [SaveScreen] with the minimal provider overrides needed for widget
/// testing. The fake image service throws on pickFromCamera() to skip the
/// camera flow — save_screen catches the exception in _capturePhoto and pops,
/// so we wrap in a Navigator to absorb that pop.
Widget createTestSaveScreen({
  required MockItemRepository mockItemRepo,
  required FakeImageService fakeImageService,
}) {
  final router = GoRouter(
    initialLocation: '/save',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/save',
        builder: (context, state) => const SaveScreen(),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      // Override image service with our fake.
      imageServiceProvider.overrideWithValue(fakeImageService),

      // Override item repository so we can verify calls.
      itemRepositoryProvider.overrideWithValue(mockItemRepo),

      // Provide empty locations so the chip row renders without DB access.
      locationsWithDerivedUsageProvider.overrideWith(
        (ref) => Future.value([]),
      ),
      allLocationsProvider.overrideWith(
        (ref) => Future.value(<LocationModel>[]),
      ),

      // No ML labels needed.
      mlLabelsForImageProvider.overrideWith(
        (ref, path) => Future.value([]),
      ),

      // Minimal settings for the non-monetized release build.
      settingsProvider.overrideWith(
        (ref) => SettingsNotifier(),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
    ),
  );
}

void main() {
  late MockItemRepository mockItemRepo;
  late FakeImageService fakeImageService;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(FakeItem());
  });

  setUp(() {
    mockItemRepo = MockItemRepository();
    tempDir = Directory.systemTemp.createTempSync('ikeep-save-screen-test-');
    final imageFile = File('${tempDir.path}${Platform.pathSeparator}photo.png');
    imageFile.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSfoAAAAASUVORK5CYII=',
      ),
    );
    fakeImageService = FakeImageService(imageFile.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SaveScreen form interaction', () {
    testWidgets('renders text fields after camera is dismissed', (tester) async {
      await tester.pumpWidget(
        createTestSaveScreen(
          mockItemRepo: mockItemRepo,
          fakeImageService: fakeImageService,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The save screen shows TextField widgets for item name (at minimum).
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('0 / 1000 cloud backups used'), findsOneWidget);
      expect(find.textContaining('Ikeep Plus'), findsNothing);
    });

    testWidgets('does not call repository when name is empty', (tester) async {
      await tester.pumpWidget(
        createTestSaveScreen(
          mockItemRepo: mockItemRepo,
          fakeImageService: fakeImageService,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Look for save button and tap it without entering a name.
      final saveFinder = find.textContaining(
        RegExp(r'save|Save', caseSensitive: false),
      );
      if (saveFinder.evaluate().isNotEmpty) {
        await tester.tap(saveFinder.first, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Repository saveItem should NOT have been called.
      verifyNever(
        () => mockItemRepo.saveItem(
          any(),
          movedByMemberUuid: any(named: 'movedByMemberUuid'),
          movedByName: any(named: 'movedByName'),
        ),
      );
    });
  });
}
