import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ikeep/services/firebase_image_upload_service.dart';
import 'package:ikeep/services/image_optimizer_service.dart';

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

class MockReference extends Mock implements Reference {}

class MockListResult extends Mock implements ListResult {}

class MockImageOptimizerService extends Mock implements ImageOptimizerService {}

void main() {
  group('FirebaseImageUploadService missing local image handling', () {
    late MockFirebaseStorage mockStorage;
    late MockReference rootRef;
    late MockReference preferredFileRef;
    late MockReference folderRef;
    late MockReference legacyFileRef;
    late MockListResult listResult;
    late MockImageOptimizerService mockOptimizer;
    late FirebaseImageUploadService service;

    setUp(() {
      mockStorage = MockFirebaseStorage();
      rootRef = MockReference();
      preferredFileRef = MockReference();
      folderRef = MockReference();
      legacyFileRef = MockReference();
      listResult = MockListResult();
      mockOptimizer = MockImageOptimizerService();

      when(() => mockStorage.ref()).thenReturn(rootRef);
      when(() => mockOptimizer.preferredUploadExtension).thenReturn('.jpg');
      when(() => rootRef.child(any())).thenAnswer((invocation) {
        final path = invocation.positionalArguments.first as String;
        if (path == 'users/user-1/items/item-1') {
          return folderRef;
        }
        if (path == 'users/user-1/items/item-1/image_0.jpg') {
          return preferredFileRef;
        }
        throw StateError('Unexpected storage path: $path');
      });

      service = FirebaseImageUploadService(
        storage: mockStorage,
        optimizer: mockOptimizer,
      );
    });

    test('reuses an existing remote slot when the local file is missing',
        () async {
      when(() => preferredFileRef.getDownloadURL()).thenThrow(
        FirebaseException(
          plugin: 'firebase_storage',
          code: 'object-not-found',
        ),
      );
      when(() => preferredFileRef.fullPath)
          .thenReturn('users/user-1/items/item-1/image_0.jpg');

      when(() => folderRef.listAll()).thenAnswer((_) async => listResult);
      when(() => listResult.items).thenReturn([legacyFileRef]);

      when(() => legacyFileRef.fullPath)
          .thenReturn('users/user-1/items/item-1/image_0.webp');
      when(() => legacyFileRef.getDownloadURL())
          .thenAnswer((_) async => 'https://example.com/image_0.webp');

      final result = await service.uploadItemImages(
        userId: 'user-1',
        itemUuid: 'item-1',
        imagePaths: const [
          '/data/user/0/com.example.ikeep/app_flutter/item_images/missing.jpg'
        ],
      );

      expect(result, ['https://example.com/image_0.webp']);
    });

    test('skips a missing local image when no remote copy exists', () async {
      when(() => preferredFileRef.getDownloadURL()).thenThrow(
        FirebaseException(
          plugin: 'firebase_storage',
          code: 'object-not-found',
        ),
      );
      when(() => preferredFileRef.fullPath)
          .thenReturn('users/user-1/items/item-1/image_0.jpg');

      when(() => folderRef.listAll()).thenAnswer((_) async => listResult);
      when(() => listResult.items).thenReturn(const []);

      final result = await service.uploadItemImages(
        userId: 'user-1',
        itemUuid: 'item-1',
        imagePaths: const [
          '/data/user/0/com.example.ikeep/app_flutter/item_images/missing.jpg'
        ],
      );

      expect(result, isEmpty);
    });
  });
}
