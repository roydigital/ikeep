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

  /// Rebuilds the [fullPath] for [uuid] by walking ancestors in DB.
  Future<String> buildFullPath(String uuid);
}
