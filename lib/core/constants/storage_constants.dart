// File system directory names and Appwrite identifiers.
class StorageConstants {
  StorageConstants._();

  // Local directories (relative to app documents directory)
  static const String itemImagesDir = 'item_images';
  static const String itemInvoicesDir = 'item_invoices';
  static const String thumbnailsDir = 'thumbnails';
  static const String optimizedUploadsDir = 'optimized_uploads';
  static const String mediaCacheDir = 'media_cache';
  static const String mediaCacheThumbnailsDir = 'thumbs';
  static const String mediaCacheImagesDir = 'images';
  static const String mediaCachePdfsDir = 'pdfs';

  // Appwrite — fill these in from your Appwrite console
  static const String appwriteEndpoint = 'https://cloud.appwrite.io/v1';
  static const String appwriteProjectId = 'YOUR_PROJECT_ID';
  static const String appwriteDatabaseId = 'YOUR_DATABASE_ID';
  static const String appwriteItemsCollectionId = 'items';
  static const String appwriteLocationsCollectionId = 'locations';
  static const String appwriteImagesBucketId = 'item_images';

  // Firebase Storage
  static const String firebaseItemImagesRoot = 'users';
  static const String firebaseItemsSegment = 'items';
  static const String firebaseInvoicesSegment = 'invoices';
  static const String firebaseThumbnailSuffix = '_thumb';
  static const String firebaseLongLivedCacheControl =
      'public,max-age=31536000,immutable';

  // Custom metadata keys stored on Firebase Storage objects so lightweight
  // Firestore media descriptors can be reconstructed without downloading the
  // actual file.
  static const String sourceModifiedMsMetadataKey = 'sourceModifiedMs';
  static const String sourceBytesMetadataKey = 'sourceBytes';
  static const String contentHashMetadataKey = 'contentHash';
  static const String versionMetadataKey = 'version';
  static const String updatedAtMetadataKey = 'updatedAt';
  static const String byteSizeMetadataKey = 'byteSize';
  static const String mimeTypeMetadataKey = 'mimeType';
}
