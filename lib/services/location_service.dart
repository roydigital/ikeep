import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Encapsulates GPS positioning and reverse geocoding.
/// Returns a locality string (e.g., "HSR Layout, Bangalore") — never raw GPS.
class LocationService {
  static const _keyLocality = 'ikeep_cached_locality';
  static const _keyLocalityUpdatedAt = 'ikeep_locality_updated_at';
  // Refresh locality if older than 24 hours.
  static const _staleDuration = Duration(hours: 24);

  /// Whether location permission has been granted.
  Future<bool> hasPermission() async {
    final status = await Geolocator.checkPermission();
    return status == LocationPermission.always ||
        status == LocationPermission.whileInUse;
  }

  /// Requests location permission. Returns true if granted.
  Future<bool> requestPermission() async {
    // Check if location services are enabled.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Returns the cached locality if fresh, otherwise resolves from GPS.
  /// Format: "Locality, AdminArea" (e.g., "HSR Layout, Karnataka").
  /// Returns null if permission denied or geocoding fails.
  Future<String?> getCurrentLocality() async {
    // Check cache first.
    final cached = await _getCachedLocality();
    if (cached != null) return cached;

    // Resolve from GPS.
    final granted = await hasPermission();
    if (!granted) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low, // City-level, privacy-friendly
          timeLimit: Duration(seconds: 10),
        ),
      );

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isEmpty) return null;

      final place = placemarks.first;
      final locality = _formatLocality(place);
      if (locality != null) {
        await _cacheLocality(locality);
      }
      return locality;
    } catch (_) {
      return null;
    }
  }

  /// Forces a GPS refresh, bypassing the cache.
  Future<String?> refreshLocality() async {
    final granted = await hasPermission();
    if (!granted) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isEmpty) return null;

      final place = placemarks.first;
      final locality = _formatLocality(place);
      if (locality != null) {
        await _cacheLocality(locality);
      }
      return locality;
    } catch (_) {
      return null;
    }
  }

  /// Reads the cached locality from SharedPreferences.
  /// Returns null if stale or not cached.
  Future<String?> _getCachedLocality() async {
    final prefs = await SharedPreferences.getInstance();
    final locality = prefs.getString(_keyLocality);
    final updatedAtMs = prefs.getInt(_keyLocalityUpdatedAt);

    if (locality == null || updatedAtMs == null) return null;

    final updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
    if (DateTime.now().difference(updatedAt) > _staleDuration) return null;

    return locality;
  }

  /// Caches the locality string in SharedPreferences.
  Future<void> _cacheLocality(String locality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocality, locality);
    await prefs.setInt(
        _keyLocalityUpdatedAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// Returns the raw cached locality (even if stale) for display purposes.
  Future<String?> getCachedLocalityRaw() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLocality);
  }

  /// Formats a Placemark into a normalized locality string.
  /// Returns "SubLocality, Locality" or "Locality, AdminArea".
  String? _formatLocality(Placemark place) {
    final subLocality = (place.subLocality ?? '').trim();
    final locality = (place.locality ?? '').trim();
    final adminArea = (place.administrativeArea ?? '').trim();

    if (subLocality.isNotEmpty && locality.isNotEmpty) {
      return '$subLocality, $locality';
    }
    if (locality.isNotEmpty && adminArea.isNotEmpty) {
      return '$locality, $adminArea';
    }
    if (locality.isNotEmpty) return locality;
    if (adminArea.isNotEmpty) return adminArea;
    return null;
  }
}
