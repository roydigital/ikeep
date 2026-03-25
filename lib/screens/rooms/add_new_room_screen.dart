import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/uuid_generator.dart';
import '../../domain/models/location_model.dart';
import '../../providers/location_providers.dart';
import '../../theme/app_colors.dart';
import 'rooms_loading_overlay.dart';

// ─────────────────────────────────────────────────────────────
// Top-level preset data
// ─────────────────────────────────────────────────────────────

const _kAreaGroups = [
  _AreaGroup(
    title: 'Residential',
    icon: Icons.home_rounded,
    areas: [
      'House',
      'Apartment',
      'Condo',
      'Townhouse',
      'Villa',
      'Studio',
      'Flat',
      'Penthouse',
      'Duplex',
      'Bungalow',
      'Cabin',
      'Cottage',
      'Beach House',
      'Lake House',
      'Vacation Home',
      'Rental Property',
      'Tiny House',
      'Mobile Home',
      'Dormitory',
      'Student Housing',
      'Assisted Living',
      'Senior Home',
      'Guest House',
    ],
  ),
  _AreaGroup(
    title: 'Office & Commercial',
    icon: Icons.business_rounded,
    areas: [
      'Office',
      'Co-working Space',
      'Shop',
      'Retail Store',
      'Restaurant',
      'Café',
      'Hotel Room',
      'Motel Room',
      'Reception',
      'Lobby',
      'Conference Center',
      'Medical Office',
      'Dental Office',
      'Salon',
      'Gym',
      'Studio Space',
      'Classroom',
      'Laboratory',
      'Library',
      'Bank',
      'Post Office',
      'Clinic',
      'Showroom',
    ],
  ),
  _AreaGroup(
    title: 'Storage & Industrial',
    icon: Icons.warehouse_rounded,
    areas: [
      'Garage',
      'Storage Unit',
      'Warehouse',
      'Workshop',
      'Factory',
      'Barn',
      'Shed',
      'Tool Shed',
      'Locker',
      'Self-Storage',
      'Godown',
      'Cold Storage',
      'Loading Dock',
      'Supply Room',
      'Storeroom',
    ],
  ),
  _AreaGroup(
    title: 'Outdoor & Property',
    icon: Icons.park_rounded,
    areas: [
      'Backyard',
      'Front Yard',
      'Garden',
      'Patio',
      'Terrace',
      'Balcony',
      'Porch',
      'Deck',
      'Driveway',
      'Parking Spot',
      'Rooftop',
      'Farm',
      'Ranch',
      'Field',
      'Greenhouse',
      'Gate Area',
    ],
  ),
  _AreaGroup(
    title: 'Vehicles & Transport',
    icon: Icons.directions_car_rounded,
    areas: [
      'Car',
      'SUV',
      'Van',
      'Truck',
      'Motorcycle',
      'RV',
      'Camper',
      'Boat',
      'Trailer',
      'Bicycle Storage',
    ],
  ),
];

const _kPresetZones = [
  'Top Shelf',
  'Middle Shelf',
  'Bottom Shelf',
  'Main Closet',
  'Walk-in Closet',
  'Wardrobe',
  'Under Bed',
  'Bedside Table',
  'Dresser Drawer',
  'Nightstand',
  'Filing Cabinet',
  'Desk Drawer',
  'Bookshelf',
  'Medicine Cabinet',
  'Bathroom Cabinet',
  'Vanity',
  'Kitchen Cabinet',
  'Pantry Shelf',
  'Refrigerator',
  'Freezer',
  'Garage Shelf',
  'Tool Box',
  'Workbench',
  'Storage Box',
  'Storage Bin',
  'Basket',
  'Corner Rack',
  'Wall Hook',
  'Entryway Shelf',
  'Attic Area',
  'Basement Corner',
];

// ─────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────

class AddNewRoomScreen extends ConsumerStatefulWidget {
  const AddNewRoomScreen({super.key});

  @override
  ConsumerState<AddNewRoomScreen> createState() => _AddNewRoomScreenState();
}

class _AddNewRoomScreenState extends ConsumerState<AddNewRoomScreen> {
  final _roomNameController = TextEditingController();
  final _customZoneController = TextEditingController();

  String? _selectedParentUuid;
  String? _selectedParentName;
  String _selectedIconKey = 'bed';
  bool _isSaving = false;
  bool _isBusy = false;
  String _busyLabel = 'Syncing changes...';

