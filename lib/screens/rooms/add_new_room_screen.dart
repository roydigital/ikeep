import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/uuid_generator.dart';
import '../../domain/models/location_model.dart';
import '../../providers/location_providers.dart';
import '../../theme/app_colors.dart';

class AddNewRoomScreen extends ConsumerStatefulWidget {
  const AddNewRoomScreen({super.key});

  @override
  ConsumerState<AddNewRoomScreen> createState() => _AddNewRoomScreenState();
}

class _AddNewRoomScreenState extends ConsumerState<AddNewRoomScreen> {
  final _roomNameController = TextEditingController();

  static const String _customParentValue = '__custom_parent_location__';

  String? _selectedParentUuid;
  String? _selectedParentDropdownValue;
  String _selectedIconKey = 'bed';
  bool _isSaving = false;

  late List<_ZoneOption> _zones;

  static const List<_RoomIconOption> _roomIcons = [
    _RoomIconOption(key: 'bed', label: 'BED', icon: Icons.bed_rounded),
    _RoomIconOption(key: 'living', label: 'LIVING', icon: Icons.chair_rounded),
    _RoomIconOption(
        key: 'kitchen', label: 'KITCHEN', icon: Icons.kitchen_rounded),
    _RoomIconOption(key: 'garage', label: 'GARAGE', icon: Icons.garage_rounded),
    _RoomIconOption(key: 'bath', label: 'BATH', icon: Icons.bathtub_outlined),
    _RoomIconOption(
        key: 'office', label: 'OFFICE', icon: Icons.work_outline_rounded),
    _RoomIconOption(
        key: 'dining', label: 'DINING', icon: Icons.restaurant_rounded),
    _RoomIconOption(
        key: 'other', label: 'OTHER', icon: Icons.more_horiz_rounded),
  ];

  static const List<_ParentLocationGroup> _parentLocationGroups = [
    _ParentLocationGroup(
      title: 'Home & Residential',
      locations: [
        'House',
        'Apartment',
        'Villa',
        'Studio',
        'Bedroom',
        'Master Bedroom',
        'Kids Room',
        'Guest Room',
        'Living Room',
        'Family Room',
        'Dining Room',
        'Kitchen',
        'Pantry',
        'Bathroom',
        'Powder Room',
        'Laundry Room',
        'Basement',
        'Attic',
        'Closet',
        'Storage Room',
      ],
    ),
    _ParentLocationGroup(
      title: 'Office & Commercial',
      locations: [
        'Office',
        'Cabin',
        'Conference Room',
        'Reception',
        'Lobby',
        'Break Room',
        'Server Room',
        'Warehouse',
        'Retail Store',
        'Shop Floor',
        'Classroom',
        'Laboratory',
      ],
    ),
    _ParentLocationGroup(
      title: 'Garage, Utility & Service',
      locations: [
        'Garage',
        'Parking Spot',
        'Workshop',
        'Tool Shed',
        'Utility Room',
        'Electrical Room',
        'Pump Room',
        'Boiler Room',
      ],
    ),
    _ParentLocationGroup(
      title: 'Outdoor & Property',
      locations: [
        'Lawn',
        'Garden',
        'Backyard',
        'Front Yard',
        'Patio',
        'Terrace',
        'Balcony',
        'Porch',
        'Driveway',
        'Rooftop',
        'Gate Area',
      ],
    ),
    _ParentLocationGroup(
      title: 'Travel & Vehicles',
      locations: [
        'Car',
        'SUV',
        'Van',
        'Truck',
        'Motorcycle',
        'Bicycle Storage',
        'Camper',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _zones = _defaultZones();
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  List<_ZoneOption> _defaultZones() {
    return [
      const _ZoneOption(
        name: 'Top Shelf',
        icon: Icons.table_rows_rounded,
        iconName: 'shelves',
        selected: false,
      ),
      const _ZoneOption(
        name: 'Main Closet',
        icon: Icons.door_sliding_outlined,
        iconName: 'door',
        selected: false,
      ),
    ];
  }

  void _syncDefaultParent(List<LocationModel> roots) {
    if (_selectedParentUuid != null || roots.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedParentUuid != null) return;
      setState(() {
        _selectedParentUuid = roots.first.uuid;
        _selectedParentDropdownValue = 'existing:${roots.first.uuid}';
      });
    });
  }

  void _resetForm(List<LocationModel> roots) {
    setState(() {
      _roomNameController.clear();
      _selectedParentUuid = roots.isNotEmpty ? roots.first.uuid : null;
      _selectedParentDropdownValue =
          roots.isNotEmpty ? 'existing:${roots.first.uuid}' : null;
      _selectedIconKey = 'bed';
      _zones = _defaultZones();
    });
  }

  Future<String?> _addParentLocation() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: Text(
          'Add Parent Location',
          style: TextStyle(
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
              fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight),
          decoration: InputDecoration(
            hintText: 'e.g., Office',
            hintStyle: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight),
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
            child: Text('Cancel',
                style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Add',
              style: TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (!mounted || result == null || result.isEmpty) return null;

    final location = LocationModel(
      uuid: generateUuid(),
      name: result,
      parentUuid: null,
      iconName: 'folder',
      createdAt: DateTime.now(),
    );
    final error = await ref
        .read(locationsNotifierProvider.notifier)
        .saveLocation(location);
    if (!mounted) return null;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade400),
      );
      return null;
    }

