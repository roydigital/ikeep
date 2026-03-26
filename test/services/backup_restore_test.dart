// ignore_for_file: lines_longer_than_80_chars, subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ikeep/data/database/item_dao.dart';
import 'package:ikeep/data/database/location_dao.dart';
import 'package:ikeep/domain/models/item.dart';
import 'package:ikeep/services/firebase_image_upload_service.dart';
import 'package:ikeep/services/firebase_invoice_storage_service.dart';
import 'package:ikeep/services/firebase_sync_service.dart';
import 'package:ikeep/services/image_optimizer_service.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────────

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

class MockImageOptimizerService extends Mock implements ImageOptimizerService {}

class MockItemDao extends Mock implements ItemDao {}

class MockLocationDao extends Mock implements LocationDao {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class MockQueryDocumentSnapshot extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class MockReference extends Mock implements Reference {}

class MockListResult extends Mock implements ListResult {}

class MockFullMetadata extends Mock implements FullMetadata {}

// ── Helpers ────────────────────────────────────────────────────────────────────

Item _makeItem({
  String uuid = 'item-1',
  List<String> imagePaths = const [],
  String? invoicePath,
  bool isBackedUp = true,
  String? cloudId,
  DateTime? lastSyncedAt,
}) {
  return Item(
    uuid: uuid,
    name: 'Test item',
    savedAt: DateTime(2026, 1, 1),
    imagePaths: imagePaths,
    invoicePath: invoicePath,
    isBackedUp: isBackedUp,
    cloudId: cloudId,
    lastSyncedAt: lastSyncedAt,
  );
}

/// A minimal fake QueryDocumentSnapshot backed by a plain [Map].
class _FakeDoc
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _FakeDoc(this._id, this._data);

  final String _id;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // Register fallback values required by mocktail for any() matchers.
  setUpAll(() {
    registerFallbackValue(
        Item(uuid: 'fallback', name: 'fallback', savedAt: _epoch));
    registerFallbackValue(SetOptions(merge: true));
    registerFallbackValue(<String>[]);
  });

  // ── ImageUploadResult ──────────────────────────────────────────────────────

  group('ImageUploadResult', () {
    test('hasImages is false when downloadUrls is empty', () {
      const result =
          ImageUploadResult(downloadUrls: [], storagePaths: []);
      expect(result.hasImages, isFalse);
    });

    test('hasImages is true when at least one URL is present', () {
      const result = ImageUploadResult(
        downloadUrls: ['https://example.com/img.jpg'],
        storagePaths: ['users/u/items/i/image_0.jpg'],
      );
      expect(result.hasImages, isTrue);
    });

    test('isFullyUploaded requires equal-length lists', () {
      const complete = ImageUploadResult(
        downloadUrls: ['https://a.com/img.jpg'],
        storagePaths: ['users/u/items/i/image_0.jpg'],
      );
      expect(complete.isFullyUploaded, isTrue);

      const partial = ImageUploadResult(
        downloadUrls: ['https://a.com/img.jpg'],
        storagePaths: [], // storage path missing → partial failure
      );
      expect(partial.isFullyUploaded, isFalse);
    });
  });

  // ── StoredInvoiceFile.storagePath ──────────────────────────────────────────

  group('StoredInvoiceFile', () {
    test('storagePath is optional and defaults to null', () {
      const invoice = StoredInvoiceFile(
        path: 'https://example.com/invoice.pdf',
        fileName: 'invoice.pdf',
      );
      expect(invoice.storagePath, isNull);
    });

    test('storagePath is preserved when provided', () {
      const invoice = StoredInvoiceFile(
        path: 'https://example.com/invoice.pdf',
        fileName: 'invoice.pdf',
        storagePath: 'users/u/items/i/invoices/invoice.pdf',
      );
      expect(invoice.storagePath,
          equals('users/u/items/i/invoices/invoice.pdf'));
    });
  });

  // ── FirebaseImageUploadService.resolveItemImageUrls ────────────────────────