  final Set<String> _selectedZoneNames = {};
  final List<String> _customZones = [];

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

  @override
  void dispose() {
    _roomNameController.dispose();
    _customZoneController.dispose();
    super.dispose();
  }

  Future<T> _runWithLoading<T>({
    required String label,
    required Future<T> Function() action,
  }) async {
    setState(() {
      _isBusy = true;
      _busyLabel = label;
    });

    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyLabel = 'Syncing changes...';
        });
      }
    }
  }

  void _syncDefaultParent(List<LocationModel> roots) {
    if (_selectedParentUuid != null || roots.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedParentUuid != null) return;
      setState(() {
        _selectedParentUuid = roots.first.uuid;
        _selectedParentName = roots.first.name;
      });
    });
  }

  void _resetForm(List<LocationModel> roots) {
    setState(() {
      _roomNameController.clear();
      _customZoneController.clear();
      _selectedParentUuid = roots.isNotEmpty ? roots.first.uuid : null;
      _selectedParentName = roots.isNotEmpty ? roots.first.name : null;
      _selectedIconKey = 'bed';
      _selectedZoneNames.clear();
      _customZones.clear();
    });
  }

  // Opens the searchable area picker bottom sheet.
  Future<void> _showAreaPicker(List<LocationModel> roots) async {
    if (_isBusy) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showModalBottomSheet<_AreaPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AreaPickerSheet(isDark: isDark),
    );

    if (!mounted || result == null) return;

    // If the result has no name (user tapped "Create Custom" without typing),
    // prompt via a dialog instead.
    String areaName = result.name.trim();
    if (result.isNew && areaName.isEmpty) {
      areaName = await _promptCustomAreaName() ?? '';
      if (areaName.isEmpty) return;
    }

    // Check if an area with this name already exists.
    final existing = roots.firstWhere(
      (r) => r.name.trim().toLowerCase() == areaName.toLowerCase(),
      orElse: () => LocationModel(
        uuid: '',
        name: '',
        type: LocationType.area,
        parentUuid: null,
        iconName: '',
        createdAt: DateTime.now(),
      ),
    );

    if (!result.isNew || existing.uuid.isNotEmpty) {
      final target = result.isNew
          ? existing
          : roots.firstWhere((r) => r.uuid == result.uuid);
      setState(() {
        _selectedParentUuid = target.uuid;
        _selectedParentName = target.name;
      });
      return;
    }

    // Create the new area location.
    final location = LocationModel(
      uuid: generateUuid(),
      name: areaName,
      type: LocationType.area,
      parentUuid: null,
      iconName: 'folder',
      createdAt: DateTime.now(),
    );
    final error = await _runWithLoading<String?>(
      label: 'Creating area...',
      action: () =>
          ref.read(locationsNotifierProvider.notifier).saveLocation(location),
    );
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade400),
      );
      return;
    }

    setState(() {
      _selectedParentUuid = location.uuid;
      _selectedParentName = location.name;
    });
  }

  // Simple dialog for entering a custom area name when no search text was typed.
  Future<String?> _promptCustomAreaName() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: Text(
          'Create Custom Area',
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
            hintText: 'e.g., My Office, Beach House…',
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
              'Create',
              style: TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _addCustomZone() {
    final name = _customZoneController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      if (!_customZones.contains(name) && !_kPresetZones.contains(name)) {
        _customZones.insert(0, name);
      }
      _selectedZoneNames.add(name);
      _customZoneController.clear();
    });
  }

  void _toggleZone(String name) {
    setState(() {
      if (_selectedZoneNames.contains(name)) {
        _selectedZoneNames.remove(name);
      } else {
        _selectedZoneNames.add(name);
      }
    });
  }

  Future<void> _createRoom() async {
    if (_isBusy) return;

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
      type: LocationType.room,
      parentUuid: _selectedParentUuid,
      iconName: _selectedIconKey,
      createdAt: DateTime.now(),
    );
    final locationNotifier = ref.read(locationsNotifierProvider.notifier);
    String? roomError;

    try {
      roomError = await _runWithLoading<String?>(
        label: 'Creating room...',
        action: () async {
          final error = await locationNotifier.saveLocation(room);
          if (error != null) return error;

          for (final zoneName in _selectedZoneNames) {
            final lc = zoneName.toLowerCase();
            var iconName = 'folder';
            if (lc.contains('shelf')) iconName = 'shelves';
            if (lc.contains('closet') || lc.contains('wardrobe')) {
              iconName = 'door';
            }

            final zoneError = await locationNotifier.saveLocation(
              LocationModel(
                uuid: generateUuid(),
                name: zoneName,
                type: LocationType.zone,
                parentUuid: room.uuid,
                iconName: iconName,
                createdAt: DateTime.now(),
              ),
            );
            if (zoneError != null) return zoneError;
          }

          return null;
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }

    if (!mounted) return;
    if (roomError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(roomError), backgroundColor: Colors.red.shade400),
      );
      return;
    }

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
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textMuted =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: kBg,
          body: rootsAsync.when(
            data: (roots) {
              _syncDefaultParent(roots);
              return Column(
                children: [
                  _PinnedRoomSheetHeader(
                    backgroundColor: kBg,
                    borderColor: kBorder,
                    textPrimary: textPrimary,
                    onClose: () => Navigator.pop(context),
                    onReset: () => _resetForm(roots),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        // ── Scrollable content ──────────────────────────────
                        Positioned.fill(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                                22, 18, 22, 160 + bottomInset),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Header ────────────────────────────────

                                // ── Room Name ─────────────────────────────
                                _SectionLabel(
                                    label: 'ROOM NAME', textMuted: textMuted),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _roomNameController,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'e.g., Master Bedroom',
                                    hintStyle: TextStyle(
                                      color: textMuted,
                                      fontSize: 16,
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
                                const SizedBox(height: 30),

                                // ── Parent Location ───────────────────────
                                _SectionLabel(
                                    label: 'PARENT LOCATION',
                                    textMuted: textMuted),
                                const SizedBox(height: 4),
                                Text(
                                  'The broader area this room belongs to',
                                  style: TextStyle(
                                      color: textMuted.withValues(alpha: 0.65),
                                      fontSize: 12),
                                ),
                                const SizedBox(height: 12),
                                GestureDetector(
                                  onTap: () => _showAreaPicker(roots),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: kCardSoft,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: _selectedParentUuid != null
                                            ? AppColors.primary
                                                .withValues(alpha: 0.5)
                                            : Colors.transparent,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.13),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          child: const Icon(
                                            Icons.location_on_rounded,
                                            color: AppColors.primary,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _selectedParentName ??
                                                    'Select parent area',
                                                style: TextStyle(
                                                  color: _selectedParentName !=
                                                          null
                                                      ? textPrimary
                                                      : textMuted,
                                                  fontSize: 16,
                                                  fontWeight:
                                                      _selectedParentName !=
                                                              null
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                ),
                                              ),
                                              if (_selectedParentName != null)
                                                Text(
                                                  'Tap to change',
                                                  style: TextStyle(
                                                    color: textMuted.withValues(
                                                        alpha: 0.6),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: AppColors.primary,
                                          size: 26,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 30),

                                // ── Room Icon ─────────────────────────────
                                _SectionLabel(
                                    label: 'ROOM ICON', textMuted: textMuted),
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
                                    mainAxisExtent: 100,
                                  ),
                                  itemBuilder: (context, index) {
                                    final icon = _roomIcons[index];
                                    final selected =
                                        icon.key == _selectedIconKey;
                                    return InkWell(
                                      onTap: () => setState(
                                          () => _selectedIconKey = icon.key),
                                      borderRadius: BorderRadius.circular(22),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 150),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? AppColors.primary
                                                  .withValues(alpha: 0.12)
                                              : kCardSoft,
                                          borderRadius:
                                              BorderRadius.circular(22),
                                          border: Border.all(
                                            color: selected
                                                ? AppColors.primary
                                                : Colors.transparent,
                                            width: 2,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              icon.icon,
                                              color: selected
                                                  ? AppColors.primary
                                                  : textMuted,
                                              size: 28,
                                            ),
                                            const SizedBox(height: 8),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6),
                                              child: Text(
                                                icon.label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: selected
                                                      ? AppColors.primary
                                                      : textMuted,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.8,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 30),

                                // ── Initial Zones ─────────────────────────
                                Row(
                                  children: [
                                    Expanded(
                                      child: _SectionLabel(
                                          label: 'ADD INITIAL ZONES',
                                          textMuted: textMuted),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: kCardSoft,
                                        borderRadius:
                                            BorderRadius.circular(999),
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
                                const SizedBox(height: 4),
                                Text(
                                  'Specific spots within this room to track items',
                                  style: TextStyle(
                                      color: textMuted.withValues(alpha: 0.65),
                                      fontSize: 12),
                                ),
                                const SizedBox(height: 14),

                                // Custom zone text input
                                Container(
                                  decoration: BoxDecoration(
                                    color: kCardSoft,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 4, 8, 4),
                                  child: Row(
                                    children: [
                                      const Icon(
                                          Icons.add_location_alt_outlined,
                                          color: AppColors.primary,
                                          size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextField(
                                          controller: _customZoneController,
                                          style: TextStyle(
                                            color: textPrimary,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'Add a custom zone…',
                                            hintStyle: TextStyle(
                                                color: textMuted, fontSize: 15),
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    vertical: 16),
                                          ),
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) => _addCustomZone(),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: _addCustomZone,
                                        child: Container(
                                          width: 46,
                                          height: 46,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.14),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: const Icon(Icons.add_rounded,
                                              color: AppColors.primary,
                                              size: 24),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Zone chips — custom first, then presets
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    for (final zone in _customZones)
                                      _ZoneChip(
                                        name: zone,
                                        selected:
                                            _selectedZoneNames.contains(zone),
                                        isCustom: true,
                                        isDark: isDark,
                                        textPrimary: textPrimary,
                                        textMuted: textMuted,
                                        onTap: () => _toggleZone(zone),
                                      ),
                                    for (final zone in _kPresetZones)
                                      _ZoneChip(
                                        name: zone,
                                        selected:
                                            _selectedZoneNames.contains(zone),
                                        isCustom: false,
                                        isDark: isDark,
                                        textPrimary: textPrimary,
                                        textMuted: textMuted,
                                        onTap: () => _toggleZone(zone),
                                      ),
                                  ],
                                ),

                                // Selection summary
                                if (_selectedZoneNames.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.22)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.check_circle_rounded,
                                            color: AppColors.primary, size: 18),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            '${_selectedZoneNames.length} zone${_selectedZoneNames.length == 1 ? '' : 's'} will be created',
                                            style: const TextStyle(
                                              color: AppColors.primary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () => setState(
                                              () => _selectedZoneNames.clear()),
                                          child: Text(
                                            'Clear all',
                                            style: TextStyle(
                                              color: textMuted,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
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
                        ),

                        // ── Floating CTA ─────────────────────────────────
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: EdgeInsets.fromLTRB(
                                22, 18, 22, 22 + bottomInset),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  kBg.withValues(alpha: 0.96),
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
                                  disabledBackgroundColor:
                                      AppColors.primaryDark,
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
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Create Room',
                                            style: TextStyle(
                                              fontSize: 24,
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
        if (_isBusy) RoomsLoadingOverlay(label: _busyLabel),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Zone Chip
// ─────────────────────────────────────────────────────────────

class _PinnedRoomSheetHeader extends StatelessWidget {
  const _PinnedRoomSheetHeader({
    required this.backgroundColor,
    required this.borderColor,
    required this.textPrimary,
    required this.onClose,
    required this.onReset,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color textPrimary;
  final VoidCallback onClose;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(color: borderColor.withValues(alpha: 0.85)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 74,
                height: 9,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: onClose,
                      icon: Icon(
                        Icons.close_rounded,
                        color: textPrimary,
                        size: 34,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Add New Room',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onReset,
                      child: const Text(
                        'Reset',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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

class _ZoneChip extends StatelessWidget {
  const _ZoneChip({
    required this.name,
    required this.selected,
    required this.isCustom,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final bool isCustom;
  final bool isDark;
  final Color textPrimary;
  final Color textMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardSoft =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.primary.withValues(alpha: 0.14) : cardSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded,
                  color: AppColors.primary, size: 13),
              const SizedBox(width: 5),
            ] else if (isCustom) ...[
              Icon(Icons.star_rounded, color: AppColors.primary, size: 13),
              const SizedBox(width: 5),
            ],
            Text(
              name,
              style: TextStyle(
                color: selected ? AppColors.primary : textMuted,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Area Picker Bottom Sheet
// ─────────────────────────────────────────────────────────────

class _AreaPickerResult {
  const _AreaPickerResult({
    required this.name,
    required this.isNew,
    this.uuid,
  });

  final String name;
  final bool isNew;
  final String? uuid;
}

class _AreaPickerSheet extends ConsumerStatefulWidget {
  const _AreaPickerSheet({required this.isDark});

  final bool isDark;

  @override
  ConsumerState<_AreaPickerSheet> createState() => _AreaPickerSheetState();
}

class _AreaPickerSheetState extends ConsumerState<_AreaPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _isBusy = false;
  String _busyLabel = 'Syncing area...';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<T> _runWithLoading<T>({
    required String label,
    required Future<T> Function() action,
  }) async {
    setState(() {
      _isBusy = true;
      _busyLabel = label;
    });

    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyLabel = 'Syncing area...';
        });
      }
    }
  }

  List<String> get _allPresets => _kAreaGroups.expand((g) => g.areas).toList();

  // Returns true when the area name matches a built-in preset, meaning
  // it was not typed by the user (edit should be disabled for these).
  bool _isPresetArea(String name) {
    final lc = name.toLowerCase();
    return _kAreaGroups.any((g) => g.areas.any((a) => a.toLowerCase() == lc));
  }

  // ── Swipe-to-edit (custom areas only) ──────────────────────────────────────

  Future<void> _editArea(LocationModel area) async {
    if (_isBusy) return;

    final isDark = widget.isDark;
    final controller = TextEditingController(text: area.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: Text(
          'Rename Area',
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Area name',
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
                  color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName == null ||
        newName.isEmpty ||
        newName == area.name ||
        !mounted) {
      return;
    }

    // Prevent renaming to a name that already exists.
    final currentAreas =
        ref.read(rootLocationsProvider).valueOrNull ?? const <LocationModel>[];
    final isDuplicate = currentAreas.any(
      (a) =>
          a.uuid != area.uuid &&
          a.name.trim().toLowerCase() == newName.toLowerCase(),
    );
    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$newName" already exists.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final error = await _runWithLoading<String?>(
      label: 'Updating area...',
      action: () => ref
          .read(locationsNotifierProvider.notifier)
          .updateLocation(area.copyWith(name: newName)),
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    }
  }

  // ── Swipe-to-delete (all saved areas) ──────────────────────────────────────

  Future<void> _deleteArea(LocationModel area) async {
    if (_isBusy) return;

    final isDark = widget.isDark;
    final allLocs =
        ref.read(allLocationsProvider).valueOrNull ?? const <LocationModel>[];
    final hasChildren = allLocs.any((l) => l.parentUuid == area.uuid);

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor:
                isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            title: Text(
              'Delete "${area.name}"?',
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              hasChildren
                  ? 'All rooms and zones inside it will also be removed.'
                  : 'This cannot be undone.',
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
                      color: AppColors.error, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    final error = await _runWithLoading<String?>(
      label: 'Deleting area...',
      action: () => ref
          .read(locationsNotifierProvider.notifier)
          .deleteLocation(area.uuid),
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    }
  }

  // ── Swipeable tile for "Your Saved Areas" ───────────────────────────────────

  Widget _buildSavedAreaTile(LocationModel area) {
    final isDark = widget.isDark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final cardColor =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;
    final isPreset = _isPresetArea(area.name);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Dismissible(
          key: ValueKey('saved-area-${area.uuid}'),
          // Preset areas: delete only. Custom areas: edit + delete.
          direction: isPreset
              ? DismissDirection.endToStart
              : DismissDirection.horizontal,
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              await _editArea(area);
            } else {
              await _deleteArea(area);
            }
            return false; // reactive rebuild handles removal after delete
          },
          // Left-to-right background: Edit (custom areas only)
          background: isPreset
              ? const SizedBox.shrink()
              : Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  color: AppColors.primary,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                      SizedBox(width: 6),
                      Text(
                        'EDIT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
          // Right-to-left background: Delete (always)
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: AppColors.error,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'DELETE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 6),
                Icon(Icons.delete_outline_rounded,
                    color: Colors.white, size: 20),
              ],
            ),
          ),
          child: Material(
            color: cardColor,
            child: InkWell(
              onTap: () => Navigator.pop(
                context,
                _AreaPickerResult(
                    name: area.name, isNew: false, uuid: area.uuid),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        area.name,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.primary.withValues(alpha: 0.45),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final cardColor =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textMuted =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final borderColor = isDark ? AppColors.borderDark : AppColors.borderLight;

    final query = _query.toLowerCase().trim();

    // Watch the live root locations so the list auto-updates after edits/deletes.
    final existingAreas =
        ref.watch(rootLocationsProvider).valueOrNull ?? const <LocationModel>[];
    final existingNamesLc =
        existingAreas.map((a) => a.name.toLowerCase()).toSet();

    // Filtered existing areas
    final filteredExisting = existingAreas
        .where((a) => query.isEmpty || a.name.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // For non-empty queries: flat filtered list (excluding already-saved names)
    final filteredPresets = query.isEmpty
        ? null
        : _allPresets
            .where((a) =>
                a.toLowerCase().contains(query) &&
                !existingNamesLc.contains(a.toLowerCase()))
            .toList();

    return Stack(
      children: [
        Container(
          height: MediaQuery.of(context).size.height * 0.86,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: borderColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  'Select Parent Area',
                  style: TextStyle(
                      color: textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  'The broader location this room lives in',
                  style: TextStyle(color: textMuted, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(color: textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search areas…',
                    hintStyle: TextStyle(color: textMuted),
                    prefixIcon:
                        Icon(Icons.search_rounded, color: textMuted, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: textMuted, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: cardColor,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
                  children: [
                    // ── "Create" option — always pinned at top ──────
                    _AreaTile(
                      name: query.isNotEmpty
                          ? 'Create  "$_query"'
                          : '✍   Create Custom Area',
                      icon: Icons.add_circle_outline_rounded,
                      iconColor: AppColors.primary,
                      textColor: AppColors.primary,
                      tileColor: AppColors.primary.withValues(alpha: 0.08),
                      onTap: () => Navigator.pop(
                        context,
                        _AreaPickerResult(
                          name: query.isNotEmpty ? _query.trim() : '',
                          isNew: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Existing saved areas ─────────────────────────
                    if (filteredExisting.isNotEmpty) ...[
                      _SheetSectionHeader(
                          label: 'YOUR SAVED AREAS',
                          icon: Icons.bookmark_rounded,
                          textMuted: textMuted),
                      for (final area in filteredExisting)
                        _buildSavedAreaTile(area),
                      const SizedBox(height: 14),
                    ],

                    // ── Preset areas ─────────────────────────────────
                    if (filteredPresets != null) ...[
                      // Flat search results
                      if (filteredPresets.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              'No matching areas.\nTap "Create" above to add one.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: textMuted, fontSize: 14),
                            ),
                          ),
                        )
                      else ...[
                        _SheetSectionHeader(
                            label: 'SUGGESTIONS',
                            icon: Icons.lightbulb_outline_rounded,
                            textMuted: textMuted),
                        ...filteredPresets.map(
                          (area) => _AreaTile(
                            name: area,
                            icon: Icons.home_work_rounded,
                            iconColor: textMuted,
                            textColor: textPrimary,
                            tileColor: cardColor,
                            onTap: () => Navigator.pop(
                              context,
                              _AreaPickerResult(name: area, isNew: true),
                            ),
                          ),
                        ),
                      ],
                    ] else ...[
                      // Grouped preset areas (no search active)
                      for (final group in _kAreaGroups) ...[
                        _SheetSectionHeader(
                            label: group.title.toUpperCase(),
                            icon: group.icon,
                            textMuted: textMuted),
                        ...group.areas
                            .where((a) =>
                                !existingNamesLc.contains(a.toLowerCase()))
                            .map(
                              (area) => _AreaTile(
                                name: area,
                                icon: Icons.home_work_rounded,
                                iconColor: textMuted,
                                textColor: textPrimary,
                                tileColor: cardColor,
                                onTap: () => Navigator.pop(
                                  context,
                                  _AreaPickerResult(name: area, isNew: true),
                                ),
                              ),
                            ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_isBusy) RoomsLoadingOverlay(label: _busyLabel),
      ],
    );
  }
}

class _AreaTile extends StatelessWidget {
  const _AreaTile({
    required this.name,
    required this.icon,
    required this.iconColor,
    required this.textColor,
    required this.tileColor,
    required this.onTap,
  });

  final String name;
  final IconData icon;
  final Color iconColor;
  final Color textColor;
  final Color tileColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: tileColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: iconColor.withValues(alpha: 0.45), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetSectionHeader extends StatelessWidget {
  const _SheetSectionHeader({
    required this.label,
    required this.textMuted,
    this.icon,
  });

  final String label;
  final Color textMuted;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 0, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: textMuted, size: 13),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared small widgets & data classes
// ─────────────────────────────────────────────────────────────

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
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
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

class _AreaGroup {
  const _AreaGroup({
    required this.title,
    required this.icon,
    required this.areas,
  });

  final String title;
  final IconData icon;
  final List<String> areas;
}
