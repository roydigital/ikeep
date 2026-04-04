import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/feature_limits.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/path_utils.dart';
import '../core/utils/uuid_generator.dart';
import '../domain/models/item.dart';
import '../domain/models/item_visibility.dart';
import '../domain/models/zone.dart';
import '../providers/item_providers.dart';
import '../providers/settings_provider.dart';
import '../services/invoice_service.dart';
import 'service_providers.dart';

class QuickAddItemDraft {
  const QuickAddItemDraft({
    required this.id,
    this.name = '',
    this.notes = '',
    this.tagsText = '',
    this.imagePaths = const [],
    this.invoicePath,
    this.invoiceFileName,
    this.invoiceFileSizeBytes,
    this.isExpanded = false,
  });

  factory QuickAddItemDraft.empty() {
    return QuickAddItemDraft(id: generateUuid());
  }

  final String id;
  final String name;
  final String notes;
  final String tagsText;
  final List<String> imagePaths;
  final String? invoicePath;
  final String? invoiceFileName;
  final int? invoiceFileSizeBytes;
  final bool isExpanded;

  String get trimmedName => name.trim();
  String get trimmedNotes => notes.trim();
  String get trimmedTagsText => tagsText.trim();
  bool get hasInvoice => invoicePath?.trim().isNotEmpty ?? false;
  bool get hasAttachments => imagePaths.isNotEmpty || hasInvoice;
  bool get hasExtraDetails =>
      trimmedNotes.isNotEmpty || parsedTags.isNotEmpty || hasAttachments;
  bool get isBlank => trimmedName.isEmpty && !hasExtraDetails;