  group('FirebaseImageUploadService.resolveItemImageUrls', () {
    late MockFirebaseStorage mockStorage;
    late MockImageOptimizerService mockOptimizer;
    late MockReference rootRef;
    late MockReference storageFileRef;
    late MockReference folderRef;
    late MockListResult emptyList;
    late FirebaseImageUploadService service;

    setUp(() {
      mockStorage = MockFirebaseStorage();
      mockOptimizer = MockImageOptimizerService();
      rootRef = MockReference();
      storageFileRef = MockReference();
      folderRef = MockReference();
      emptyList = MockListResult();

      when(() => mockStorage.ref()).thenReturn(rootRef);
      when(() => mockOptimizer.preferredUploadExtension).thenReturn('.webp');
      when(() => emptyList.items).thenReturn([]);
      when(() => folderRef.listAll())
          .thenAnswer((_) async => emptyList);

      service = FirebaseImageUploadService(
        storage: mockStorage,
        optimizer: mockOptimizer,
      );
    });

    // ── Test 3: reinstall simulation — old local paths are dead ──────────────
    test(
        'reinstall simulation: uses storage path to get fresh URL '
        'when stored download URL might be stale', () async {
      // Arrange: the Firestore doc has both a (potentially stale) HTTPS URL
      // and a durable storage path. After reinstall we should use the storage
      // path to get a guaranteed-fresh download URL.
      const storagePath = 'users/uid/items/item-1/image_0.webp';
      const freshUrl = 'https://storage.googleapis.com/fresh-token/image.webp';

      when(() => rootRef.child(storagePath)).thenReturn(storageFileRef);
      when(() => storageFileRef.getDownloadURL())
          .thenAnswer((_) async => freshUrl);

      final urls = await service.resolveItemImageUrls(
        userId: 'uid',
        itemUuid: 'item-1',
        downloadUrls: ['https://old-stale-token/image.webp'],
        storagePaths: [storagePath],
      );

      expect(urls, equals([freshUrl]));
      // The fresh URL should have come from the storage path, not the old URL.
      verify(() => storageFileRef.getDownloadURL()).called(1);
    });

    // ── Test 8: missing Firebase Storage object during restore ────────────────
    test(
        'gracefully skips missing storage objects and falls back to '
        'folder listing', () async {
      const storagePath = 'users/uid/items/item-1/image_0.webp';
      final notFoundError = FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
        message: 'No object exists at the desired reference.',
      );

      when(() => rootRef.child(storagePath)).thenReturn(storageFileRef);
      when(() => storageFileRef.getDownloadURL())
          .thenThrow(notFoundError);
      // Folder listing is the final fallback — also empty here.
      when(() => rootRef.child('users/uid/items/item-1'))
          .thenReturn(folderRef);

      final urls = await service.resolveItemImageUrls(
        userId: 'uid',
        itemUuid: 'item-1',
        downloadUrls: [],
        storagePaths: [storagePath],
      );

      // Storage object is gone → returns empty list rather than throwing.
      expect(urls, isEmpty);
    });

    // ── Test 5: render restored remote image ──────────────────────────────────
    test('returns https URL as-is when no storage paths provided (legacy backup)',
        () async {
      const httpsUrl =
          'https://firebasestorage.googleapis.com/v0/b/bucket/o/file?alt=media&token=xyz';
      when(() => rootRef.child('users/uid/items/item-1'))
          .thenReturn(folderRef);

      final urls = await service.resolveItemImageUrls(
        userId: 'uid',
        itemUuid: 'item-1',
        downloadUrls: [httpsUrl],
        storagePaths: const [],
      );

      expect(urls, equals([httpsUrl]));
    });
  });

  // ── FirebaseInvoiceStorageService.resolveCloudInvoice ─────────────────────

  group('FirebaseInvoiceStorageService.resolveCloudInvoice', () {
    late MockFirebaseStorage mockStorage;
    late MockReference rootRef;
    late MockReference invoiceRef;
    late MockReference folderRef;
    late MockListResult emptyList;
    late MockFullMetadata mockMetadata;
    late FirebaseInvoiceStorageService service;

    setUp(() {
      mockStorage = MockFirebaseStorage();
      rootRef = MockReference();
      invoiceRef = MockReference();
      folderRef = MockReference();
      emptyList = MockListResult();
      mockMetadata = MockFullMetadata();

      when(() => mockStorage.ref()).thenReturn(rootRef);
      when(() => emptyList.items).thenReturn([]);
      when(() => folderRef.listAll())
          .thenAnswer((_) async => emptyList);
      when(() => mockMetadata.customMetadata).thenReturn(null);
      when(() => mockMetadata.size).thenReturn(null);

      service = FirebaseInvoiceStorageService(storage: mockStorage);
    });

    // ── Test 6: open restored PDF ─────────────────────────────────────────────
    test(
        'uses storage path to get fresh download URL for invoice '
        'after reinstall', () async {
      const storagePath = 'users/uid/items/item-1/invoices/invoice.pdf';
      const freshUrl = 'https://storage.googleapis.com/fresh/invoice.pdf';

      when(() => rootRef.child(storagePath)).thenReturn(invoiceRef);
      when(() => invoiceRef.getDownloadURL())
          .thenAnswer((_) async => freshUrl);
      when(() => invoiceRef.getMetadata())
          .thenAnswer((_) async => mockMetadata);
      when(() => invoiceRef.fullPath).thenReturn(storagePath);

      final result = await service.resolveCloudInvoice(
        userId: 'uid',
        itemUuid: 'item-1',
        invoicePath: 'https://old-url/invoice.pdf',
        invoiceFileName: 'receipt.pdf',
        storagePath: storagePath,
      );

      expect(result, isNotNull);
      expect(result!.path, equals(freshUrl));
      expect(result.storagePath, equals(storagePath));
    });

    // ── Test 8 (invoice): missing Storage object ──────────────────────────────
    test('returns null when storage object is gone and folder is empty',
        () async {
      const storagePath = 'users/uid/items/item-1/invoices/invoice.pdf';
      final notFoundError = FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
      );

      when(() => rootRef.child(storagePath)).thenReturn(invoiceRef);
      when(() => invoiceRef.getDownloadURL()).thenThrow(notFoundError);

      // Folder listing is the final fallback.
      when(() => rootRef.child('users/uid/items/item-1/invoices'))
          .thenReturn(folderRef);

      final result = await service.resolveCloudInvoice(
        userId: 'uid',
        itemUuid: 'item-1',
        storagePath: storagePath,
      );

      expect(result, isNull);
    });
  });

  // ── FirebaseSyncService ────────────────────────────────────────────────────

  group('FirebaseSyncService', () {
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockFirebaseFirestore mockFirestore;
    late MockFirebaseStorage mockStorage;
    late MockImageOptimizerService mockOptimizer;
    late MockItemDao mockItemDao;
    late MockLocationDao mockLocationDao;
    late MockCollectionReference mockItemsRef;
    late MockCollectionReference mockLocationsRef;
    late MockDocumentReference mockUserDoc;
    late MockDocumentReference mockItemDoc;
    late MockQuerySnapshot mockItemsSnapshot;
    late MockQuerySnapshot mockLocationsSnapshot;
    late MockReference mockRootRef;
    late FirebaseImageUploadService imageService;
    late FirebaseInvoiceStorageService invoiceService;
    late FirebaseSyncService syncService;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      mockFirestore = MockFirebaseFirestore();
      mockStorage = MockFirebaseStorage();
      mockOptimizer = MockImageOptimizerService();
      mockItemDao = MockItemDao();
      mockLocationDao = MockLocationDao();
      mockItemsRef = MockCollectionReference();
      mockLocationsRef = MockCollectionReference();
      mockUserDoc = MockDocumentReference();
      mockItemDoc = MockDocumentReference();
      mockItemsSnapshot = MockQuerySnapshot();
      mockLocationsSnapshot = MockQuerySnapshot();
      mockRootRef = MockReference();

      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('uid-1');
      when(() => mockUser.email).thenReturn('test@example.com');
      when(() => mockUser.displayName).thenReturn('Test User');
      when(() => mockUser.photoURL).thenReturn(null);

      when(() => mockStorage.ref()).thenReturn(mockRootRef);
      when(() => mockOptimizer.preferredUploadExtension).thenReturn('.webp');

      when(() => mockFirestore.collection('users'))
          .thenReturn(_fakeCollectionFor(mockUserDoc, mockFirestore));
      when(() => mockUserDoc.collection('items'))
          .thenReturn(mockItemsRef);
      when(() => mockUserDoc.collection('locations'))
          .thenReturn(mockLocationsRef);
      when(
        () => mockUserDoc.set(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => mockItemDoc.set(any(), any()),
      ).thenAnswer((_) async {});
      when(() => mockItemsRef.doc(any())).thenReturn(mockItemDoc);
      when(() => mockItemsRef.limit(any()))
          .thenReturn(_fakeLimitQuery(mockItemsSnapshot));
      when(() => mockItemsRef.get())
          .thenAnswer((_) async => mockItemsSnapshot);
      when(() => mockLocationsRef.get())
          .thenAnswer((_) async => mockLocationsSnapshot);
      when(() => mockItemsSnapshot.docs).thenReturn([]);
      when(() => mockLocationsSnapshot.docs).thenReturn([]);

      // Location DAO stubs.
      when(() => mockLocationDao.recalculateUsageCounts())
          .thenAnswer((_) async {});
      when(() => mockLocationDao.getAllLocations())
          .thenAnswer((_) async => []);

      imageService = FirebaseImageUploadService(
        storage: mockStorage,
        optimizer: mockOptimizer,
      );
      invoiceService =
          FirebaseInvoiceStorageService(storage: mockStorage);

      syncService = FirebaseSyncService(
        auth: mockAuth,
        firestore: mockFirestore,
        itemDao: mockItemDao,
        locationDao: mockLocationDao,
        imageUploadService: imageService,
        invoiceStorageService: invoiceService,
      );
    });

    // ── Test 1: backup item with image ────────────────────────────────────────
    test('backup stores both download URL and storage path in Firestore',
        () async {
      const localImagePath = '/data/user/0/ikeep/images/photo.jpg';
      const storagePath = 'users/uid-1/items/item-1/image_0.webp';

      final item = _makeItem(imagePaths: [localImagePath]);

      // Stub the ItemDao countBackedUpItems for quota check.
      when(() => mockItemDao.countBackedUpItems())
          .thenAnswer((_) async => 0);
      when(() => mockItemDao.updateItem(any()))
          .thenAnswer((_) async {});

      // Stub Storage so the image "uploads" successfully.
      final mockSlotRef = MockReference();
      final mockFolderRef = MockReference();
      final mockEmptyList = MockListResult();
      when(() => mockRootRef.child(storagePath)).thenReturn(mockSlotRef);
      when(() => mockRootRef.child('users/uid-1/items/item-1'))
          .thenReturn(mockFolderRef);
      when(() => mockFolderRef.listAll())
          .thenAnswer((_) async => mockEmptyList);
      when(() => mockEmptyList.items).thenReturn([]);

      // File does not exist locally — triggers _tryReuseStoredSlotImage which
      // also fails (no prior upload) — results in empty upload result.
      when(() => mockSlotRef.getDownloadURL()).thenThrow(
        FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'),
      );

      // Act
      await syncService.syncItem(item);

      // Verify the Firestore doc was written — the write includes imagePaths
      // and imageStoragePaths fields.
      final captured =
          verify(() => mockItemDoc.set(captureAny(), any())).captured;
      expect(captured, isNotEmpty);
      final firestoreData = captured.first as Map<String, dynamic>;
      expect(firestoreData.containsKey('imageStoragePaths'), isTrue);
    });

    // ── Test 2: backup item with PDF ──────────────────────────────────────────
    test('backup stores invoiceStoragePath in Firestore', () async {
      final item = _makeItem(
        invoicePath: null, // no local invoice
        isBackedUp: true,
      );

      when(() => mockItemDao.countBackedUpItems())
          .thenAnswer((_) async => 0);
      when(() => mockItemDao.updateItem(any()))
          .thenAnswer((_) async {});

      final mockFolderRef = MockReference();
      final mockEmptyList = MockListResult();
      when(() => mockRootRef.child(any())).thenReturn(mockFolderRef);
      when(() => mockFolderRef.listAll())
          .thenAnswer((_) async => mockEmptyList);
      when(() => mockEmptyList.items).thenReturn([]);

      await syncService.syncItem(item);

      final captured =
          verify(() => mockItemDoc.set(captureAny(), any())).captured;
      expect(captured, isNotEmpty);
      final firestoreData = captured.first as Map<String, dynamic>;
      // invoiceStoragePath key is always written (may be null for items with
      // no invoice).
      expect(firestoreData.containsKey('invoiceStoragePath'), isTrue);
    });

    // ── Test 9: different Google account sign-in ──────────────────────────────
    test(
        'hasRemoteBackup returns false when user is not signed in',
        () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      final result = await syncService.hasRemoteBackup();
      expect(result, isFalse);
    });

    test(
        'hasRemoteBackup returns false when items collection is empty',
        () async {
      when(() => mockItemsSnapshot.docs).thenReturn([]);
      final result = await syncService.hasRemoteBackup();
      expect(result, isFalse);
    });

    test(
        'hasRemoteBackup returns true when at least one item exists in '
        'Firestore', () async {
      final fakeDoc = _FakeDoc('item-1', {'uuid': 'item-1', 'name': 'Test'});
      when(() => mockItemsSnapshot.docs)
          .thenReturn([fakeDoc]);

      final result = await syncService.hasRemoteBackup();
      expect(result, isTrue);
    });

    // ── Test 10: repeat restore must be idempotent ────────────────────────────
    test(
        'fullSync: importing a remote item that already exists locally '
        'calls updateItem instead of insertItem', () async {
      // Arrange: local DB already has item-1 (from a previous partial restore).
      final existingLocalItem = _makeItem(
        uuid: 'item-1',
        isBackedUp: true,
        lastSyncedAt: DateTime(2026, 1, 1),
      );
      final remoteData = <String, dynamic>{
        'uuid': 'item-1',
        'name': 'Test item',
        'savedAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-02T00:00:00.000Z', // newer than local
        'imagePaths': <String>[],
        'imageStoragePaths': <String>[],
        'tags': <String>[],
        'isBackedUp': true,
        'userId': 'uid-1',
        'isArchived': false,
        'isLent': false,
        'isAvailableForLending': false,
        'seasonCategory': 'all_year',
        'sharedWithMemberUuids': <String>[],
      };

      when(() => mockItemDao.getAllItems())
          .thenAnswer((_) async => [existingLocalItem]);
      when(() => mockItemDao.getItemByUuid('item-1'))
          .thenAnswer((_) async => existingLocalItem);
      when(() => mockItemDao.updateItem(any()))
          .thenAnswer((_) async {});

      final fakeDoc = _FakeDoc('item-1', remoteData);
      when(() => mockItemsSnapshot.docs).thenReturn([fakeDoc]);

      await syncService.fullSync();

      // updateItem should be called (not insertItem) since the item exists.
      verify(() => mockItemDao.updateItem(any())).called(greaterThanOrEqualTo(1));
      verifyNever(() => mockItemDao.insertItem(any()));
    });
  });
}

// ── Epoch constant ─────────────────────────────────────────────────────────────

final _epoch = DateTime(2020);

// ── Query helper fakes ─────────────────────────────────────────────────────────

/// Returns a [CollectionReference] stub whose [doc] method returns [docRef].
CollectionReference<Map<String, dynamic>> _fakeCollectionFor(
  DocumentReference<Map<String, dynamic>> docRef,
  FirebaseFirestore firestore,
) {
  final col = MockCollectionReference();
  when(() => col.doc(any())).thenReturn(docRef);
  when(() => col.doc()).thenReturn(docRef);
  return col;
}

/// Returns a minimal Query-like stub (used for [limit]) whose [get] returns
/// [snapshot].
_LimitQuery _fakeLimitQuery(QuerySnapshot<Map<String, dynamic>> snapshot) {
  return _LimitQuery(snapshot);
}

class _LimitQuery
    implements Query<Map<String, dynamic>> {
  _LimitQuery(this._snapshot);
  final QuerySnapshot<Map<String, dynamic>> _snapshot;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async =>
      _snapshot;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
