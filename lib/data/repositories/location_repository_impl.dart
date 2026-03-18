import '../../core/errors/failure.dart';
import '../../core/utils/path_utils.dart';
import '../../domain/models/location_model.dart';
import '../database/location_dao.dart';
import 'location_repository.dart';

class LocationRepositoryImpl implements LocationRepository {
  LocationRepositoryImpl({required this.locationDao});

  final LocationDao locationDao;

  Future<String> _buildFullPathForLocation(LocationModel location) async {
    if (location.parentUuid == null) {
      return location.name;
    }

    final ancestors = await locationDao.getAncestors(location.parentUuid!);
    final ancestorNames = ancestors.map((l) => l.name).toList();
    return PathUtils.buildFullPath(ancestorNames, location.name);
  }

  Future<void> _refreshDescendantPaths(String parentUuid) async {
    final children = await locationDao.getChildLocations(parentUuid);
    for (final child in children) {
      final fullPath = await _buildFullPathForLocation(child);
      final updatedChild = child.copyWith(fullPath: fullPath);
      await locationDao.updateLocation(updatedChild);
      await _refreshDescendantPaths(child.uuid);
    }
  }

  @override
  Future<Failure?> saveLocation(LocationModel location) async {
    try {
      final fullPath = await _buildFullPathForLocation(location);
      await locationDao.insertLocation(location.copyWith(fullPath: fullPath));
      return null;
    } catch (e) {
      return Failure('Failed to save location: $e', e);
    }
  }

  @override
  Future<Failure?> updateLocation(LocationModel location) async {
    try {
      final fullPath = await _buildFullPathForLocation(location);
      await locationDao.updateLocation(location.copyWith(fullPath: fullPath));
      await _refreshDescendantPaths(location.uuid);
      return null;
    } catch (e) {
      return Failure('Failed to update location: $e', e);
    }
  }

  @override
  Future<Failure?> deleteLocation(String uuid) async {
    try {
      await locationDao.deleteLocation(uuid);
      return null;
    } catch (e) {
      return Failure('Failed to delete location: $e', e);
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
