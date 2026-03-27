import '../../core/errors/failure.dart';
import '../../domain/models/location_model.dart';

abstract class LocationRepository {
  Future<Failure?> saveLocation(LocationModel location);
  Future<Failure?> updateLocation(LocationModel location);

  /// Deletes location and cascades to children.
  Future<Failure?> deleteLocation(String uuid);

  Future<LocationModel?> getLocation(String uuid);
  Future<List<LocationModel>> getAllLocations();
  Future<List<LocationModel>> getRootLocations();
  Future<List<LocationModel>> getChildLocations(String parentUuid);

  /// Returns true if a sibling with the same normalized name already exists.
  ///
  /// [excludeUuid] should be set when editing so the current record is skipped.
  Future<bool> hasSiblingWithName({
    required String name,
    required String locationType,
    String? parentUuid,
    String? excludeUuid,
  });

  /// Rebuilds the [fullPath] for [uuid] by walking ancestors in DB.
  Future<String> buildFullPath(String uuid);
}
