import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

// ─── Mocks ───────────────────────────────────────────────────────────────────

/// [ItemRepository] is an abstract class so it can be implemented by Mock.
class MockItemRepository extends Mock implements ItemRepository {}

class FakeItem extends Fake implements Item {}

/// A minimal fake ImageService that always throws on camera/gallery pick,
/// simulating the user cancelling. This avoids trying to `implements` the
/// concrete [ImageService] class (which Dart 3 forbids for plain classes).
class FakeImageService {
  Future<String> pickFromCamera() async =>
      throw Exception('No image captured');

  Future<String> pickFromGallery() async =>
      throw Exception('No image selected');

  Future<List<String>> pickMultipleFromGallery() async => [];

  Future<void> deleteImage(String imagePath) async {}

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
  return ProviderScope(
    overrides: [
      // Override image service with our fake.
      imageServiceProvider.overrideWithValue(fakeImageService as dynamic),

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

      // Minimal settings (not premium, backup disabled).
      settingsProvider.overrideWith(
        (ref) => SettingsNotifier(),
      ),
    ],
    child: MaterialApp(
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => const SaveScreen(),
        ),
      ),
    ),
  );
}

void main() {
  late MockItemRepository mockItemRepo;
  late FakeImageService fakeImageService;

  setUpAll(() {
    registerFallbackValue(FakeItem());
  });

  setUp(() {
    mockItemRepo = MockItemRepository();
    fakeImageService = FakeImageService();
  });

  group('SaveScreen form interaction', () {
    testWidgets('renders text fields after camera is dismissed', (tester) async {
      await tester.pumpWidget(
        createTestSaveScreen(
          mockItemRepo: mockItemRepo,
          fakeImageService: fakeImageService,
        ),
      );
      await tester.pumpAndSettle();

      // The save screen shows TextField widgets for item name (at minimum).
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('does not call repository when name is empty', (tester) async {
      await tester.pumpWidget(
        createTestSaveScreen(
          mockItemRepo: mockItemRepo,
          fakeImageService: fakeImageService,
        ),
      );
      await tester.pumpAndSettle();

      // Look for save button and tap it without entering a name.
      final saveFinder = find.textContaining(
        RegExp(r'save|Save', caseSensitive: false),
      );
      if (saveFinder.evaluate().isNotEmpty) {
        await tester.tap(saveFinder.first);
        await tester.pumpAndSettle();
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
