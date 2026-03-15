import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';
import '../../providers/location_providers.dart';
import '../../widgets/app_nav_bar.dart';
import 'add_new_room_screen.dart';

class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  int _expandedRoom = 0;

  final List<_AreaData> _areas = const [
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

  final List<_RoomData> _rooms = const [
    _RoomData(
      name: 'Master Bedroom',
      items: 45,
      icon: Icons.bed_rounded,
      zones: [
        _ZoneData(
            name: 'Bedside Table', count: 12, icon: Icons.table_restaurant),
        _ZoneData(
            name: 'Walk-in Closet', count: 28, icon: Icons.checkroom_outlined),
        _ZoneData(name: 'Top Shelf', count: 5, icon: Icons.table_rows_rounded),
      ],
    ),
    _RoomData(
      name: 'Kitchen',
      items: 82,
      icon: Icons.kitchen_rounded,
      zones: [],
    ),
    _RoomData(
      name: 'Storeroom',
      items: 156,
      icon: Icons.inventory_2_outlined,
      zones: [],
    ),
    _RoomData(
      name: 'Garage',
      items: 32,
      icon: Icons.garage_rounded,
      zones: [],
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

  @override
  Widget build(BuildContext context) {
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
          _TopHeader(onAddTap: _openAddRoomFlow),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: bottomInset + 90),
              children: [
                const SizedBox(height: AppDimensions.spacingMd),
                _SectionTitle(
                  title: 'Houses & Areas',
                  trailing: TextButton(
                    onPressed: () {},
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
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _areas.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (context, index) => _AreaCard(
                      data: _areas[index],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _SectionTitle(
                  title: 'Rooms',
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      '12 total rooms',
                      style: TextStyle(
                        color: kMuted,
                        fontSize: 36 / 2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListView.separated(
                  itemCount: _rooms.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
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
                    );
                  },
                ),
              ],
            ),
          ),
          const AppNavBar(activeTab: AppNavTab.locations),
        ],
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({required this.onAddTap});

  final VoidCallback onAddTap;

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
                onPressed: () {},
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
              color:
                  isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
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
  const _AreaCard({required this.data});

  final _AreaData data;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textMuted =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return SizedBox(
      width: 335,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    data.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: isDark
                          ? AppColors.surfaceVariantDark
                          : AppColors.surfaceVariantLight,
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
                            horizontal: 12, vertical: 5),
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
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
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
  });

  final _RoomData room;
  final bool expanded;
  final Color card;
  final Color cardSoft;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        AppColors.primary.withValues(alpha: expanded ? 0.55 : 0.20);
    return Container(
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
                      color: expanded
                          ? Colors.white
                          : AppColors.primary,
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
                              fontWeight: FontWeight.w500),
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
                  for (final zone in room.zones) ...[
                    _ZoneRow(zone: zone),
                    const SizedBox(height: 10),
                  ],
                  Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.5),
                        style: BorderStyle.solid,
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
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({required this.zone});

  final _ZoneData zone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(zone.icon, color: AppColors.primary, size: 18),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${zone.count}',
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _AreaData {
  const _AreaData({
    required this.name,
    required this.items,
    required this.imageUrl,
    this.isPrimary = false,
  });

  final String name;
  final int items;
  final String imageUrl;
  final bool isPrimary;
}

class _RoomData {
  const _RoomData({
    required this.name,
    required this.items,
    required this.icon,
    required this.zones,
  });

  final String name;
  final int items;
  final IconData icon;
  final List<_ZoneData> zones;
}

class _ZoneData {
  const _ZoneData({
    required this.name,
    required this.count,
    required this.icon,
  });

  final String name;
  final int count;
  final IconData icon;
}
