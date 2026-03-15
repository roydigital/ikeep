import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/models/item.dart';
import '../../providers/history_providers.dart';
import '../../providers/item_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/service_providers.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_nav_bar.dart';

class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key, required this.uuid});
  final String uuid;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  int _selectedImage = 0;

  @override
  Widget build(BuildContext context) {
    final itemAsync = ref.watch(singleItemProvider(widget.uuid));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: itemAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('Error: $e', style: TextStyle(color: textPrimary))),
        data: (item) {
          if (item == null) {
            return Center(
                child: Text('Item not found',
                    style: TextStyle(color: textPrimary)));
          }

          final historyAsync = ref.watch(itemHistoryProvider(item.uuid));
          final images = item.imagePaths;
          final selected = images.isEmpty
              ? null
              : images[_selectedImage.clamp(0, images.length - 1)];

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                        child: Row(
                          children: [
                            IconButton(
                                onPressed: () => context.pop(),
                                icon: const Icon(Icons.arrow_back, size: 30),
                                color: textPrimary),
                            Expanded(
                              child: Text('Item Details',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)),
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: textPrimary),
                              color: isDark
                                  ? AppColors.surfaceVariantDark
                                  : AppColors.surfaceVariantLight,
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'a', child: Text('Details'))
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _MainCard(
                                imagePath: selected,
                                onZoom: () => _zoom(selected, isDark)),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 102,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: images.length + 1,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 14),
                                itemBuilder: (_, i) {
                                  if (i == images.length) {
                                    return InkWell(
                                      onTap: () => _addImage(item),
                                      borderRadius: BorderRadius.circular(22),
                                      child: Ink(
                                        width: 102,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? AppColors.surfaceVariantDark
                                              : AppColors.surfaceVariantLight,
                                          borderRadius:
                                              BorderRadius.circular(22),
                                        ),
                                        child: const Icon(Icons.add_a_photo,
                                            color: AppColors.primary),
                                      ),
                                    );
                                  }
                                  final active = i == _selectedImage;
                                  return InkWell(
                                    onTap: () =>
                                        setState(() => _selectedImage = i),
                                    borderRadius: BorderRadius.circular(22),
                                    child: Container(
                                      width: 102,
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(
                                            color: active
                                                ? AppColors.primary
                                                : Colors.transparent,
                                            width: 2),
                                      ),
                                      child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          child: _img(
                                              images[i], BoxFit.cover, isDark)),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 22),
                            Text(item.name,
                                style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 27,
                                    fontWeight: FontWeight.w800,
                                    height: 1.05)),
                            const SizedBox(height: 8),
                            Row(children: [
                              const Icon(Icons.location_on,
                                  color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _location(item),
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 17),
                                ),
                              ),
                            ]),
                            if (item.tags.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: item.tags
                                    .map((t) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? AppColors.surfaceVariantDark
                                                : AppColors.surfaceVariantLight,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text('#$t',
                                              style: const TextStyle(
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.w600)),
                                        ))
                                    .toList(),
                              ),
                            ],
                            const SizedBox(height: 24),
                            historyAsync.when(
                              data: (h) => _meta(context, isDark, item.savedAt,
                                  h.isEmpty ? item.updatedAt : h.first.movedAt),
                              loading: () => _meta(context, isDark,
                                  item.savedAt, item.updatedAt),
                              error: (_, __) => _meta(context, isDark,
                                  item.savedAt, item.updatedAt),
                            ),
                            const SizedBox(height: 24),
                            Row(children: [
                              Expanded(
                                  child: _Action(
                                      label: 'Update\nLocation',
                                      filled: false,
                                      icon: Icons.edit_location_alt,
                                      onTap: () => _updateLocation(item))),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: _Action(
                                      label: 'Found /\nRemove',
                                      filled: true,
                                      icon: Icons.check_circle,
                                      onTap: () => _foundRemove(item))),
                            ]),
                            const SizedBox(height: 44),
                            Text('Location History',
                                style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 20),
                            historyAsync.when(
                              loading: () => const Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.primary)),
                              error: (_, __) => Text('Could not load history',
                                  style: TextStyle(
                                      color: isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondaryLight)),
                              data: (h) {
                                if (h.isEmpty) {
                                  return Text('No movement history yet.',
                                      style: TextStyle(
                                          color: isDark
                                              ? AppColors.textSecondaryDark
                                              : AppColors.textSecondaryLight));
                                }
                                return Column(
                                  children: List.generate(h.length, (i) {
                                    final e = h[i];
                                    final first = i == 0;
                                    return _HistoryRow(
                                      title: e.locationName,
                                      subtitle: first
                                          ? 'Moved ${_ago(e.movedAt)}'
                                          : DateFormat('MMMM dd, yyyy')
                                              .format(e.movedAt),
                                      first: first,
                                      tail: i != h.length - 1,
                                    );
                                  }),
                                );
                              },
                            ),
                          ]),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: const AppNavBar(activeTab: AppNavTab.items),
              ),
              const _DetailFab(),
            ],
          );
        },
      ),
    );
  }

  Widget _meta(
      BuildContext context, bool isDark, DateTime savedAt, DateTime? movedAt) {
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.primary.withValues(alpha: 0.15)),
          bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(children: [
        Expanded(child: _metaCell(isDark, 'SAVED', _ago(savedAt), textPrimary)),
        Container(
            width: 1,
            height: 52,
            color: AppColors.primary.withValues(alpha: 0.15)),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.only(left: 22),
                child: _metaCell(isDark, 'LAST MOVED',
                    movedAt == null ? '-' : _ago(movedAt), textPrimary))),
      ]),
    );
  }

  Widget _metaCell(bool isDark, String title, String value, Color textPrimary) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              fontSize: 15.5,
              letterSpacing: 1.2)),
      const SizedBox(height: 4),
      Text(value,
          style: TextStyle(
              color: textPrimary, fontSize: 19.5, fontWeight: FontWeight.w600)),
    ]);
  }

  Future<void> _addImage(Item item) async {
    final picked = await ref.read(imageServiceProvider).pickFromGallery();
    if (!mounted) return;
    final updated = item.copyWith(imagePaths: [...item.imagePaths, picked]);
    final error =
        await ref.read(itemsNotifierProvider.notifier).updateItem(updated);
    if (!mounted || error != null) return;
    setState(() => _selectedImage = updated.imagePaths.length - 1);
    ref.invalidate(singleItemProvider(widget.uuid));
  }

  void _zoom(String? path, bool isDark) {
    if (path == null || path.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(children: [
          InteractiveViewer(
              child: AspectRatio(
                  aspectRatio: 1, child: _img(path, BoxFit.contain, isDark))),
          Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white))),
        ]),
      ),
    );
  }

  Future<void> _updateLocation(Item item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locations = await ref.read(allLocationsProvider.future);
    if (!mounted) return;
    String? selected = item.locationUuid;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setInner) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(99))),
              const SizedBox(height: 18),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Update Location',
                      style: TextStyle(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                          fontWeight: FontWeight.w700,
                          fontSize: 20))),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: locations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final l = locations[i];
                    final active = l.uuid == selected;
                    return InkWell(
                      onTap: () => setInner(() => selected = l.uuid),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.primary.withValues(alpha: 0.2)
                              : (isDark
                                  ? AppColors.surfaceVariantDark
                                  : AppColors.surfaceVariantLight),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: active
                                  ? AppColors.primary
                                  : Colors.transparent),
                        ),
                        child: Row(children: [
                          Icon(Icons.place_outlined,
                              color: active
                                  ? AppColors.primary
                                  : (isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondaryLight)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(l.fullPath ?? l.name,
                                  style: TextStyle(
                                      color: isDark
                                          ? AppColors.textPrimaryDark
                                          : AppColors.textPrimaryLight))),
                          if (active)
                            const Icon(Icons.check_circle,
                                color: AppColors.primary),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selected == null
                      ? null
                      : () => Navigator.of(ctx).pop(selected),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(50)),
                  child: const Text('Save Location'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );

    if (result == null || result == item.locationUuid) return;
    final error = await ref
        .read(itemsNotifierProvider.notifier)
        .updateItem(item.copyWith(locationUuid: result));
    if (!mounted || error != null) return;
    ref.invalidate(singleItemProvider(widget.uuid));
    ref.invalidate(itemHistoryProvider(widget.uuid));
  }

  Future<void> _foundRemove(Item item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor:
                isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            title: Text('Found / Remove',
                style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight)),
            content: Text(
                'Mark this item as found and remove it from active items?',
                style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: const Text('Confirm')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final error =
        await ref.read(itemsNotifierProvider.notifier).archiveItem(item.uuid);
    if (!mounted || error != null) return;
    context.pop();
  }

  String _location(Item item) {
    final full = item.locationFullPath?.trim();
    if (full != null && full.isNotEmpty) return full.replaceAll('>', ',');
    return item.locationName?.trim().isNotEmpty == true
        ? item.locationName!
        : 'No location selected';
  }

  static String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) {
      return '${diff.inMinutes} ${diff.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} ${diff.inHours == 1 ? 'hour' : 'hours'} ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'} ago';
    }
    if (diff.inDays < 30) {
      final w = (diff.inDays / 7).floor();
      return '$w ${w == 1 ? 'week' : 'weeks'} ago';
    }
    if (diff.inDays < 365) {
      final m = (diff.inDays / 30).floor();
      return '$m ${m == 1 ? 'month' : 'months'} ago';
    }
    final y = (diff.inDays / 365).floor();
    return '$y ${y == 1 ? 'year' : 'years'} ago';
  }

  Widget _img(String path, BoxFit fit, bool isDark) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(path,
          fit: fit, errorBuilder: (_, __, ___) => _fallback(isDark));
    }
    return Image.file(File(path),
        fit: fit, errorBuilder: (_, __, ___) => _fallback(isDark));
  }

  Widget _fallback(bool isDark) => ColoredBox(
      color:
          isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
      child: Center(
          child: Icon(Icons.broken_image_outlined,
              color: isDark ? Colors.white54 : AppColors.textDisabledLight)));
}

