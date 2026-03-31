import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/feature_limits.dart';
import '../providers/quick_add_zone_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

enum _QuickAddPhotoSource { camera, gallery }

class QuickAddItemCard extends ConsumerStatefulWidget {
  const QuickAddItemCard({
    super.key,
    required this.zoneUuid,
    required this.row,
    required this.itemNumber,
    required this.canRemove,
    required this.showValidationError,
  });

  final String zoneUuid;
  final QuickAddItemDraft row;
  final int itemNumber;
  final bool canRemove;
  final bool showValidationError;

  @override
  ConsumerState<QuickAddItemCard> createState() => _QuickAddItemCardState();
}

class _QuickAddItemCardState extends ConsumerState<QuickAddItemCard> {
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.row.name);
    _notesController = TextEditingController(text: widget.row.notes);
    _tagsController = TextEditingController(text: widget.row.tagsText);
  }

  @override
  void didUpdateWidget(covariant QuickAddItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_nameController, widget.row.name);
    _syncController(_notesController, widget.row.notes);
    _syncController(_tagsController, widget.row.tagsText);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final borderColor = widget.showValidationError
        ? AppColors.error.withValues(alpha: 0.60)
        : AppColors.primary.withValues(alpha: isDark ? 0.24 : 0.12);
    final backgroundColor =
        isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final detailBackground = isDark
        ? AppColors.surfaceVariantDark.withValues(alpha: 0.88)
        : AppColors.primary.withValues(alpha: 0.11);
    final controller =
        ref.read(zoneQuickAddControllerProvider(widget.zoneUuid).notifier);
    final isSaving = ref.watch(
      zoneQuickAddControllerProvider(widget.zoneUuid)
          .select((state) => state.isSaving),
    );
    final row = widget.row;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacingSm,
                  vertical: AppDimensions.spacingXs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                ),
                child: Text(
                  'Item ${widget.itemNumber}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: !widget.canRemove || isSaving
                    ? null
                    : () => controller.removeRow(row.id),
                tooltip: 'Remove row',
                icon: Icon(
                  Icons.delete_outline,
                  color: textSecondary,
                ),
              ),
            ],
          ),
          TextField(
            controller: _nameController,
            enabled: !isSaving,
            textCapitalization: TextCapitalization.words,
            onChanged: (value) => controller.updateName(row.id, value),
            decoration: InputDecoration(
              hintText: 'Item name',
              hintStyle: TextStyle(
                color: textSecondary,
                fontWeight: FontWeight.w500,
              ),
              filled: true,
              fillColor: detailBackground,
              errorText: widget.showValidationError
                  ? 'A name is required for this row.'
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spacingMd,
                vertical: AppDimensions.spacingMd,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                borderSide: BorderSide(
                  color:
                      AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.06),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                borderSide: BorderSide(
                  color:
                      AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.06),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          if (!row.isExpanded && row.optionalSummary != null) ...[
            const SizedBox(height: AppDimensions.spacingSm),
            Text(
              row.optionalSummary!,
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: AppDimensions.spacingSm),
          Row(
            children: [
              InkWell(
                onTap:
                    isSaving ? null : () => controller.toggleExpanded(row.id),
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingXs,
                    vertical: AppDimensions.spacingXs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        row.isExpanded
                            ? Icons.remove_circle_outline_rounded
                            : Icons.add_circle_outline_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppDimensions.spacingXs),
                      Text(
                        row.isExpanded ? 'Hide details' : 'Add details',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 18 / 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (row.imagePaths.isNotEmpty || row.hasInvoice) ...[
                const SizedBox(width: AppDimensions.spacingSm),
                Text(
                  '${row.imagePaths.length}/$itemPhotoLimit photos'
                  '${row.hasInvoice ? '  |  document attached' : ''}',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          if (row.isExpanded) ...[
            const SizedBox(height: AppDimensions.spacingSm),
            TextField(
              controller: _notesController,
              enabled: !isSaving,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 3,
              onChanged: (value) => controller.updateNotes(row.id, value),
              decoration: InputDecoration(
                labelText: 'Note',
                hintText: 'Optional description or reminder',
                filled: true,
                fillColor: detailBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            TextField(
              controller: _tagsController,
              enabled: !isSaving,
              textCapitalization: TextCapitalization.words,
              onChanged: (value) => controller.updateTags(row.id, value),
              decoration: InputDecoration(
                labelText: 'Tags',
                hintText: 'makeup, travel, red',
                helperText: 'Separate tags with commas',
                filled: true,
                fillColor: detailBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            _SectionLabel(
              label: 'Photos',
              trailing: '${row.imagePaths.length} / $itemPhotoLimit',
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            Wrap(
              spacing: AppDimensions.spacingSm,
              runSpacing: AppDimensions.spacingSm,
              children: [
                _ActionChip(
                  icon: Icons.photo_camera_outlined,
                  label: 'Camera',
                  isDisabled:
                      isSaving || row.imagePaths.length >= itemPhotoLimit,
                  onTap: () => _handlePhotoAdd(_QuickAddPhotoSource.camera),
                ),
                _ActionChip(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  isDisabled:
                      isSaving || row.imagePaths.length >= itemPhotoLimit,
                  onTap: () => _handlePhotoAdd(_QuickAddPhotoSource.gallery),
                ),
                ...row.imagePaths.map(
                  (path) => _DraftImageTile(
                    path: path,
                    isSaving: isSaving,
                    onRemove: () => controller.removeImage(row.id, path),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            _SectionLabel(label: 'Document'),
            const SizedBox(height: AppDimensions.spacingSm),
            if (!row.hasInvoice)
              _ActionChip(
                icon: Icons.attach_file_rounded,
                label: 'Attach invoice or document',
                isDisabled: isSaving,
                onTap: _handleInvoiceAttach,
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacingMd,
                  vertical: AppDimensions.spacingSm,
                ),
                decoration: BoxDecoration(
                  color: detailBackground,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppDimensions.spacingSm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.invoiceFileName?.trim().isNotEmpty == true
                                ? row.invoiceFileName!.trim()
                                : 'Attached document',
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (row.invoiceFileSizeBytes != null)
                            Text(
                              _formatFileSize(row.invoiceFileSizeBytes!),
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: isSaving
                          ? null
                          : () => controller.removeInvoice(row.id),
                      tooltip: 'Remove document',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _handlePhotoAdd(_QuickAddPhotoSource source) async {
    final controller =
        ref.read(zoneQuickAddControllerProvider(widget.zoneUuid).notifier);
    final message = switch (source) {
      _QuickAddPhotoSource.camera => await controller.addImageFromCamera(
          widget.row.id,
        ),
      _QuickAddPhotoSource.gallery => await controller.addImageFromGallery(
          widget.row.id,
        ),
    };
    _showMessage(message);
  }

  Future<void> _handleInvoiceAttach() async {
    final controller =
        ref.read(zoneQuickAddControllerProvider(widget.zoneUuid).notifier);
    final message = await controller.attachInvoice(widget.row.id);
    _showMessage(message);
  }

  void _showMessage(String? message) {
    if (!mounted || message == null || message.trim().isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _syncController(TextEditingController controller, String nextValue) {
    if (controller.text == nextValue) return;
    controller.value = controller.value.copyWith(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
      composing: TextRange.empty,
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    this.trailing,
  });

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              color: textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDisabled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: isDisabled ? null : onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingSm,
          vertical: AppDimensions.spacingSm,
        ),
        decoration: BoxDecoration(
          color: isDisabled
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03))
              : AppColors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          border: Border.all(
            color: isDisabled
                ? (isDark ? AppColors.borderDark : AppColors.borderLight)
                : AppColors.primary.withValues(alpha: 0.24),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isDisabled
                  ? (isDark
                      ? AppColors.textDisabledDark
                      : AppColors.textDisabledLight)
                  : AppColors.primary,
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            Text(
              label,
              style: TextStyle(
                color: isDisabled
                    ? (isDark
                        ? AppColors.textDisabledDark
                        : AppColors.textDisabledLight)
                    : AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftImageTile extends StatelessWidget {
  const _DraftImageTile({
    required this.path,
    required this.isSaving,
    required this.onRemove,
  });

  final String path;
  final bool isSaving;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isNetworkImage = path.startsWith('http');

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: SizedBox(
            width: 72,
            height: 72,
            child: isNetworkImage
                ? Image.network(path, fit: BoxFit.cover)
                : Image.file(File(path), fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isSaving ? null : onRemove,
              customBorder: const CircleBorder(),
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
