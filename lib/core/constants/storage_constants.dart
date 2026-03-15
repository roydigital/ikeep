// File system directory names and Appwrite identifiers.
class StorageConstants {
  StorageConstants._();

  // Local directories (relative to app documents directory)
  static const String itemImagesDir = 'item_images';
  static const String thumbnailsDir = 'thumbnails';

  // Appwrite — fill these in from your Appwrite console
  static const String appwriteEndpoint = 'https://cloud.appwrite.io/v1';
  static const String appwriteProjectId = 'YOUR_PROJECT_ID';
  static const String appwriteDatabaseId = 'YOUR_DATABASE_ID';
  static const String appwriteItemsCollectionId = 'items';
  static const String appwriteLocationsCollectionId = 'locations';
  static const String appwriteImagesBucketId = 'item_images';
}