class _MainCard extends StatelessWidget {
  const _MainCard({required this.imagePath, required this.onZoom});
  final String? imagePath;
  final VoidCallback onZoom;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: MediaQuery.of(context).size.width - 40,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isDark
                ? AppColors.surfaceVariantDark
                : AppColors.surfaceVariantLight,
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            AppColors.primary.withValues(alpha: 0.25),
          ],
        ),
      ),
      child: Stack(children: [
        Positioned.fill(
          child: imagePath == null
              ? Icon(Icons.image_outlined,
                  color: isDark ? Colors.white70 : AppColors.textDisabledLight,
                  size: 56)
              : imagePath!.startsWith('http')
                  ? Image.network(imagePath!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                          Icons.broken_image_outlined,
                          color: isDark
                              ? Colors.white70
                              : AppColors.textDisabledLight))
                  : Image.file(File(imagePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                          Icons.broken_image_outlined,
                          color: isDark
                              ? Colors.white70
                              : AppColors.textDisabledLight)),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: InkWell(
            onTap: onZoom,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: AppColors.surfaceDark.withValues(alpha: 0.85),
              ),
              child: const Icon(Icons.zoom_in, color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(
      {required this.label,
      required this.filled,
      required this.icon,
      required this.onTap});
  final String label;
  final bool filled;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Ink(
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border:
              filled ? null : Border.all(color: AppColors.primary, width: 2),
          gradient: filled
              ? const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                )
              : null,
          boxShadow: filled
              ? [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 5))
                ]
              : null,
        ),
        child: Center(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? Colors.white : AppColors.primary),
              child: Icon(icon,
                  color: filled ? AppColors.primary : Colors.black, size: 21),
            ),
            const SizedBox(width: 12),
            Flexible(
                child: Text(label,
                    style: TextStyle(
                        color: filled ? Colors.white : AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 20.5))),
          ]),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(
      {required this.title,
      required this.subtitle,
      required this.first,
      required this.tail});
  final String title;
  final String subtitle;
  final bool first;
  final bool tail;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 32,
        child: Column(children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
                color: first
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.3),
                shape: BoxShape.circle),
            child: Icon(first ? Icons.location_on : Icons.history,
                size: 14, color: first ? Colors.white : AppColors.primary),
          ),
          if (tail)
            Container(
                width: 2,
                height: 48,
                margin: const EdgeInsets.only(top: 4),
                color: AppColors.primary.withValues(alpha: 0.22)),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: textPrimary,
                    fontSize: 20,
                    fontWeight: first ? FontWeight.w700 : FontWeight.w600)),
            Text(subtitle,
                style: TextStyle(color: textSecondary, fontSize: 18)),
          ]),
        ),
      ),
    ]);
  }
}

/// Floating camera FAB that sits above the unified bottom nav bar.
class _DetailFab extends StatelessWidget {
  const _DetailFab();

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: inset + 58.0 - 14.0,
      child: Center(
        child: GestureDetector(
          onTap: () => context.push(AppRoutes.save),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  blurRadius: 28,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: const Icon(
              Icons.photo_camera,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}
