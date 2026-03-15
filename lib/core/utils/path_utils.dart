/// Utilities for building and parsing Location full-path breadcrumb strings.
/// Format: "Home > Bedroom > Top Shelf"
class PathUtils {
  PathUtils._();

  static const String separator = ' > ';

  /// Builds a full path from an ordered list of ancestor names + own name.
  static String buildFullPath(List<String> ancestorNames, String ownName) {
    return [...ancestorNames, ownName].join(separator);
  }

  /// Splits a full path into individual segment names.
  static List<String> splitFullPath(String fullPath) {
    return fullPath.split(separator);
  }

  /// Returns just the leaf name from a full path.
  static String leafName(String fullPath) {
    final parts = splitFullPath(fullPath);
    return parts.last;
  }

  /// Returns a new full path after renaming the leaf segment.
  static String renameLast(String fullPath, String newName) {
    final parts = splitFullPath(fullPath);
    if (parts.isEmpty) return newName;
    return [...parts.take(parts.length - 1), newName].join(separator);
  }
}
