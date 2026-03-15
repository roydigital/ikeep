// App-wide constants that are not theme or DB related.
class AppConstants {
  AppConstants._();

  static const String appName = 'Ikeep';
  static const String appTagline = 'Where did I keep it?';

  // Item limits
  static const int maxImagesPerItem = 3;
  static const int maxTagsPerItem = 10;
  static const int maxTagLength = 30;
  static const int maxItemNameLength = 100;
  static const int maxNotesLength = 500;

  // Location limits
  static const int maxLocationDepth = 4; // e.g. Home > Bedroom > Wardrobe > Top Shelf
  static const int maxLocationNameLength = 60;

  // Image quality
  static const int imageCompressionQuality = 80; // 0-100
  static const int thumbnailSize = 200; // pixels

  // Search
  static const int searchDebounceMs = 300;
  static const int fuzzyMatchThreshold = 2; // max Levenshtein distance for fuzzy

  // Reminder thresholds
  static const int stillThereReminderMonths = 6;

  // Pagination
  static const int recentItemsLimit = 20;
  static const int searchResultsLimit = 50;

  // Default predefined tags
  static const List<String> defaultTags = [
    'important',
    'documents',
    'tools',
    'electronics',
    'clothing',
    'seasonal',
    'rarely used',
    'medicines',
    'food',
    'books',
  ];

  // Default location icons (Material icon names)
  static const List<String> locationIconNames = [
    'home',
    'bedroom_parent',
    'kitchen',
    'garage',
    'work',
    'car',
    'storage',
    'luggage',
    'local_hospital',
    'school',
  ];
}
