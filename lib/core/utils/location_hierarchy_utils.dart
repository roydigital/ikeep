import '../../domain/models/location_model.dart';
import 'fuzzy_search.dart';

class LocationHierarchy {
  LocationHierarchy._({
    required this.byUuid,
    required this.childrenByParentUuid,
    required this.areas,
  });

  factory LocationHierarchy.fromLocations(List<LocationModel> locations) {
    final byUuid = <String, LocationModel>{
      for (final location in locations) location.uuid: location,
    };

    final childrenByParentUuid = <String?, List<LocationModel>>{};
    for (final location in locations) {
      childrenByParentUuid
          .putIfAbsent(location.parentUuid, () => <LocationModel>[])
          .add(location);
    }

    for (final entry in childrenByParentUuid.entries) {
      entry.value.sort(_sortByNameThenPath);
    }

    // Only include nodes explicitly typed as areas — never infer from parentUuid
    // being null, since legacy data may have mis-typed root nodes.
    final areas = locations
        .where((location) => location.type == LocationType.area)
        .toList()
      ..sort(_sortByNameThenPath);

    return LocationHierarchy._(
      byUuid: byUuid,
      childrenByParentUuid: childrenByParentUuid,
      areas: areas,
    );
  }

  final Map<String, LocationModel> byUuid;
  final Map<String?, List<LocationModel>> childrenByParentUuid;
  final List<LocationModel> areas;

  static int _sortByNameThenPath(LocationModel a, LocationModel b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (byName != 0) return byName;
    final aPath = (a.fullPath ?? '').toLowerCase();
    final bPath = (b.fullPath ?? '').toLowerCase();
    return aPath.compareTo(bPath);
  }

  List<LocationModel> childrenOf(String? parentUuid) {
    return List<LocationModel>.from(
      childrenByParentUuid[parentUuid] ?? const <LocationModel>[],
    );
  }

  LocationModel? parentOf(LocationModel location) {
    final parentUuid = location.parentUuid;
    if (parentUuid == null) return null;
    return byUuid[parentUuid];
  }

  List<LocationModel> ancestorsOf(String uuid) {
    final ancestors = <LocationModel>[];
    var current = byUuid[uuid];
    final visited = <String>{};

    while (current != null && visited.add(current.uuid)) {
      ancestors.insert(0, current);
      final parentUuid = current.parentUuid;
      current = parentUuid == null ? null : byUuid[parentUuid];
    }

    return ancestors;
  }

  List<LocationModel> descendantsOf(String uuid) {
    final descendants = <LocationModel>[];
    final queue = <LocationModel>[...childrenOf(uuid)];
    final visited = <String>{};

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (!visited.add(current.uuid)) continue;
      descendants.add(current);
      queue.addAll(childrenOf(current.uuid));
    }

    return descendants;
  }

  List<LocationModel> roomsForArea(String areaUuid) {
    return childrenOf(areaUuid)
        .where((location) => location.type == LocationType.room)
        .toList();
  }

  List<LocationModel> directZonesForArea(String areaUuid) {
    return childrenOf(areaUuid)
        .where((location) => location.type == LocationType.zone)
        .toList();
  }

  List<LocationModel> zonesForRoom(String roomUuid) {
    return childrenOf(roomUuid)
        .where((location) => location.type == LocationType.zone)
        .toList();
  }

  List<LocationModel> assignableZones() {
    return byUuid.values
        .where((location) => location.isAssignableToItem)
        .toList()
      ..sort(_sortByNameThenPath);
  }

  List<LocationModel> searchLocations(
    String query, {
    Set<LocationType>? types,
    int pathMatchMinTokenCount = 1,
  }) {
    final tokens = _queryTokens(query);
    final shouldMatchPath = tokens.length >= pathMatchMinTokenCount;
    Iterable<LocationModel> candidates = byUuid.values;

    if (types != null) {
      candidates =
          candidates.where((location) => types.contains(location.type));
    }

    final results = candidates.where((location) {
      if (tokens.isEmpty) return true;

      if (_matchesAllSearchTokens(tokens, location.name)) {
        return true;
      }

      if (!shouldMatchPath) {
        return false;
      }

      return _matchesAllSearchTokens(tokens, displayPath(location));
    }).toList()
      ..sort((a, b) {
        if (tokens.isNotEmpty) {
          final scoreA = _searchScore(tokens, a, shouldMatchPath);
          final scoreB = _searchScore(tokens, b, shouldMatchPath);
          if (scoreA != scoreB) {
            return scoreA.compareTo(scoreB);
          }
        }
        return _sortByNameThenPath(a, b);
      });

    return results;
  }

  List<LocationModel> searchZones(String query) {
    return searchLocations(
      query,
      types: const {LocationType.zone},
    ).where((location) => location.isAssignableToItem).toList();
  }

  LocationModel? areaFor(String uuid) {
    final chain = ancestorsOf(uuid);
    for (final location in chain) {
      if (location.parentUuid == null || location.type == LocationType.area) {
        return location;
      }
    }
    return null;
  }

  LocationModel? roomFor(String uuid) {
    final chain = ancestorsOf(uuid).reversed;
    for (final location in chain) {
      if (location.type == LocationType.room) {
        return location;
      }
    }
    return null;
  }

  bool isDirectZone(LocationModel location) {
    if (location.type != LocationType.zone) return false;
    final parent = parentOf(location);
    return parent == null || parent.type == LocationType.area;
  }

  String displayPath(LocationModel location) {
    final fullPath = location.fullPath?.trim();
    if (fullPath != null && fullPath.isNotEmpty) return fullPath;
    final names =
        ancestorsOf(location.uuid).map((entry) => entry.name).toList();
    return names.isEmpty ? location.name : names.join(' > ');
  }

  static List<String> _queryTokens(String query) {
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  static bool _matchesSearchToken(String token, String target) {
    return FuzzySearch.matches(token, target);
  }

  static bool _matchesAllSearchTokens(List<String> tokens, String target) {
    return tokens.every((token) => _matchesSearchToken(token, target));
  }

  int _searchScore(
    List<String> tokens,
    LocationModel location,
    bool shouldMatchPath,
  ) {
    final path = displayPath(location);
    var totalScore = 0;

    for (final token in tokens) {
      final nameScore = FuzzySearch.score(token, location.name);
      final pathScore =
          shouldMatchPath ? FuzzySearch.score(token, path) + 1 : 999;
      totalScore += nameScore < pathScore ? nameScore : pathScore;
    }

    return totalScore;
  }
}
