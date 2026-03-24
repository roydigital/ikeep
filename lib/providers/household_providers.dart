import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/firestore_borrow_request.dart';
import '../domain/models/household.dart';
import '../domain/models/household_member.dart';
import '../domain/models/household_member_lookup_state.dart';
import '../domain/models/item.dart';
import '../domain/models/item_visibility.dart';
import '../domain/models/shared_item.dart';
import '../domain/models/sync_status.dart';
import 'auth_providers.dart';
import 'history_providers.dart';
import 'item_providers.dart';
import 'repository_providers.dart';
import 'service_providers.dart';
import 'sync_providers.dart';

/// Household aggregate for the current signed-in user.
final currentHouseholdProvider = FutureProvider<Household?>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return null;
  return ref.watch(householdRepositoryProvider).getCurrentHousehold();
});

final currentHouseholdIdProvider = FutureProvider<String?>((ref) async {
  final household = await ref.watch(currentHouseholdProvider.future);
  return household?.householdId;
});

final householdMembersProvider =
    FutureProvider<List<HouseholdMember>>((ref) async {
  final household = await ref.watch(currentHouseholdProvider.future);
  if (household == null) return const [];
  return ref.watch(householdRepositoryProvider).getAllMembers();
});

/// Starts the household Firestore listeners when the user belongs to a household.
final householdSyncBootstrapProvider = FutureProvider<SyncResult>((ref) async {
  final householdId = await ref.watch(currentHouseholdIdProvider.future);
  final syncService = ref.watch(householdSyncServiceProvider);
  if (householdId == null || householdId.isEmpty) {
    await syncService.stopSync();
    return const SyncResult.idle();
  }
  return syncService.startSync(householdId);
});

final householdLocalChangesProvider = StreamProvider<void>((ref) {
  ref.watch(householdSyncBootstrapProvider);
  return ref.watch(householdSyncServiceProvider).localChanges;
});

/// SQLite remains the source of truth for the UI; this stream simply re-reads
/// local shared items whenever the sync layer reports a local upsert/delete.
///
/// A 500 ms debounce coalesces rapid-fire sync writes (e.g. bulk import of 50
/// shared items) into a single SQLite query instead of one per write.
final householdSharedItemsProvider =
    StreamProvider<List<SharedItem>>((ref) async* {
  final householdId = await ref.watch(currentHouseholdIdProvider.future);
  if (householdId == null || householdId.isEmpty) {
    yield const [];
    return;
  }

  final itemRepository = ref.watch(itemRepositoryProvider);
  final currentUserId = ref.read(authStateProvider).valueOrNull?.uid;

  // Initial read.
  yield _toSharedItems(
    await itemRepository.getSharedItems(householdId: householdId),
    currentUserId: currentUserId,
  );

  // Debounced change listener — coalesces bursts of local-change events.
  final controller = StreamController<void>();
  Timer? debounce;
  final sub = ref.watch(householdSyncServiceProvider).localChanges.listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), () {
      if (!controller.isClosed) controller.add(null);
    });
  });
  ref.onDispose(() {
    debounce?.cancel();
    sub.cancel();
    controller.close();
  });

  await for (final _ in controller.stream) {
    yield _toSharedItems(
      await itemRepository.getSharedItems(householdId: householdId),
      currentUserId: currentUserId,
    );
  }
});

/// Convenience state for settings/profile UI.
final hasHouseholdProvider = Provider<bool>((ref) {
  return ref.watch(currentHouseholdProvider).valueOrNull != null;
});

/// Placeholder borrow request providers retained for compatibility.
final incomingBorrowRequestsProvider =
    FutureProvider<List<FirestoreBorrowRequest>>((ref) async => const []);
final outgoingBorrowRequestsProvider =
    FutureProvider<List<FirestoreBorrowRequest>>((ref) async => const []);