  List<String> get parsedTags {
    final values = tagsText
        .split(RegExp(r'[,;\n]'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return values;
  }

  String? get optionalSummary {
    final parts = <String>[
      if (trimmedNotes.isNotEmpty) 'Note',
      if (parsedTags.isNotEmpty)
        '${parsedTags.length} tag${parsedTags.length == 1 ? '' : 's'}',
      if (imagePaths.isNotEmpty)
        '${imagePaths.length} photo${imagePaths.length == 1 ? '' : 's'}',
      if (hasInvoice) 'Document',
    ];
    if (parts.isEmpty) return null;
    return parts.join(' | ');
  }

  QuickAddItemDraft copyWith({
    String? name,
    String? notes,
    String? tagsText,
    List<String>? imagePaths,
    String? invoicePath,
    String? invoiceFileName,
    int? invoiceFileSizeBytes,
    bool? isExpanded,
    bool clearInvoicePath = false,
    bool clearInvoiceFileName = false,
    bool clearInvoiceFileSizeBytes = false,
  }) {
    return QuickAddItemDraft(
      id: id,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      tagsText: tagsText ?? this.tagsText,
      imagePaths: imagePaths ?? this.imagePaths,
      invoicePath: clearInvoicePath ? null : (invoicePath ?? this.invoicePath),
      invoiceFileName: clearInvoiceFileName
          ? null
          : (invoiceFileName ?? this.invoiceFileName),
      invoiceFileSizeBytes: clearInvoiceFileSizeBytes
          ? null
          : (invoiceFileSizeBytes ?? this.invoiceFileSizeBytes),
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }
}

class ZoneQuickAddState {
  const ZoneQuickAddState({
    required this.rows,
    required this.backupToCloud,
    this.isSaving = false,
    this.invalidRowIds = const <String>{},
  });

  factory ZoneQuickAddState.initial({
    required bool backupToCloud,
  }) {
    return ZoneQuickAddState(
      rows: [QuickAddItemDraft.empty()],
      backupToCloud: backupToCloud,
    );
  }

  final List<QuickAddItemDraft> rows;
  final bool backupToCloud;
  final bool isSaving;
  final Set<String> invalidRowIds;

  bool get hasUnsavedChanges => rows.any((row) => !row.isBlank);
  int get savableRowCount =>
      rows.where((row) => row.trimmedName.isNotEmpty).length;
  int get blankRowCount => rows.where((row) => row.isBlank).length;

  QuickAddItemDraft? rowById(String rowId) {
    for (final row in rows) {
      if (row.id == rowId) return row;
    }
    return null;
  }

  ZoneQuickAddState copyWith({
    List<QuickAddItemDraft>? rows,
    bool? backupToCloud,
    bool? isSaving,
    Set<String>? invalidRowIds,
  }) {
    return ZoneQuickAddState(
      rows: rows ?? this.rows,
      backupToCloud: backupToCloud ?? this.backupToCloud,
      isSaving: isSaving ?? this.isSaving,
      invalidRowIds: invalidRowIds ?? this.invalidRowIds,
    );
  }
}

class QuickAddSaveOutcome {
  const QuickAddSaveOutcome({
    required this.savedCount,
    required this.ignoredBlankCount,
    this.invalidRowIds = const <String>{},
    this.errorMessage,
  });

  final int savedCount;
  final int ignoredBlankCount;
  final Set<String> invalidRowIds;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
  bool get hasValidationErrors => invalidRowIds.isNotEmpty;
}

class ZoneQuickAddController extends StateNotifier<ZoneQuickAddState> {
  ZoneQuickAddController(this._ref, this.zoneUuid)
      : super(
          ZoneQuickAddState.initial(
            backupToCloud: _ref.read(settingsProvider).isBackupEnabled,
          ),
        );

  final Ref _ref;
  final String zoneUuid;

  void addRow() {
    state = state.copyWith(
      rows: [...state.rows, QuickAddItemDraft.empty()],
    );
  }

  Future<void> removeRow(String rowId) async {
    final row = state.rowById(rowId);
    if (row == null) return;

    await _cleanupRowMedia(row);

    final remainingRows = state.rows.where((entry) => entry.id != rowId).toList();
    final nextRows = remainingRows.isEmpty
        ? [QuickAddItemDraft.empty()]
        : remainingRows;
    final invalidRowIds = {...state.invalidRowIds}..remove(rowId);
    state = state.copyWith(
      rows: nextRows,
      invalidRowIds: invalidRowIds,
    );
  }

  void updateName(String rowId, String value) {
    _updateRow(
      rowId,
      (row) => row.copyWith(name: value),
    );
  }

  void updateNotes(String rowId, String value) {
    _updateRow(
      rowId,
      (row) => row.copyWith(notes: value),
    );
  }

  void updateTags(String rowId, String value) {
    _updateRow(
      rowId,
      (row) => row.copyWith(tagsText: value),
    );
  }

  void toggleExpanded(String rowId) {
    _updateRow(
      rowId,
      (row) => row.copyWith(isExpanded: !row.isExpanded),
      clearValidation: false,
    );
  }

  Future<String?> setBackupToCloud(bool enabled) async {
    if (!enabled) {
      state = state.copyWith(backupToCloud: false);
      return null;
    }

    final backedUpCount = await _ref.read(backedUpItemsCountProvider.future);
    if (hasReachedCloudBackupLimit(backedUpCount: backedUpCount)) {
      state = state.copyWith(backupToCloud: false);
      return cloudBackupQuotaExceededError();
    }

    await _ref.read(settingsProvider.notifier).setBackupEnabled(true);
    state = state.copyWith(backupToCloud: true);
    return null;
  }

  Future<String?> addImageFromCamera(String rowId) async {
    return _addImage(
      rowId,
      () => _ref.read(imageServiceProvider).pickFromCamera(),
    );
  }

  Future<String?> addImageFromGallery(String rowId) async {
    return _addImage(
      rowId,
      () => _ref.read(imageServiceProvider).pickFromGallery(),
    );
  }

  Future<void> removeImage(String rowId, String imagePath) async {
    final row = state.rowById(rowId);
    if (row == null) return;

    final nextImages = [...row.imagePaths]..remove(imagePath);
    _updateRow(
      rowId,
      (entry) => entry.copyWith(imagePaths: nextImages),
    );

    if (_isSafeLocalImagePath(imagePath)) {
      await _ref.read(imageServiceProvider).deleteImage(imagePath);
    }
  }

  Future<String?> attachInvoice(String rowId) async {
    final row = state.rowById(rowId);
    if (row == null) return 'This row is no longer available.';

    try {
      final picked = await _ref.read(invoiceServiceProvider).pickInvoice();
      if (picked == null) {
        return null;
      }

      final previousInvoicePath = row.invoicePath;
      _updateRow(
        rowId,
        (_) => row.copyWith(
          invoicePath: picked.path,
          invoiceFileName: picked.fileName,
          invoiceFileSizeBytes: picked.sizeBytes,
          isExpanded: true,
        ),
      );

      if (InvoiceService.isSafeLocalInvoicePath(previousInvoicePath)) {
        await _ref.read(invoiceServiceProvider).deleteInvoice(previousInvoicePath!);
      }
      return null;
    } on InvoiceTooLargeException catch (error) {
      return error.message;
    } catch (error) {
      return _errorMessage(
        error,
        fallback: 'Could not attach this document.',
      );
    }
  }

  Future<void> removeInvoice(String rowId) async {
    final row = state.rowById(rowId);
    if (row == null || !row.hasInvoice) return;

    final previousInvoicePath = row.invoicePath;
    _updateRow(
      rowId,
      (entry) => entry.copyWith(
        clearInvoicePath: true,
        clearInvoiceFileName: true,
        clearInvoiceFileSizeBytes: true,
      ),
    );

    if (InvoiceService.isSafeLocalInvoicePath(previousInvoicePath)) {
      await _ref.read(invoiceServiceProvider).deleteInvoice(previousInvoicePath!);
    }
  }

  Future<void> discardDraft() async {
    await _cleanupRowsMedia(state.rows);
    state = ZoneQuickAddState.initial(backupToCloud: state.backupToCloud);
  }

  Future<QuickAddSaveOutcome> saveAll(Zone zone) async {
    if (state.isSaving) {
      return const QuickAddSaveOutcome(savedCount: 0, ignoredBlankCount: 0);
    }
    final invalidRowIds = _findInvalidRowIds(state.rows);
    if (invalidRowIds.isNotEmpty) {
      state = state.copyWith(invalidRowIds: invalidRowIds);
      return QuickAddSaveOutcome(
        savedCount: 0,
        ignoredBlankCount: state.blankRowCount,
        invalidRowIds: invalidRowIds,
        errorMessage: 'Add a name for rows that already have details attached.',
      );
    }

    final rowsToSave =
        state.rows.where((row) => row.trimmedName.isNotEmpty).toList(growable: false);
    if (rowsToSave.isEmpty) {
      return const QuickAddSaveOutcome(
        savedCount: 0,
        ignoredBlankCount: 0,
        errorMessage: 'Add at least one item name to save.',
      );
    }

    state = state.copyWith(isSaving: true, invalidRowIds: <String>{});

    final items = rowsToSave.map((row) {
      final now = DateTime.now();
      return Item(
        uuid: generateUuid(),
        name: row.trimmedName,
        notes: row.trimmedNotes.isEmpty ? null : row.trimmedNotes,
        tags: row.parsedTags,
        imagePaths: row.imagePaths,
        invoicePath: row.invoicePath,
        invoiceFileName: row.invoiceFileName,
        invoiceFileSizeBytes: row.invoiceFileSizeBytes,
        savedAt: now,
        updatedAt: now,
        locationUuid: zone.uuid,
        areaUuid: zone.areaUuid,
        roomUuid: zone.roomUuid,
        zoneUuid: zone.uuid,
        isBackedUp: state.backupToCloud,
        visibility: ItemVisibility.private_,
      );
    }).toList(growable: false);

    final saveResult =
        await _ref.read(itemsNotifierProvider.notifier).saveItemsBatchWithMover(
              items,
              movedByName: 'You',
            );

    state = state.copyWith(isSaving: false);

    if (saveResult.hasFailure) {
      return QuickAddSaveOutcome(
        savedCount: 0,
        ignoredBlankCount: state.blankRowCount,
        errorMessage: saveResult.failureMessage,
      );
    }

    final ignoredBlankCount = state.blankRowCount;
    state = ZoneQuickAddState.initial(backupToCloud: state.backupToCloud);
    return QuickAddSaveOutcome(
      savedCount: saveResult.savedItems.length,
      ignoredBlankCount: ignoredBlankCount,
    );
  }

  Set<String> _findInvalidRowIds(List<QuickAddItemDraft> rows) {
    return rows
        .where((row) => row.trimmedName.isEmpty && row.hasExtraDetails)
        .map((row) => row.id)
        .toSet();
  }

  Future<String?> _addImage(
    String rowId,
    Future<String> Function() picker,
  ) async {
    final row = state.rowById(rowId);
    if (row == null) return 'This row is no longer available.';
    if (row.imagePaths.length >= itemPhotoLimit) {
      return 'You can add up to $itemPhotoLimit photos per item.';
    }

    try {
      final path = await picker();
      if (path.trim().isEmpty) return null;
      final refreshedRow = state.rowById(rowId);
      if (refreshedRow == null) return null;
      _updateRow(
        rowId,
        (_) => refreshedRow.copyWith(
          imagePaths: [...refreshedRow.imagePaths, path],
          isExpanded: true,
        ),
      );
      return null;
    } catch (error) {
      return _errorMessage(
        error,
        fallback: 'Could not add this photo.',
      );
    }
  }

  void _updateRow(
    String rowId,
    QuickAddItemDraft Function(QuickAddItemDraft row) update, {
    bool clearValidation = true,
  }) {
    final nextRows = state.rows.map((row) {
      if (row.id != rowId) {
        return row;
      }
      return update(row);
    }).toList(growable: false);
    final invalidRowIds = {...state.invalidRowIds};
    if (clearValidation) {
      invalidRowIds.remove(rowId);
    }
    state = state.copyWith(
      rows: nextRows,
      invalidRowIds: invalidRowIds,
    );
  }

  Future<void> _cleanupRowsMedia(Iterable<QuickAddItemDraft> rows) async {
    for (final row in rows) {
      await _cleanupRowMedia(row);
    }
  }

  Future<void> _cleanupRowMedia(QuickAddItemDraft row) async {
    final imageService = _ref.read(imageServiceProvider);
    final invoiceService = _ref.read(invoiceServiceProvider);

    final localImagePaths = row.imagePaths.where(_isSafeLocalImagePath).toList();
    if (localImagePaths.isNotEmpty) {
      await imageService.deleteImages(localImagePaths);
    }

    final invoicePath = row.invoicePath;
    if (InvoiceService.isSafeLocalInvoicePath(invoicePath)) {
      await invoiceService.deleteInvoice(invoicePath!);
    }
  }

  bool _isSafeLocalImagePath(String path) {
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) return false;
    if (PathUtils.isRemotePath(trimmedPath)) return false;
    return !trimmedPath.toLowerCase().startsWith('gs://');
  }

  String? _errorMessage(
    Object error, {
    required String fallback,
  }) {
    if (error is ImageException &&
        error.message.toLowerCase().startsWith('no image')) {
      return null;
    }
    if (error is AppException) {
      return error.message;
    }
    return fallback;
  }
}

final zoneQuickAddControllerProvider = StateNotifierProvider.autoDispose
    .family<ZoneQuickAddController, ZoneQuickAddState, String>(
  (ref, zoneUuid) => ZoneQuickAddController(ref, zoneUuid),
);
