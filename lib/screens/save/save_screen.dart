import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/uuid_generator.dart';
import '../../domain/models/item.dart';
import '../../domain/models/location_model.dart';
import '../../providers/item_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/ml_label_providers.dart';
import '../../providers/service_providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';

class SaveScreen extends ConsumerStatefulWidget {
  const SaveScreen({super.key});

  @override
  ConsumerState<SaveScreen> createState() => _SaveScreenState();
}

class _SaveScreenState extends ConsumerState<SaveScreen> {
  String? _imagePath;
  bool _isCapturing = true;
  final _nameController = TextEditingController();
  String? _selectedLocationUuid;
  final List<String> _tags = [];
  bool _isSaving = false;
  bool _showTagInput = false;
  final _tagController = TextEditingController();
  final _tagFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capturePhoto());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    _tagFocusNode.dispose();
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
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _isSaving = true);

    final item = Item(
      uuid: generateUuid(),
      name: name,
      locationUuid: _selectedLocationUuid,
      imagePaths: _imagePath != null ? [_imagePath!] : [],
      tags: _tags,
      savedAt: DateTime.now(),
    );

    final error = await ref.read(itemsNotifierProvider.notifier).saveItem(item);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    } else {
      context.pop();
    }
  }

  Future<void> _showAddLocationDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        ),
        title: Text(
          'New Location',
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
            hintText: 'e.g. Kitchen Drawer',
            hintStyle: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
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
                  color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final location = LocationModel(
        uuid: generateUuid(),
        name: result,
        createdAt: DateTime.now(),
      );
      final error = await ref
          .read(locationsNotifierProvider.notifier)
          .saveLocation(location);
      if (error == null && mounted) {
        setState(() => _selectedLocationUuid = location.uuid);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
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
    final sheetBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppDimensions.bottomSheetRadius),
          ),
          border: Border(
            top: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
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
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.74,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 8,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: _buildForm(isDark),
                ),
              ),
            ],
          ),
        ),
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
            fontSize: 20,
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
    final locationsAsync = ref.watch(allLocationsProvider);

    return locationsAsync.when(
      data: (locations) {
        final sorted = [...locations]
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
    final isSelected = _selectedLocationUuid == loc.uuid;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedLocationUuid = isSelected ? null : loc.uuid;
      }),
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

  Widget _buildSaveButton() {
    final canSave = _nameController.text.trim().isNotEmpty && !_isSaving;

    return SizedBox(
      width: double.infinity,
      child: AnimatedOpacity(
        opacity: canSave ? 1.0 : 0.55,
        duration: const Duration(milliseconds: 200),
        child: ElevatedButton(
          onPressed: canSave ? _saveEntry : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(vertical: 17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
            elevation: 8,
            shadowColor: AppColors.primary.withValues(alpha: 0.4),
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
                    Text(
                      'Save Entry',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, size: 20),
                  ],
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