final borrowRequestsForItemProvider = FutureProvider.family<
    List<FirestoreBorrowRequest>, String>((ref, itemUuid) async => const []);
final pendingIncomingCountProvider = Provider<int>((ref) => 0);

List<SharedItem> _toSharedItems(
  List<Item> items, {
  String? currentUserId,
}) {
  return items
      .map(
        (item) => SharedItem(
          itemUuid: item.uuid,
          ownerUid: item.cloudId ?? '',
          ownerName:
              item.cloudId == currentUserId ? 'You' : 'Household member',
          name: item.name,
          locationName: item.locationName ?? item.locationFullPath ?? '',
          tags: item.tags,
          isLent: item.isLent,
          lentToName: item.lentTo,
          expectedReturnDate: item.expectedReturnDate,
          updatedAt: item.updatedAt,
        ),
      )
      .toList();
}

class HouseholdActionState {
  const HouseholdActionState({
    this.isLoading = false,
    this.lastError,
  });

  final bool isLoading;
  final String? lastError;

  HouseholdActionState copyWith({
    bool? isLoading,
    String? lastError,
    bool clearError = false,
  }) {
    return HouseholdActionState(
      isLoading: isLoading ?? this.isLoading,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class HouseholdNotifier extends StateNotifier<HouseholdActionState> {
  static const String _backupRequiredMessage =
      'Turn on Backup to Cloud before sharing this item with family. '
      'Device-only items stay private on this device.';

  HouseholdNotifier(this._ref) : super(const HouseholdActionState());

  final Ref _ref;

  Future<String?> createHousehold({required String name}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final failure =
          await _ref.read(householdRepositoryProvider).createHousehold(name: name);
      if (failure != null) {
        state = state.copyWith(isLoading: false, lastError: failure.message);
        return failure.message;
      }

      await _refreshHouseholdState();
      state = state.copyWith(isLoading: false, clearError: true);
      return null;
    } catch (e) {
      final message = 'Failed to create household: $e';
      state = state.copyWith(isLoading: false, lastError: message);
      return message;
    }
  }

  Future<String?> addMember({
    required String userId,
    String? name,
    String? email,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final householdId = await _requireHouseholdId();
      final failure = await _ref.read(householdRepositoryProvider).addMember(
            householdId: householdId,
            userId: userId,
            name: name,
            email: email,
          );
      if (failure != null) {
        state = state.copyWith(isLoading: false, lastError: failure.message);
        return failure.message;
      }

      _ref.invalidate(householdMembersProvider);
      _ref.invalidate(currentHouseholdProvider);
      state = state.copyWith(isLoading: false, clearError: true);
      return null;
    } catch (e) {
      final message = 'Failed to add household member: $e';
      state = state.copyWith(isLoading: false, lastError: message);
      return message;
    }
  }

  Future<String?> toggleItemVisibility(Item item) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final targetVisibility = item.visibility.isHousehold
          ? ItemVisibility.private_
          : ItemVisibility.household;
      if (targetVisibility.isHousehold &&
          _currentUserOwnsItem(item) &&
          !item.isBackedUp) {
        state = state.copyWith(
          isLoading: false,
          lastError: _backupRequiredMessage,
        );
        return _backupRequiredMessage;
      }

      final householdId = targetVisibility.isHousehold
          ? await _requireHouseholdId()
          : item.householdId;

      // Family sharing requires cloud backup — ensure isBackedUp is set.
      final updated = item.copyWith(
        visibility: targetVisibility,
        householdId: targetVisibility.isHousehold ? householdId : null,
        clearHouseholdId: !targetVisibility.isHousehold,
        isBackedUp: item.isBackedUp,
        sharedWithMemberUuids:
            targetVisibility.isHousehold ? item.sharedWithMemberUuids : const [],
        updatedAt: DateTime.now(),
      );

      final failure = await _ref.read(itemRepositoryProvider).updateItem(updated);
      if (failure != null) {
        state = state.copyWith(isLoading: false, lastError: failure.message);
        return failure.message;
      }

      _invalidateItemState(updated.uuid);
      state = state.copyWith(isLoading: false, clearError: true);
      return null;
    } catch (e) {
      final message = 'Failed to update item visibility: $e';
      state = state.copyWith(isLoading: false, lastError: message);
      return message;
    }
  }

