import '../../core/errors/failure.dart';
import '../../core/utils/path_utils.dart';
import '../../domain/models/location_model.dart';
import '../database/location_dao.dart';
import 'location_repository.dart';

class LocationRepositoryImpl implements LocationRepository {
  LocationRepositoryImpl({required this.locationDao});

  final LocationDao locationDao;

  @override
  Future<Failure?> saveLocation(LocationModel location) async {
    try {
      final fullPath = await buildFullPath(location.uuid);
      await locationDao.insertLocation(location.copyWith(fullPath: fullPath));
      return null;
    } catch (e) {
      return Failure('Failed to save location', e);
    }
  }

  @override
  Future<Failure?> updateLocation(LocationModel location) async {
    try {
      final fullPath = await buildFullPath(location.uuid);
      await locationDao.updateLocation(location.copyWith(fullPath: fullPath));
      return null;
    } catch (e) {
      return Failure('Failed to update location', e);
    }
  }

  @override
  Future<Failure?> deleteLocation(String uuid) async {
    try {
      await locationDao.deleteLocation(uuid);
      return null;
    } catch (e) {
      return Failure('Failed to delete location', e);
    }
  }

  @override
  Future<LocationModel?> getLocation(String uuid) =>
      locationDao.getLocationByUuid(uuid);

  @override
  Future<List<LocationModel>> getAllLocations() =>
      locationDao.getAllLocations();

  @override
  Future<List<LocationModel>> getRootLocations() =>
      locationDao.getRootLocations();

  @override
  Future<List<LocationModel>> getChildLocations(String parentUuid) =>
      locationDao.getChildLocations(parentUuid);

  @override
  Future<String> buildFullPath(String uuid) async {
    final ancestors = await locationDao.getAncestors(uuid);
    if (ancestors.isEmpty) return '';
    return PathUtils.buildFullPath(
      ancestors.take(ancestors.length - 1).map((l) => l.name).toList(),
      ancestors.last.name,
    );
  }
}
