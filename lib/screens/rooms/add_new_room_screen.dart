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

  String? _selectedParentUuid;
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
    return const [
      _ZoneOption(
        name: 'Top Shelf',
        icon: Icons.table_rows_rounded,
        iconName: 'shelves',
      ),
      _ZoneOption(
        name: 'Main Closet',
        icon: Icons.door_sliding_outlined,
        iconName: 'door',
      ),
    ];
  }

  void _syncDefaultParent(List<LocationModel> roots) {
    if (_selectedParentUuid != null || roots.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedParentUuid != null) return;
      setState(() => _selectedParentUuid = roots.first.uuid);
    });
  }

  void _resetForm(List<LocationModel> roots) {
    setState(() {
      _roomNameController.clear();
      _selectedParentUuid = roots.isNotEmpty ? roots.first.uuid : null;
      _selectedIconKey = 'bed';
      _zones = _defaultZones();
    });
  }

  Future<void> _addParentLocation() async {
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

    if (!mounted || result == null || result.isEmpty) return;

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
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade400),
      );
      return;
    }

    setState(() => _selectedParentUuid = location.uuid);
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
          selected: true,
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
                        Container(
                          height: 76,
                          decoration: BoxDecoration(
                            color: kCardSoft,
                            borderRadius: BorderRadius.circular(40),
                          ),
                          alignment: Alignment.centerLeft,
                          child: TextField(
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
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 32),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _SectionLabel(
                            label: 'Parent Location', textMuted: textMuted),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            for (final root in roots)
                              _parentChip(root, isDark, textPrimary,
                                  kCardSoft),
                            InkWell(
                              onTap: _addParentLocation,
                              borderRadius: BorderRadius.circular(28),
                              child: Container(
                                height: 62,
                                width: 76,
                                decoration: BoxDecoration(
                                  color: kCardSoft,
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: const Icon(Icons.add,
                                    color: AppColors.primary, size: 38 / 2),
                              ),
                            ),
                          ],
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
                          _zoneRow(_zones[i], i, isDark, kCardSoft,
                              textPrimary, textMuted),
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

  Widget _parentChip(LocationModel root, bool isDark, Color textPrimary,
      Color cardSoft) {
    final selected = _selectedParentUuid == root.uuid;
    return InkWell(
      onTap: () => setState(() => _selectedParentUuid = root.uuid),
      borderRadius: BorderRadius.circular(28),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : cardSoft,
          borderRadius: BorderRadius.circular(28),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.42),
                    blurRadius: 18,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Text(
          root.name,
          style: TextStyle(
            color: selected ? Colors.white : textPrimary,
            fontSize: 20 / 2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
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