  Future<String?> updateSharedItemLocation({
    required Item item,
    required String locationUuid,
    String? movedByName,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final householdId = item.householdId ?? await _requireHouseholdId();
      final user = _ref.read(authStateProvider).valueOrNull;
      final updated = item.copyWith(
        locationUuid: locationUuid,
        householdId: householdId,
        visibility: ItemVisibility.household,
        updatedAt: DateTime.now(),
      );

      final failure = await _ref.read(itemRepositoryProvider).updateItem(
            updated,
            movedByMemberUuid: user?.uid,
            movedByName: movedByName ?? _resolveMoverName(user),
          );
      if (failure != null) {
        state = state.copyWith(isLoading: false, lastError: failure.message);
        return failure.message;
      }

      _invalidateItemState(updated.uuid);
      state = state.copyWith(isLoading: false, clearError: true);
      return null;
    } catch (e) {
      final message = 'Failed to update shared item location: $e';
      state = state.copyWith(isLoading: false, lastError: message);
      return message;
    }
  }

  Future<String?> inviteMember({
    required String name,
    required String email,
  }) async {
    final userId = email.trim().toLowerCase();
    return addMember(userId: userId, name: name, email: email);
  }

  Future<String?> requestToBorrow({
    required SharedItem item,
    DateTime? requestedReturnDate,
    String? note,
  }) async {
    return 'Borrow requests are not wired into the shared-pool controller yet.';
  }

  Future<String?> approveRequest(FirestoreBorrowRequest request) async {
    return 'Borrow requests are not wired into the shared-pool controller yet.';
  }

  Future<String?> denyRequest(FirestoreBorrowRequest request) async {
    return 'Borrow requests are not wired into the shared-pool controller yet.';
  }

  Future<String?> cancelRequest(FirestoreBorrowRequest request) async {
    return 'Borrow requests are not wired into the shared-pool controller yet.';
  }

  Future<String?> markItemReturned(Item item) async {
    final updated = item.copyWith(
      isLent: false,
      clearLentTo: true,
      clearLentOn: true,
      clearExpectedReturnDate: true,
      clearLentReminderAfterDays: true,
    );
    final failure = await _ref.read(itemRepositoryProvider).updateItem(updated);
    if (failure != null) return failure.message;

    await _ref.read(notificationServiceProvider).cancelLentReminder(item.uuid);

    final syncResult = await _ref.read(syncServiceProvider).syncItem(updated);
    _ref.read(syncStatusProvider.notifier).state = syncResult;

    _invalidateItemState(item.uuid);
    return null;
  }

  Future<String> _requireHouseholdId() async {
    final householdId = await _ref.read(currentHouseholdIdProvider.future);
    if (householdId == null || householdId.isEmpty) {
      throw StateError('Create a household before sharing items.');
    }
    return householdId;
  }

  Future<void> _refreshHouseholdState() async {
    _ref.invalidate(currentHouseholdProvider);
    _ref.invalidate(currentHouseholdIdProvider);
    _ref.invalidate(householdMembersProvider);
    final syncResult = await _ref.read(householdSyncBootstrapProvider.future);
    _ref.read(syncStatusProvider.notifier).state = syncResult;
  }

  /// Refreshes only the providers that are likely stale after a single-item
  /// mutation.  The heavy list providers (`allItemsProvider`, etc.) are
  /// coalesced into a single microtask so that multiple back-to-back calls
  /// to `_invalidateItemState` only trigger one round of list re-fetches.
  bool _listInvalidationScheduled = false;

