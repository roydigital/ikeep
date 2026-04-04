import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/feature_limits.dart';
import '../../core/utils/uuid_generator.dart';
import '../../domain/models/item.dart';
import '../../domain/models/item_visibility.dart';
import '../../domain/models/location_model.dart';
import '../../domain/models/zone.dart';
import '../../providers/item_providers.dart';
import '../../providers/location_usage_providers.dart';
import '../../providers/ml_label_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';
import '../../widgets/location_picker_sheet.dart';

class SaveScreen extends ConsumerStatefulWidget {
  const SaveScreen({
    super.key,
    this.initialZoneUuid,
  });

  final String? initialZoneUuid;

  @override
  ConsumerState<SaveScreen> createState() => _SaveScreenState();
}

class _SaveScreenState extends ConsumerState<SaveScreen> {
  String? _imagePath;
  bool _isCapturing = true;
  final _nameController = TextEditingController();
  // Holds the fully-resolved zone (with areaUuid, roomUuid populated).
  // Set via the picker sheet or by tapping a quick-pick chip.
  Zone? _selectedZone;
  final List<String> _tags = [];
  bool _isSaving = false;
  bool _showTagInput = false;
  final _tagController = TextEditingController();
  final _tagFocusNode = FocusNode();
  bool _hasExpiry = false;
  DateTime? _expiryDate;
  bool _isLentFlow = false;
  final _lentToController = TextEditingController();
  DateTime _lentOnDate = DateTime.now();
  DateTime? _expectedReturnDate;
  bool _backupToCloud = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initialZoneUuid = widget.initialZoneUuid;
      if (initialZoneUuid != null && initialZoneUuid.trim().isNotEmpty) {
        await _resolveAndSetZone(initialZoneUuid);
      }
      if (mounted) {
        await _capturePhoto();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    _tagFocusNode.dispose();
    _lentToController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    try {
      final path = await ref.read(imageServiceProvider).pickFromCamera();
      if (mounted) {
        setState(() {
          _imagePath = path;
          _isCapturing = false;
        });
      }
    } catch (_) {
      if (mounted) context.pop();
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final path = await ref.read(imageServiceProvider).pickFromGallery();
      if (mounted) {
        setState(() {
          _imagePath = path;
          _isCapturing = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _retakePhoto() async {
    setState(() => _isCapturing = true);
    await _capturePhoto();
  }

  void _applyAiSuggestion(String name) {
    _nameController.text = name;
    setState(() {});
  }

  void _removeTag(String tag) => setState(() => _tags.remove(tag));

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagController.clear();
        _showTagInput = false;
      });
    } else {
      setState(() => _showTagInput = false);
    }
  }

  Future<void> _saveEntry() async {
    if (_isSaving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (_isLentFlow && _lentToController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tell us who you lent this item to'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (_isLentFlow && _expectedReturnDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add an expected return date for lent items'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);

    final item = Item(
      uuid: generateUuid(),
      name: name,
      // Keep locationUuid for backward compat — zoneUuid is the new canonical ref.
      locationUuid: _selectedZone?.uuid,
      areaUuid: _selectedZone?.areaUuid,
      roomUuid: _selectedZone?.roomUuid,
      zoneUuid: _selectedZone?.uuid,
      imagePaths: _imagePath != null ? [_imagePath!] : [],
      tags: _tags,
      savedAt: DateTime.now(),
      expiryDate: _hasExpiry ? _expiryDate : null,
      isBackedUp: _backupToCloud,
      isLent: _isLentFlow,
      lentTo: _isLentFlow ? _lentToController.text.trim() : null,
      lentOn: _isLentFlow ? _lentOnDate : null,
      expectedReturnDate: _isLentFlow ? _expectedReturnDate : null,
      visibility: ItemVisibility.private_,
    );

    String? failure;
    try {
      failure = await ref.read(itemsNotifierProvider.notifier).saveItemWithMover(
            item,
            movedByName: 'You',
          );
    } catch (e) {
      failure = 'Save failed: $e';
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }

    if (!mounted) return;

    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure), backgroundColor: AppColors.error),
      );
    } else {
      context.pop();
    }
  }

  Future<void> _handleBackupToggle(bool enabled) async {
    if (!enabled) {
      if (mounted) {
        setState(() => _backupToCloud = false);
      }
      return;
    }

    final backedUpCount = await ref.read(backedUpItemsCountProvider.future);
    if (hasReachedCloudBackupLimit(
      backedUpCount: backedUpCount,
    )) {
      if (mounted) {
        setState(() => _backupToCloud = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cloudBackupQuotaExceededError()),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    await ref.read(settingsProvider.notifier).setBackupEnabled(true);
    if (mounted) {
      setState(() => _backupToCloud = true);
    }
  }

  /// Resolves a zone UUID into a full [Zone] (with areaUuid/roomUuid populated)
  /// and stores it as the selected zone. Called after the picker returns.
  Future<void> _resolveAndSetZone(String zoneUuid) async {
    final zone = await ref
        .read(locationHierarchyRepositoryProvider)
        .resolveZone(zoneUuid);
    if (mounted) setState(() => _selectedZone = zone);
  }

  Future<void> _showAddLocationDialog() async {
    final result = await showLocationPickerSheet(
      context,
      initialSelectedLocationUuid: _selectedZone?.uuid,
      title: 'Select Location',
    );
    if (result != null && mounted) {
      await _resolveAndSetZone(result);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildBackground(),
          if (!_isCapturing) _buildCameraChrome(context),
          if (_isCapturing) _buildLoadingOverlay(),
          if (!_isCapturing)
            _buildBottomSheet(context, isDark).animate().slideY(
                begin: 1, end: 0, duration: 380.ms, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    if (_imagePath != null) {
      return Positioned.fill(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Image.file(
            File(_imagePath!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0x4D5B7CF6),
              AppColors.surfaceDark,
              Color(0x335B7CF6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return const Positioned.fill(
      child: Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }

  Widget _buildCameraChrome(BuildContext context) {
    return Positioned.fill(
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _chromeButton(icon: Icons.close, onTap: () => context.pop()),
                  _chromeButton(icon: Icons.flash_on_outlined, onTap: () {}),
                ],
              ),
            ),
            const Spacer(),
            // Focus square
            SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                children: [
                  // Outer dim border
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24, width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  // Corner brackets
                  Positioned(
                    top: 0,
                    left: 0,
                    child: CustomPaint(
                      size: const Size(18, 18),
                      painter: _BracketPainter(flipH: false, flipV: false),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: CustomPaint(
                      size: const Size(18, 18),
                      painter: _BracketPainter(flipH: true, flipV: false),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: CustomPaint(
                      size: const Size(18, 18),
                      painter: _BracketPainter(flipH: false, flipV: true),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CustomPaint(
                      size: const Size(18, 18),
                      painter: _BracketPainter(flipH: true, flipV: true),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Bottom camera controls (peeking above the sheet)
            Padding(
              padding: const EdgeInsets.only(bottom: 160),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _chromeButton(
                    icon: Icons.image_outlined,
                    onTap: _pickFromGallery,
                    size: 48,
                  ),
                  const SizedBox(width: 36),
                  // Shutter
                  GestureDetector(
                    onTap: _retakePhoto,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38, width: 4),
                      ),
                      child: Center(
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 36),
                  _chromeButton(
                      icon: Icons.cached, onTap: _retakePhoto, size: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chromeButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 44,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.45),
      ),
    );
  }

  Widget _buildBottomSheet(BuildContext context, bool isDark) {
    final mediaQuery = MediaQuery.of(context);
    final sheetBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final topSafeMargin = mediaQuery.viewPadding.top + 12;
    final preferredMaxHeight = mediaQuery.size.height * 0.74;

    return Positioned(
      top: topSafeMargin,
      left: 0,
      right: 0,
      bottom: 0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxSheetHeight = constraints.maxHeight < preferredMaxHeight
              ? constraints.maxHeight
              : preferredMaxHeight;

          return Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppDimensions.bottomSheetRadius),
                ),
                border: Border(
                  top: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 28,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusFull),
                        ),
                      ),
                    ),
                    // Form
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxSheetHeight),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(
                          left: 24,
                          right: 24,
                          top: 8,
                          bottom: mediaQuery.viewInsets.bottom + 24,
                        ),
                        child: _buildForm(isDark),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(bool isDark) {
    final textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final inputBg =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;
    final borderColor = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Save',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        const SizedBox(height: 24),

        // ── Item Name ───────────────────────────────────────────────────────
        _sectionLabel('Item Name', secondaryColor),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Enter item name...',
            hintStyle: TextStyle(color: secondaryColor),
            filled: true,
            fillColor: inputBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        if (_imagePath != null) _buildAiSuggestion(),

        const SizedBox(height: 24),

        // ── Location ────────────────────────────────────────────────────────
        _sectionLabel('Location', secondaryColor),
        const SizedBox(height: 12),
        _buildLocationChips(isDark, borderColor, textColor),

        const SizedBox(height: 24),

        // ── Tags ────────────────────────────────────────────────────────────
        _sectionLabel('Tags', secondaryColor),
        const SizedBox(height: 12),
        _buildTagChips(isDark, borderColor, textColor),

        const SizedBox(height: 20),

        _buildCloudBackupSection(
          isDark,
          textColor,
          secondaryColor,
          borderColor,
        ),

        const SizedBox(height: 20),

        // ── Expiry Date ─────────────────────────────────────────────────────
        _buildExpirySection(isDark, borderColor, textColor, secondaryColor),

        const SizedBox(height: 20),

        // ── Metadata ────────────────────────────────────────────────────────
        _buildLentSection(
            isDark, inputBg, borderColor, textColor, secondaryColor),

        const SizedBox(height: 20),

        // ── Metadata ────────────────────────────────────────────────────────
        _buildMetadataRow(secondaryColor),

        const SizedBox(height: 20),

        // ── Save button ─────────────────────────────────────────────────────
        _buildSaveButton(),
      ],
    );
  }

  Widget _sectionLabel(String text, Color color) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildAiSuggestion() {
    final labelsAsync = ref.watch(mlLabelsForImageProvider(_imagePath!));

    return labelsAsync.when(
      data: (labels) {
        if (labels.isEmpty) return const SizedBox.shrink();
        final topLabel = labels.first.label;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: GestureDetector(
            onTap: () => _applyAiSuggestion(topLabel),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppColors.primary, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    'AI Suggestion: $topLabel',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            Text(
              'Scanning...',
              style: TextStyle(
                  color: AppColors.primary.withValues(alpha: 0.7),
                  fontSize: 12),
            ),
          ],
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildLocationChips(bool isDark, Color borderColor, Color textColor) {
    final locationsAsync = ref.watch(locationsWithDerivedUsageProvider);

    return locationsAsync.when(
      data: (locations) {
        final sorted = locations
            .where((loc) => loc.isAssignableToItem)
            .toList()
          ..sort((a, b) => b.usageCount.compareTo(a.usageCount));
        final shown = sorted.take(4).toList();

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...shown.map(
                (loc) => _locationChip(loc, isDark, borderColor, textColor)),
            _addLocationButton(isDark, borderColor),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 36,
        child: Center(
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary)),
      ),
      error: (_, __) => Wrap(
        spacing: 8,
        children: [_addLocationButton(isDark, borderColor)],
      ),
    );
  }

  Widget _locationChip(
      LocationModel loc, bool isDark, Color borderColor, Color textColor) {
    final isSelected = _selectedZone?.uuid == loc.uuid;
    return GestureDetector(
      onTap: () async {
        if (isSelected) {
          setState(() => _selectedZone = null);
        } else {
          // Resolve the full hierarchy (areaUuid, roomUuid) for this zone.
          await _resolveAndSetZone(loc.uuid);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark
                  ? AppColors.surfaceVariantDark
                  : AppColors.surfaceVariantLight),
          border: Border.all(
            color: isSelected ? AppColors.primary : borderColor,
          ),
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  )
                ]
              : [],
        ),
        child: Text(
          loc.name,
          style: TextStyle(
            color: isSelected ? Colors.white : textColor,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _addLocationButton(bool isDark, Color borderColor) {
    return GestureDetector(
      onTap: _showAddLocationDialog,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? AppColors.surfaceVariantDark
                  : AppColors.surfaceVariantLight,
              border: Border.all(color: borderColor),
            ),
            child: Icon(
              Icons.add,
              size: 18,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagChips(bool isDark, Color borderColor, Color textColor) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ..._tags.map((tag) => _tagChip(tag, isDark, borderColor, textColor)),
        if (_showTagInput)
          _tagInputChip(isDark, borderColor, textColor)
        else
          _addTagButton(isDark, borderColor, textColor),
      ],
    );
  }

  Widget _tagChip(String tag, bool isDark, Color borderColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceVariantDark
            : AppColors.surfaceVariantLight,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#$tag',
            style: TextStyle(
                color: textColor, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _removeTag(tag),
            child: Icon(Icons.close,
                size: 14, color: textColor.withValues(alpha: 0.45)),
          ),
        ],
      ),
    );
  }

  Widget _tagInputChip(bool isDark, Color borderColor, Color textColor) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceVariantDark
            : AppColors.surfaceVariantLight,
        border: Border.all(color: AppColors.primary),
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      ),
      child: TextField(
        controller: _tagController,
        focusNode: _tagFocusNode,
        autofocus: true,
        style: TextStyle(color: textColor, fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Tag name',
          hintStyle:
              TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 12),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          prefix: const Text(
            '#',
            style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700),
          ),
        ),
        onSubmitted: _addTag,
      ),
    );
  }

  Widget _addTagButton(bool isDark, Color borderColor, Color textColor) {
    return GestureDetector(
      onTap: () => setState(() => _showTagInput = true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceVariantDark
              : AppColors.surfaceVariantLight,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add,
                size: 14,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight),
            const SizedBox(width: 4),
            Text(
              'Add tag',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataRow(Color color) {
    final formatted =
        DateFormat("MMM dd, yyyy '•' HH:mm").format(DateTime.now());

    return Opacity(
      opacity: 0.6,
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            formatted.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudBackupSection(
    bool isDark,
    Color textColor,
    Color secondaryColor,
    Color borderColor,
  ) {
    final backedUpCountAsync = ref.watch(backedUpItemsCountProvider);
    final backedUpCount = backedUpCountAsync.valueOrNull ?? 0;
    final progress = cloudBackupUsageProgress(
      backedUpCount: backedUpCount,
    );
    final progressColor = backedUpCount >= cloudBackupWarningThreshold
        ? AppColors.warning
        : AppColors.primary;
    final helperText = _backupToCloud
        ? 'Cloud-backed items can later be shared with family members from the item details screen.'
        : 'Keep this off if the item should stay only on this device. Family sharing stays unavailable while backup is off.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceVariantDark
            : AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backup to Cloud',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cloudBackupUsageLabel(
                        backedUpCount: backedUpCount,
                      ),
                      style: TextStyle(color: secondaryColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _backupToCloud,
                activeThumbColor: AppColors.primary,
                onChanged: _handleBackupToggle,
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: backedUpCountAsync.isLoading ? null : progress,
            minHeight: 8,
            backgroundColor: borderColor.withValues(alpha: 0.4),
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          ),
          const SizedBox(height: 10),
          Text(
            helperText,
            style: TextStyle(
              color: secondaryColor,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpirySection(
    bool isDark,
    Color borderColor,
    Color textColor,
    Color secondaryColor,
  ) {
    // Quick-preset durations covering food, medicine, household items
    const presets = <(String label, int days)>[
      ('1 week', 7),
      ('1 month', 30),
      ('3 months', 90),
      ('6 months', 180),
      ('1 year', 365),
      ('2 years', 730),
    ];

    String? expiryLabel;
    if (_expiryDate != null) {
      final diff = _expiryDate!.difference(DateTime.now()).inDays;
      if (diff < 0) {
        expiryLabel = 'Expired ${-diff}d ago';
      } else if (diff == 0) {
        expiryLabel = 'Expires today';
      } else {
        expiryLabel = DateFormat('dd MMM yyyy').format(_expiryDate!);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Expires', secondaryColor),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                _hasExpiry
                    ? (expiryLabel ?? 'Pick a date below')
                    : 'Set an expiry for food, medicine, etc.',
                style: TextStyle(
                  color: _hasExpiry && _expiryDate != null
                      ? textColor
                      : secondaryColor,
                  fontSize: 12,
                  fontWeight: _hasExpiry && _expiryDate != null
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ),
            Switch(
              value: _hasExpiry,
              activeThumbColor: AppColors.primary,
              onChanged: (value) {
                setState(() {
                  _hasExpiry = value;
                  if (!value) _expiryDate = null;
                });
              },
            ),
          ],
        ),
        if (_hasExpiry) ...[
          const SizedBox(height: 10),
          // Quick presets
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...presets.map((preset) {
                final target = DateTime.now().add(Duration(days: preset.$2));
                final targetDay =
                    DateTime(target.year, target.month, target.day);
                final isSelected = _expiryDate != null &&
                    _expiryDate!.year == targetDay.year &&
                    _expiryDate!.month == targetDay.month &&
                    _expiryDate!.day == targetDay.day;

                return GestureDetector(
                  onTap: () => setState(() => _expiryDate = targetDay),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusFull),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : borderColor,
                      ),
                    ),
                    child: Text(
                      preset.$1,
                      style: TextStyle(
                        color: isSelected ? Colors.white : textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }),
              // Custom date button
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _expiryDate ??
                        DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                    helpText: 'SELECT EXPIRY DATE',
                  );
                  if (picked != null) {
                    setState(() => _expiryDate = picked);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusFull),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month,
                          size: 14, color: secondaryColor),
                      const SizedBox(width: 6),
                      Text(
                        'Pick date',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_expiryDate != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, color: AppColors.warning, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Expires ${DateFormat('dd MMM yyyy').format(_expiryDate!)}  ·  '
                      "You'll be notified on the day",
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _expiryDate = null),
                    child: Icon(Icons.close, size: 16, color: secondaryColor),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildLentSection(
    bool isDark,
    Color inputBg,
    Color borderColor,
    Color textColor,
    Color secondaryColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('I Lent It', secondaryColor),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                _isLentFlow
                    ? 'Track who has it + auto-remind me'
                    : 'Turn on to log borrowed-away items',
                style: TextStyle(color: secondaryColor, fontSize: 12),
              ),
            ),
            Switch(
              value: _isLentFlow,
              activeThumbColor: AppColors.primary,
              onChanged: (value) => setState(() => _isLentFlow = value),
            ),
          ],
        ),
        if (_isLentFlow) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _lentToController,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Lent to (name)',
              hintStyle: TextStyle(color: secondaryColor),
              filled: true,
              fillColor: inputBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await _pickDate(_lentOnDate);
                    if (picked == null) return;
                    setState(() => _lentOnDate = picked);
                  },
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label:
                      Text('Lent: ${DateFormat('dd MMM').format(_lentOnDate)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await _pickDate(
                      _expectedReturnDate ?? _lentOnDate,
                    );
                    if (picked == null) return;
                    setState(() => _expectedReturnDate = picked);
                  },
                  icon: const Icon(Icons.event_available, size: 16),
                  label: Text(
                    _expectedReturnDate == null
                        ? 'Expected return'
                        : DateFormat('dd MMM').format(_expectedReturnDate!),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<DateTime?> _pickDate(DateTime initial) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    return picked;
  }

  Widget _buildSaveButton() {
    final canSave = _nameController.text.trim().isNotEmpty && !_isSaving;

    return SizedBox(
      width: double.infinity,
      child: AnimatedOpacity(
        opacity: canSave ? 1.0 : 0.55,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: BoxDecoration(
            gradient: canSave ? AppColors.primaryGradient : null,
            color: canSave ? null : AppColors.primary.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
            boxShadow: canSave
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: AppColors.secondary.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(4, 8),
                    ),
                  ]
                : null,
          ),
          child: ElevatedButton(
            onPressed: canSave ? _saveEntry : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.transparent,
              disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
              padding: const EdgeInsets.symmetric(vertical: 17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
              ),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Save Entry',
                        style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Corner bracket painter ─────────────────────────────────────────────────

class _BracketPainter extends CustomPainter {
  final bool flipH;
  final bool flipV;

  const _BracketPainter({required this.flipH, required this.flipV});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.save();
    if (flipH || flipV) {
      canvas.translate(
        flipH ? size.width : 0,
        flipV ? size.height : 0,
      );
      canvas.scale(flipH ? -1 : 1, flipV ? -1 : 1);
    }

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0);

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BracketPainter old) =>
      old.flipH != flipH || old.flipV != flipV;
}
