// NOTE: Location permission is currently NOT declared in AndroidManifest.xml
// because the only caller (_NearbyLendingCard) is an unused widget.
// When activating Nearby Lending or any other location-dependent feature:
// 1. Add `<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>`
//    back to AndroidManifest.xml
// 2. Ensure caller passes BuildContext to show the rationale dialog
// 3. Update Play Store Data Safety form to declare location data collection
import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/dialogs/location_rationale_dialog.dart';

/// Outcome of a location resolution flow. Callers use this to distinguish
/// between user-declined rationale (silent fallback) and a true failure.
enum LocationResult {
  success,
  userDeclinedRationale,
  permissionDenied,
  serviceDisabled,
  error,
}

/// Wraps the outcome of [LocationService.getCurrentLocality] /
/// [LocationService.refreshLocality] so callers can switch on [status]
/// and optionally read [locality] (populated when status == success).
class LocalityResult {
  const LocalityResult({required this.status, this.locality});

  final LocationResult status;
  final String? locality;

  bool get isSuccess => status == LocationResult.success;
}

/// Encapsulates GPS positioning and reverse geocoding.
/// Returns a locality string (e.g., "HSR Layout, Bangalore") — never raw GPS.
class LocationService {
  static const _keyLocality = 'ikeep_cached_locality';
  static const _keyLocalityUpdatedAt = 'ikeep_locality_updated_at';
  // Google Play requires a prominent in-app disclosure before the OS
  // permission prompt. Once the user has seen it (and agreed), we skip it.
  static const _keyRationaleShown = 'location_rationale_shown';
  // Refresh locality if older than 24 hours.
  static const _staleDuration = Duration(hours: 24);

  /// Whether location permission has been granted.
  Future<bool> hasPermission() async {
    final status = await Geolocator.checkPermission();
    return status == LocationPermission.always ||
        status == LocationPermission.whileInUse;
  }

  /// Returns the cached locality if fresh, otherwise resolves from GPS.
  /// Format: "Locality, AdminArea" (e.g., "HSR Layout, Karnataka").
  Future<LocalityResult> getCurrentLocality(BuildContext context) async {
    // Check cache first — fresh cache never needs a permission round-trip.
    final cached = await _getCachedLocality();
    if (cached != null) {
      return LocalityResult(
          status: LocationResult.success, locality: cached);
    }

    if (!context.mounted) {
      return const LocalityResult(status: LocationResult.error);
    }
    return _resolveFromGps(context);
  }

  /// Forces a GPS refresh, bypassing the cache.
  Future<LocalityResult> refreshLocality(BuildContext context) async {
    return _resolveFromGps(context);
  }

  /// Resolves locality from GPS, gating the first-ever permission prompt
  /// behind the in-app rationale dialog (Play Store sensitive-permission
  /// disclosure requirement).
  Future<LocalityResult> _resolveFromGps(BuildContext context) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocalityResult(status: LocationResult.serviceDisabled);
    }

    // Skip rationale if already granted — the whole point is to explain
    // BEFORE the OS prompt, which won't fire again once granted.
    var permission = await Geolocator.checkPermission();
    final alreadyGranted = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    if (!alreadyGranted) {
      final prefs = await SharedPreferences.getInstance();
      final rationaleShown = prefs.getBool(_keyRationaleShown) ?? false;

      if (!rationaleShown) {
        if (!context.mounted) {
          return const LocalityResult(status: LocationResult.error);
        }
        final accepted = await LocationRationaleDialog.show(context);
        if (!accepted) {
          return const LocalityResult(
              status: LocationResult.userDeclinedRationale);
        }
        await prefs.setBool(_keyRationaleShown, true);
      }

      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocalityResult(status: LocationResult.permissionDenied);
      }
    }

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

      if (placemarks.isEmpty) {
        return const LocalityResult(status: LocationResult.error);
      }

      final locality = _formatLocality(placemarks.first);
      if (locality == null) {
        return const LocalityResult(status: LocationResult.error);
      }
      await _cacheLocality(locality);
      return LocalityResult(
          status: LocationResult.success, locality: locality);
    } catch (_) {
      return const LocalityResult(status: LocationResult.error);
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