    setState(() {
      _selectedParentUuid = location.uuid;
      _selectedParentDropdownValue = 'existing:${location.uuid}';
    });
    return location.uuid;
  }

  Future<void> _onParentLocationChanged(
    String? selectedValue,
    List<LocationModel> roots,
  ) async {
    if (selectedValue == null) return;

    if (selectedValue == _customParentValue) {
      await _addParentLocation();
      return;
    }

    if (selectedValue.startsWith('existing:')) {
      final uuid = selectedValue.substring('existing:'.length);
      setState(() {
        _selectedParentUuid = uuid;
        _selectedParentDropdownValue = selectedValue;
      });
      return;
    }

    if (!selectedValue.startsWith('preset:')) return;
    final presetName = selectedValue.substring('preset:'.length);
    final existing = roots.where((root) {
      return root.name.trim().toLowerCase() == presetName.trim().toLowerCase();
    }).firstOrNull;

    if (existing != null) {
      setState(() {
        _selectedParentUuid = existing.uuid;
        _selectedParentDropdownValue = 'existing:${existing.uuid}';
      });
      return;
    }

    final newLocation = LocationModel(
      uuid: generateUuid(),
      name: presetName,
      parentUuid: null,
      iconName: 'folder',
      createdAt: DateTime.now(),
    );
    final error = await ref
        .read(locationsNotifierProvider.notifier)
        .saveLocation(newLocation);
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade400),
      );
      return;
    }

    setState(() {
      _selectedParentUuid = newLocation.uuid;
      _selectedParentDropdownValue = 'existing:${newLocation.uuid}';
    });
  }

  Future<void> _addCustomZone() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: Text(
          'Add Custom Zone',
          style: TextStyle(
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
              fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight),
          decoration: InputDecoration(
            hintText: 'e.g., Nightstand Drawer',
            hintStyle: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight),
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
            child: Text('Cancel',
                style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Add',
              style: TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (!mounted || result == null || result.isEmpty) return;

    setState(() {
      _zones.add(
        _ZoneOption(
          name: result,
          icon: Icons.grid_view_rounded,
          iconName: 'folder',
          selected: false,
        ),
      );
    });
  }

  Future<void> _createRoom() async {
    final roomName = _roomNameController.text.trim();
    if (roomName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room name')),
      );
      return;
    }

    if (_selectedParentUuid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a parent location')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final room = LocationModel(
      uuid: generateUuid(),
      name: roomName,
      parentUuid: _selectedParentUuid,
      iconName: _selectedIconKey,
      createdAt: DateTime.now(),
    );
    final locationNotifier = ref.read(locationsNotifierProvider.notifier);
    final roomError = await locationNotifier.saveLocation(room);

    if (roomError != null) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(roomError), backgroundColor: Colors.red.shade400),
      );
      return;
    }

    for (final zone in _zones.where((z) => z.selected)) {
      final zoneError = await locationNotifier.saveLocation(
        LocationModel(
          uuid: generateUuid(),
          name: zone.name,
          parentUuid: room.uuid,
          iconName: zone.iconName,
          createdAt: DateTime.now(),
        ),
      );
      if (zoneError != null) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(zoneError), backgroundColor: Colors.red.shade400),
        );
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final rootsAsync = ref.watch(rootLocationsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kBg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final kCardSoft =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;
    final kBorder = isDark ? AppColors.borderDark : AppColors.borderLight;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textMuted =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: rootsAsync.when(
          data: (roots) {
            _syncDefaultParent(roots);
            return Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 150),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 74,
                            height: 9,
                            decoration: BoxDecoration(
                              color: kBorder,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(Icons.close_rounded,
                                  color: textPrimary, size: 34),
                            ),
                            Expanded(
                              child: Text(
                                'Add New Room',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 50 / 2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _resetForm(roots),
                              child: const Text(
                                'Reset',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 40 / 2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _SectionLabel(label: 'Room Name', textMuted: textMuted),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _roomNameController,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 24 / 2,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g., Master Bedroom',
                            hintStyle: TextStyle(
                              color: textMuted,
                              fontSize: 24 / 2,
                              fontWeight: FontWeight.w600,
                            ),
                            filled: true,
                            fillColor: kCardSoft,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(40),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(40),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(40),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 26),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _SectionLabel(
                            label: 'Parent Location', textMuted: textMuted),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: kCardSoft,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 6),
                          child: DropdownButtonFormField<String>(
                            value: _selectedParentDropdownValue,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                color: AppColors.primary),
                            dropdownColor: isDark
                                ? AppColors.surfaceDark
                                : AppColors.surfaceLight,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                            ),
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            hint: Text(
                              'Select parent location',
                              style: TextStyle(
                                color: textMuted,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            selectedItemBuilder: (context) {
                              return _buildParentDropdownItems(
                                roots: roots,
                                textPrimary: textPrimary,
                                textMuted: textMuted,
                              )
                                  .map((item) => Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          item.label,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: item.isHeader
                                                ? textMuted
                                                : textPrimary,
                                            fontSize: 16,
                                            fontWeight: item.isHeader
                                                ? FontWeight.w500
                                                : FontWeight.w700,
                                          ),
                                        ),
                                      ))
                                  .toList();
                            },
                            items: _buildParentDropdownItems(
                              roots: roots,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            )
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item.value,
                                    enabled: !item.isHeader,
                                    child: Text(
                                      item.label,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: item.isHeader
                                            ? textMuted
                                            : textPrimary,
                                        fontSize: item.isHeader ? 13 : 15,
                                        fontWeight: item.isHeader
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        letterSpacing: item.isHeader ? 0.6 : 0,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                _onParentLocationChanged(value, roots),
                          ),
                        ),
                        const SizedBox(height: 30),
                        _SectionLabel(label: 'Room Icon', textMuted: textMuted),
                        const SizedBox(height: 12),
                        GridView.builder(
                          itemCount: _roomIcons.length,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.9,
                          ),
                          itemBuilder: (context, index) {
                            final icon = _roomIcons[index];
                            final selected = icon.key == _selectedIconKey;
                            return InkWell(
                              onTap: () =>
                                  setState(() => _selectedIconKey = icon.key),
                              borderRadius: BorderRadius.circular(22),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: kCardSoft,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.primary
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      icon.icon,
                                      color: selected
                                          ? AppColors.primary
                                          : textMuted,
                                      size: 28,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      icon.label,
                                      style: TextStyle(
                                        color: selected
                                            ? AppColors.primary
                                            : textMuted,
                                        fontSize: 32 / 2,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Expanded(
                                child: _SectionLabel(
                                    label: 'Add Initial Zones',
                                    textMuted: textMuted)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: kCardSoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'OPTIONAL',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        for (var i = 0; i < _zones.length; i++) ...[
                          _zoneRow(_zones[i], i, isDark, kCardSoft, textPrimary,
                              textMuted),
                          const SizedBox(height: 10),
                        ],
                        InkWell(
                          onTap: _addCustomZone,
                          borderRadius: BorderRadius.circular(30),
                          child: CustomPaint(
                            painter: _DashedRRectPainter(
                              color: kBorder,
                              strokeWidth: 2,
                              radius: 30,
                              dashLength: 9,
                              gapLength: 6,
                            ),
                            child: Container(
                              width: double.infinity,
                              height: 86,
                              decoration: BoxDecoration(
                                color: (isDark
                                        ? AppColors.surfaceDark
                                        : AppColors.surfaceLight)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_circle,
                                      color: textMuted, size: 34 / 2),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Add Custom Zone',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 20 / 2,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          kBg,
                          kBg,
                        ],
                      ),
                    ),
                    child: SizedBox(
                      height: 82,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _createRoom,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.primaryDark,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.6,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Create Room',
                                    style: TextStyle(
                                      fontSize: 48 / 2,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Icon(Icons.arrow_forward_ios_rounded,
                                      size: 28),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Failed to load parent locations.\n$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondaryDark),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_ParentDropdownEntry> _buildParentDropdownItems({
    required List<LocationModel> roots,
    required Color textPrimary,
    required Color textMuted,
  }) {
    final entries = <_ParentDropdownEntry>[
      const _ParentDropdownEntry(
        value: _customParentValue,
        label: '✍ Create Custom Location',
      ),
    ];

    if (roots.isNotEmpty) {
      entries.add(const _ParentDropdownEntry(
        value: '__header_saved__',
        label: 'YOUR SAVED LOCATIONS',
        isHeader: true,
      ));
      final sortedRoots = [...roots]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      for (final root in sortedRoots) {
        entries.add(_ParentDropdownEntry(
          value: 'existing:${root.uuid}',
          label: root.name,
        ));
      }
    }

    final rootNames = roots.map((r) => r.name.trim().toLowerCase()).toSet();
    for (var i = 0; i < _parentLocationGroups.length; i++) {
      final group = _parentLocationGroups[i];
      entries.add(_ParentDropdownEntry(
        value: '__header_group_$i',
        label: group.title.toUpperCase(),
        isHeader: true,
      ));

      for (final location in group.locations) {
        if (rootNames.contains(location.trim().toLowerCase())) continue;
        entries.add(_ParentDropdownEntry(
          value: 'preset:$location',
          label: location,
        ));
      }
    }

    return entries;
  }

  Widget _zoneRow(_ZoneOption zone, int index, bool isDark, Color cardSoft,
      Color textPrimary, Color textMuted) {
    return InkWell(
      onTap: () => setState(
          () => _zones[index] = zone.copyWith(selected: !zone.selected)),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 98,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: cardSoft,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(zone.icon, color: textMuted, size: 34 / 2),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                zone.name,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 44 / 2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: zone.selected
                      ? AppColors.primary
                      : (isDark ? AppColors.borderDark : AppColors.borderLight),
                  width: 2.4,
                ),
              ),
              child: zone.selected
                  ? const Center(
                      child: Icon(Icons.circle,
                          size: 12, color: AppColors.primary),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.textMuted});

  final String label;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: textMuted,
        fontSize: 22 / 2,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _RoomIconOption {
  const _RoomIconOption({
    required this.key,
    required this.label,
    required this.icon,
  });

  final String key;
  final String label;
  final IconData icon;
}

class _ZoneOption {
  const _ZoneOption({
    required this.name,
    required this.icon,
    required this.iconName,
    this.selected = false,
  });

  final String name;
  final IconData icon;
  final String iconName;
  final bool selected;

  _ZoneOption copyWith({
    String? name,
    IconData? icon,
    String? iconName,
    bool? selected,
  }) {
    return _ZoneOption(
      name: name ?? this.name,
      icon: icon ?? this.icon,
      iconName: iconName ?? this.iconName,
      selected: selected ?? this.selected,
    );
  }
}

class _ParentLocationGroup {
  const _ParentLocationGroup({required this.title, required this.locations});

  final String title;
  final List<String> locations;
}

class _ParentDropdownEntry {
  const _ParentDropdownEntry({
    required this.value,
    required this.label,
    this.isHeader = false,
  });

  final String value;
  final String label;
  final bool isHeader;
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dashLength,
    required this.gapLength,
  });

  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next =
            (distance + dashLength).clamp(0.0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength;
  }
}