  void _invalidateItemState(String itemUuid) {
    // Always refresh the specific item immediately.
    _ref.invalidate(singleItemProvider(itemUuid));
    _ref.invalidate(itemHistoryProvider(itemUuid));
    _ref.invalidate(itemLatestHistoryProvider(itemUuid));

    // Coalesce list-level invalidations — multiple calls within the same
    // microtask (e.g. batch visibility toggle) result in a single refresh.
    if (!_listInvalidationScheduled) {
      _listInvalidationScheduled = true;
      Future.microtask(() {
        _listInvalidationScheduled = false;
        _ref.invalidate(allItemsProvider);
        _ref.invalidate(lentItemsProvider);
        _ref.invalidate(lendableItemsProvider);
        _ref.invalidate(forgottenItemsProvider);
        _ref.invalidate(householdSharedItemsProvider);
      });
    }
  }

  bool _currentUserOwnsItem(Item item) {
    final currentUserUid = _ref.read(authStateProvider).valueOrNull?.uid.trim();
    final cloudId = item.cloudId?.trim();
    if (currentUserUid == null || currentUserUid.isEmpty) {
      return true;
    }
    if (cloudId == null || cloudId.isEmpty || cloudId == item.uuid) {
      return true;
    }
    return cloudId == currentUserUid;
  }

  String _resolveMoverName(User? user) {
    final displayName = user?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return 'You';
  }
}

final householdNotifierProvider =
    StateNotifierProvider<HouseholdNotifier, HouseholdActionState>((ref) {
  return HouseholdNotifier(ref);
});

class HouseholdMemberLookupController
    extends StateNotifier<HouseholdMemberLookupState> {
  HouseholdMemberLookupController(this._ref)
      : super(const HouseholdMemberLookupState());

  static final RegExp _emailPattern = RegExp(
    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    caseSensitive: false,
  );

  final Ref _ref;

  Future<void> searchUser(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      state = state.copyWith(
        searchedEmail: '',
        isLoading: false,
        errorMessage: 'Enter an email address.',
        clearFoundUser: true,
      );
      return;
    }
    if (!_emailPattern.hasMatch(normalizedEmail)) {
      state = state.copyWith(
        searchedEmail: normalizedEmail,
        isLoading: false,
        errorMessage: 'Enter a valid email address.',
        clearFoundUser: true,
      );
      return;
    }

    final authUser = _ref.read(authStateProvider).valueOrNull;
    final ownEmail = authUser?.email?.trim().toLowerCase();
    if (ownEmail != null && ownEmail == normalizedEmail) {
      state = state.copyWith(
        searchedEmail: normalizedEmail,
        isLoading: false,
        errorMessage: 'You cannot add your own account to the household.',
        clearFoundUser: true,
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      searchedEmail: normalizedEmail,
      clearError: true,
      clearFoundUser: true,
    );

    try {
      final user =
          await _ref.read(householdRepositoryProvider).getUserByEmail(normalizedEmail);
      if (user == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage:
              'No Ikeep account found with this email. Ask them to sign up first.',
          clearFoundUser: true,
        );
        return;
      }

      final household = await _ref.read(currentHouseholdProvider.future);
      if (household != null && household.memberIds.contains(user.uid)) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'This person is already in your household.',
          clearFoundUser: true,
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        foundUserId: user.uid,
        foundUser: user,
        clearError: true,
      );
    } on FormatException {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Enter a valid email address.',
        clearFoundUser: true,
      );
    } on StateError catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
        clearFoundUser: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to verify that email: $e',
        clearFoundUser: true,
      );
    }
  }

  void resetForm() {
    state = const HouseholdMemberLookupState();
  }
}

final householdMemberLookupProvider = StateNotifierProvider.autoDispose<
    HouseholdMemberLookupController, HouseholdMemberLookupState>((ref) {
  return HouseholdMemberLookupController(ref);
});
