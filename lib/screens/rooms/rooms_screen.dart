import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/uuid_generator.dart';
import '../../domain/models/location_model.dart';
import '../../providers/location_providers.dart';
import '../../providers/service_providers.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';
import '../../widgets/app_nav_bar.dart';
import 'add_new_room_screen.dart';

class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  int _expandedRoom = -1;
  final ScrollController _areasScrollController = ScrollController();
  final Map<String, String> _locationImageByUuid = {};

  final List<_AreaData> _areaImages = const [
    _AreaData(
      name: 'Home',
      items: 124,
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuAOwLoIEJauLq9yO69sj00Xh0BcwavrJBwOmoqGmgXq8Op_XN0G_1D6QSolaOehT2nbqDRZLpS8jjG2ky5cO_nJrYdovxIu7UZCItLuTmpg9xezcb2ANnQxr6g8H0e0b8By1XpLndnpCQYF7iiP4sYqztRgNPMGL2S1pQMuasHkzAOpgrmdLSoiVmf_zZkQ7kKSqFF2cjsrmfYkEbSwB6-N2YrSXTg_inWIHaihd2649iL3X10KOmYRkd9Z8ow116i4oxn1Z7POX2d1',
      isPrimary: true,
    ),
    _AreaData(
      name: 'Office',
      items: 42,
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuBJFC-fJG5vZGRLbZqivHZeqmIdWcuagvDuHHQAzLSthFrGIdlqu2b5h5E7KUCOv8miG4vzGx3Gk-P1CmkKgppFaynJ3OkcnLkGlqAotzunUWprClKKhWcvewzC3hGpZAbI5-oaCeUwEavHc2BsLIkgLGvOYyPNlw5XfOr-6kjHAgDYqk-uqlTydxlsaV4kYa3DWYCAC-nW6SwW9zleeN7s7-ho1v5CbcWB-2K8hmTjZvmG1HZqaHQ6q1dFLudwXX7pUQW9oY3FPHJ3',
    ),
  ];

  Future<void> _openAddRoomFlow() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.98,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: const AddNewRoomScreen(),
          ),
        );
      },
    );

    if (created == true) {
      ref.invalidate(allLocationsProvider);
      ref.invalidate(rootLocationsProvider);
    }
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editLocationName(
    LocationModel location, {
    required String label,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: location.name);
    final updatedName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: Text(
          'Edit $label',
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
          decoration: InputDecoration(
            hintText: '$label name',
            hintStyle: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
            filled: true,
            fillColor:
                isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Save',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted || updatedName == null || updatedName.isEmpty) return;
    if (updatedName == location.name) return;

    final error = await ref
        .read(locationsNotifierProvider.notifier)
        .updateLocation(location.copyWith(name: updatedName));

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade400),
      );
      return;
    }

    _showInfo('$label updated');
  }

  Future<void> _deleteLocation(
    LocationModel location, {
    required String label,
    bool cascades = false,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor:
                isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            title: Text(
              'Delete $label?',
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              cascades
                  ? 'This will delete ${location.name} and all child locations under it.'
                  : 'This action cannot be undone.',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted || !confirmed) return;

    final existingImage = _locationImageByUuid[location.uuid];
    final error =
        await ref.read(locationsNotifierProvider.notifier).deleteLocation(
              location.uuid,
            );

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade400),
      );
      return;
    }

    if (existingImage != null && !existingImage.startsWith('http')) {
      await ref.read(imageServiceProvider).deleteImage(existingImage);
    }
    setState(() {
      _locationImageByUuid.remove(location.uuid);
    });

    _showInfo('$label deleted');
  }

  Future<void> _pickLocationImage(LocationModel location) async {
    final selected = await showModalBottomSheet<_ImageSourceOption>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Use Camera'),
                onTap: () => Navigator.pop(ctx, _ImageSourceOption.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, _ImageSourceOption.gallery),
              ),
              Divider(
                height: 1,
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
              ListTile(
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null) return;

    try {
      final previousPath = _locationImageByUuid[location.uuid];
      final imageService = ref.read(imageServiceProvider);
      final newPath = selected == _ImageSourceOption.camera
          ? await imageService.pickFromCamera()
          : await imageService.pickFromGallery();

      if (!mounted) return;
      setState(() {
        _locationImageByUuid[location.uuid] = newPath;
      });

      if (previousPath != null &&
          previousPath != newPath &&
          !previousPath.startsWith('http')) {
        await imageService.deleteImage(previousPath);
      }

      _showInfo('Image updated');
    } catch (e) {
      if (!mounted) return;
      _showInfo(e.toString());
    }
  }

  Future<void> _deleteLocationImage(LocationModel location) async {
    final imagePath = _locationImageByUuid[location.uuid];
    if (imagePath == null) {
      _showInfo('No image found for this location');
      return;
    }

    if (!imagePath.startsWith('http')) {
      await ref.read(imageServiceProvider).deleteImage(imagePath);
    }

    if (!mounted) return;
    setState(() {
      _locationImageByUuid.remove(location.uuid);
    });
    _showInfo('Image removed');
  }

  Future<void> _showLocationActions(
    LocationModel location, {
    required String label,
    bool cascadesOnDelete = false,
  }) async {
    final hasImage = _locationImageByUuid.containsKey(location.uuid);

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text('Edit $label Name'),
              onTap: () {
                Navigator.pop(ctx);
                _editLocationName(location, label: label);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(hasImage ? 'Update Image' : 'Add Image'),
              onTap: () {
                Navigator.pop(ctx);
                _pickLocationImage(location);
              },
            ),
            if (hasImage)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete Image'),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteLocationImage(location);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: Text('Delete $label'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteLocation(
                  location,
                  label: label,
                  cascades: cascadesOnDelete,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String? _locationImagePath(String uuid) => _locationImageByUuid[uuid];

  Future<void> _handleViewAllAreasTap() async {
    if (!_areasScrollController.hasClients) return;

    final position = _areasScrollController.position;
    if (position.maxScrollExtent <= 0) {
      _showInfo('All areas are already visible here.');
      return;
    }

    final isAtEnd = position.pixels >= (position.maxScrollExtent - 8);
    await _areasScrollController.animateTo(
      isAtEnd ? 0 : position.maxScrollExtent,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _addZoneToRoom(_RoomData room) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    final zoneName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: Text(
          'Add Zone',
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
          decoration: InputDecoration(
            hintText: 'e.g., Wardrobe Top Rack',
            hintStyle: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
            filled: true,
            fillColor:
                isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Add',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted || zoneName == null || zoneName.isEmpty) return;

    final error =
        await ref.read(locationsNotifierProvider.notifier).saveLocation(
              LocationModel(
                uuid: generateUuid(),
                name: zoneName,
                parentUuid: room.uuid,
                iconName: 'folder',
                createdAt: DateTime.now(),
              ),
            );

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade400),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Zone added to ${room.name}')),
    );
  }

  IconData _iconForLocation(String iconName) {
    switch (iconName) {
      case 'bed':
        return Icons.bed_rounded;
      case 'living':
        return Icons.chair_rounded;
      case 'kitchen':
        return Icons.kitchen_rounded;
      case 'garage':
        return Icons.garage_rounded;
      case 'bath':
        return Icons.bathtub_outlined;
      case 'office':
        return Icons.work_outline_rounded;
      case 'dining':
        return Icons.restaurant_rounded;
      case 'door':
        return Icons.door_sliding_outlined;
      case 'shelves':
        return Icons.table_rows_rounded;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  ({List<LocationModel> roots, List<_RoomData> rooms}) _mapLocations(
    List<LocationModel> allLocations,
  ) {
    final byUuid = <String, LocationModel>{
      for (final location in allLocations) location.uuid: location,
    };

    final roots = allLocations.where((location) => location.isRoot).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final roomLocations = allLocations.where((location) {
      final parentUuid = location.parentUuid;
      if (parentUuid == null) return false;
      final parent = byUuid[parentUuid];
      return parent != null && parent.isRoot;
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final roomUuids = roomLocations.map((room) => room.uuid).toSet();

    final zonesByRoom = <String, List<LocationModel>>{};
    for (final location in allLocations) {
      final parentUuid = location.parentUuid;
      if (parentUuid != null && roomUuids.contains(parentUuid)) {
        zonesByRoom
            .putIfAbsent(parentUuid, () => <LocationModel>[])
            .add(location);
      }
    }

    final rooms = roomLocations.map((room) {
      final zoneLocations = List<LocationModel>.from(
        zonesByRoom[room.uuid] ?? const <LocationModel>[],
      )..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      return _RoomData(
        location: room,
        uuid: room.uuid,
        name: room.name,
        items: room.usageCount,
        icon: _iconForLocation(room.iconName),
        zones: zoneLocations
            .map(
              (zone) => _ZoneData(
                location: zone,
                uuid: zone.uuid,
                name: zone.name,
                count: zone.usageCount,
                icon: _iconForLocation(zone.iconName),
              ),
            )
            .toList(),
      );
    }).toList();

    return (roots: roots, rooms: rooms);
  }

  @override
  void dispose() {
    _areasScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(allLocationsProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kBg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final kCard = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final kCardSoft =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;
    final kMuted =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor: kBg,
      body: Column(
        children: [
          _TopHeader(
            onAddTap: _openAddRoomFlow,
            onSearchTap: () => context.push(AppRoutes.search),
          ),
          Expanded(
            child: locationsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Failed to load locations.\n$error',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kMuted),
                  ),
                ),
              ),
              data: (allLocations) {
                final mapped = _mapLocations(allLocations);
                final roots = mapped.roots;
                final rooms = mapped.rooms;

                final areaLocations = allLocations.isNotEmpty
                    ? [
                        ...roots,
                        ...allLocations.where((location) => !location.isRoot),
                      ]
                    : const <LocationModel>[];

                final areas = areaLocations.isNotEmpty
                    ? areaLocations
                        .asMap()
                        .entries
                        .map(
                          (entry) => _AreaData(
                            location: entry.value,
                            name: entry.value.name,
                            items: entry.value.usageCount,
                            imageUrl: _locationImagePath(entry.value.uuid) ??
                                _areaImages[entry.key % _areaImages.length]
                                    .imageUrl,
                            isPrimary: entry.key == 0 &&
                                entry.value.parentUuid == null,
                          ),
                        )
                        .toList()
                    : _areaImages;

                return ListView(
                  padding: EdgeInsets.only(bottom: bottomInset + 90),
                  children: [
                    const SizedBox(height: AppDimensions.spacingMd),
                    _SectionTitle(
                      title: 'Houses & Areas',
                      trailing: TextButton(
                        onPressed: _handleViewAllAreasTap,
                        child: const Text(
                          'View All',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 290,
                      child: ListView.separated(
                        controller: _areasScrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: areas.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (context, index) {
                          final area = areas[index];
                          return _AreaCard(
                            data: area,
                            onTap: area.location == null
                                ? null
                                : () => _showLocationActions(
                                      area.location!,
                                      label: area.location!.isRoot
                                          ? 'Area'
                                          : 'Zone',
                                      cascadesOnDelete: true,
                                    ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 22),
                    _SectionTitle(
                      title: 'Rooms',
                      trailing: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(
                          '${rooms.length} total rooms',
                          style: TextStyle(
                            color: kMuted,
                            fontSize: 36 / 2,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (rooms.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: kCardSoft,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'No rooms added yet. Tap + to create your first room.',
                            style: TextStyle(color: kMuted),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        itemCount: rooms.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final room = rooms[index];
                          final expanded = _expandedRoom == index;
                          return _RoomCard(
                            room: room,
                            expanded: expanded,
                            card: kCard,
                            cardSoft: kCardSoft,
                            muted: kMuted,
                            onTap: () {
                              setState(() {
                                _expandedRoom = expanded ? -1 : index;
                              });
                            },
                            onAddZoneTap: () {
                              _addZoneToRoom(room);
                            },
                            onSwipeEdit: () {
                              _editLocationName(room.location, label: 'Room');
                            },
                            onSwipeDelete: () {
                              _deleteLocation(
                                room.location,
                                label: 'Room',
                                cascades: true,
                              );
                            },
                            onZoneTap: (zone) {
                              _showLocationActions(zone.location,
                                  label: 'Zone');
                            },
                            onZoneSwipeEdit: (zone) {
                              _editLocationName(zone.location, label: 'Zone');
                            },
                            onZoneSwipeDelete: (zone) {
                              _deleteLocation(zone.location, label: 'Zone');
                            },
                            imagePathForUuid: _locationImagePath,
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ),
          const AppNavBar(activeTab: AppNavTab.locations),
        ],
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({required this.onAddTap, required this.onSearchTap});

  final VoidCallback onAddTap;
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        border: Border(
          bottom: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 0.6,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              const Icon(Icons.grid_view_rounded,
                  color: AppColors.primary, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Rooms & Zones',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                    fontSize: 44 / 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onSearchTap,
                icon: Icon(
                  Icons.search_rounded,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              InkWell(
                onTap: onAddTap,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 30),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.trailing});

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 0),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
              fontSize: 52 / 2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          trailing,
        ],
      ),
    );
  }
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({required this.data, this.onTap});

  final _AreaData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textMuted =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final isNetworkImage = data.imageUrl.startsWith('http');

    return SizedBox(
      width: 335,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    isNetworkImage
                        ? Image.network(
                            data.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: isDark
                                  ? AppColors.surfaceVariantDark
                                  : AppColors.surfaceVariantLight,
                              child: const Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: AppColors.primary,
                                  size: 28,
                                ),
                              ),
                            ),
                          )
                        : Image.file(
                            File(data.imageUrl),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: isDark
                                  ? AppColors.surfaceVariantDark
                                  : AppColors.surfaceVariantLight,
                              child: const Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: AppColors.primary,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.45),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (data.isPrimary)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'PRIMARY',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              data.name,
              style: TextStyle(
                color: textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: textMuted, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${data.items} items',
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.expanded,
    required this.card,
    required this.cardSoft,
    required this.muted,
    required this.onTap,
    required this.onAddZoneTap,
    required this.onSwipeEdit,
    required this.onSwipeDelete,
    required this.onZoneTap,
    required this.onZoneSwipeEdit,
    required this.onZoneSwipeDelete,
    required this.imagePathForUuid,
  });

  final _RoomData room;
  final bool expanded;
  final Color card;
  final Color cardSoft;
  final Color muted;
  final VoidCallback onTap;
  final VoidCallback onAddZoneTap;
  final VoidCallback onSwipeEdit;
  final VoidCallback onSwipeDelete;
  final ValueChanged<_ZoneData> onZoneTap;
  final ValueChanged<_ZoneData> onZoneSwipeEdit;
  final ValueChanged<_ZoneData> onZoneSwipeDelete;
  final String? Function(String uuid) imagePathForUuid;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        AppColors.primary.withValues(alpha: expanded ? 0.55 : 0.20);

    return _SwipeActionCard(
      dismissKey: ValueKey('room-${room.uuid}'),
      onEdit: onSwipeEdit,
      onDelete: onSwipeDelete,
      child: Container(
        decoration: BoxDecoration(
          color: expanded ? card : cardSoft,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: borderColor),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: expanded
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.backgroundDark
                                : AppColors.surfaceVariantLight),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        room.icon,
                        color: expanded ? Colors.white : AppColors.primary,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room.name,
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                              fontSize: 42 / 2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${room.items} items',
                            style: TextStyle(
                              color: muted,
                              fontSize: 18 / 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: expanded ? AppColors.primary : muted,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 96),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'ACTIVE ZONES',
                    style: TextStyle(
                      color: muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 96),
                child: Column(
                  children: [
                    if (room.zones.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'No zones added yet',
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                        ),
                      )
                    else
                      for (final zone in room.zones) ...[
                        _ZoneRow(
                          zone: zone,
                          imagePath: imagePathForUuid(zone.uuid),
                          onTap: () => onZoneTap(zone),
                          onSwipeEdit: () => onZoneSwipeEdit(zone),
                          onSwipeDelete: () => onZoneSwipeDelete(zone),
                        ),
                        const SizedBox(height: 10),
                      ],
                    InkWell(
                      onTap: onAddZoneTap,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '+  Add Zone',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 18 / 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.zone,
    required this.onTap,
    required this.onSwipeEdit,
    required this.onSwipeDelete,
    this.imagePath,
  });

  final _ZoneData zone;
  final VoidCallback onTap;
  final VoidCallback onSwipeEdit;
  final VoidCallback onSwipeDelete;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isNetworkImage = imagePath?.startsWith('http') ?? false;

    return _SwipeActionCard(
      dismissKey: ValueKey('zone-${zone.uuid}'),
      onEdit: onSwipeEdit,
      onDelete: onSwipeDelete,
      borderRadius: 18,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: imagePath == null
                    ? Icon(zone.icon, color: AppColors.primary, size: 18)
                    : (isNetworkImage
                        ? Image.network(
                            imagePath!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              zone.icon,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          )
                        : Image.file(
                            File(imagePath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              zone.icon,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          )),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  zone.name,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${zone.count}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeActionCard extends StatelessWidget {
  const _SwipeActionCard({
    required this.dismissKey,
    required this.child,
    required this.onEdit,
    required this.onDelete,
    this.borderRadius = 26,
  });

  final Key dismissKey;
  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Dismissible(
        key: dismissKey,
        direction: DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            onEdit();
          } else {
            onDelete();
          }
          return false;
        },
        background: _SwipeActionBackground(
          isEdit: true,
          borderRadius: borderRadius,
        ),
        secondaryBackground: _SwipeActionBackground(
          isEdit: false,
          borderRadius: borderRadius,
        ),
        child: child,
      ),
    );
  }
}

class _SwipeActionBackground extends StatelessWidget {
  const _SwipeActionBackground({
    required this.isEdit,
    required this.borderRadius,
  });

  final bool isEdit;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final color = isEdit ? AppColors.primary : Colors.red;
    final alignment = isEdit ? Alignment.centerLeft : Alignment.centerRight;
    final text = isEdit ? 'EDIT' : 'DELETE';

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignment,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _AreaData {
  const _AreaData({
    this.location,
    required this.name,
    required this.items,
    required this.imageUrl,
    this.isPrimary = false,
  });

  final LocationModel? location;
  final String name;
  final int items;
  final String imageUrl;
  final bool isPrimary;
}

class _RoomData {
  const _RoomData({
    required this.location,
    required this.uuid,
    required this.name,
    required this.items,
    required this.icon,
    required this.zones,
  });

  final LocationModel location;
  final String uuid;
  final String name;
  final int items;
  final IconData icon;
  final List<_ZoneData> zones;
}

class _ZoneData {
  const _ZoneData({
    required this.location,
    required this.uuid,
    required this.name,
    required this.count,
    required this.icon,
  });

  final LocationModel location;
  final String uuid;
  final String name;
  final int count;
  final IconData icon;
}

enum _ImageSourceOption { camera, gallery }
