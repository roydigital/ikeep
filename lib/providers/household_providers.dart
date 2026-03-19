import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/firestore_borrow_request.dart';
import '../domain/models/household.dart';
import '../domain/models/household_member.dart';
import '../domain/models/item.dart';
import '../domain/models/item_visibility.dart';
import '../domain/models/shared_item.dart';
import '../domain/models/sync_status.dart';
import 'history_providers.dart';
import 'item_providers.dart';
import 'repository_providers.dart';
import 'service_providers.dart';
import 'sync_providers.dart';

/// Stream of the Firebase Auth user. Null when signed out.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// Whether the user is signed in with Firebase Auth.
final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).valueOrNull != null;
});

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
final householdSharedItemsProvider =
    StreamProvider<List<SharedItem>>((ref) async* {
  final householdId = await ref.watch(currentHouseholdIdProvider.future);
  if (householdId == null || householdId.isEmpty) {
    yield const [];
    return;
  }

  final itemRepository = ref.watch(itemRepositoryProvider);
  yield _toSharedItems(
    await itemRepository.getSharedItems(householdId: householdId),
    currentUserId: ref.read(authStateProvider).valueOrNull?.uid,
  );

  await for (final _ in ref.watch(householdLocalChangesProvider.stream)) {
    yield _toSharedItems(
      await itemRepository.getSharedItems(householdId: householdId),
      currentUserId: ref.read(authStateProvider).valueOrNull?.uid,
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
      final householdId = targetVisibility.isHousehold
          ? await _requireHouseholdId()
          : item.householdId;

      final updated = item.copyWith(
        visibility: targetVisibility,
        householdId: targetVisibility.isHousehold ? householdId : null,
        updatedAt: DateTime.now(),
      );

      final failure = await _ref.read(itemRepositoryProvider).updateItem(updated);
      if (failure != null) {
        state = state.copyWith(isLoading: false, lastError: failure.message);
        return failure.message;
      }

      final syncResult =
          await _ref.read(householdSyncServiceProvider).syncLocalItemChange(updated);
      _ref.read(syncStatusProvider.notifier).state = syncResult;

      _invalidateItemState(updated.uuid);
      state = state.copyWith(isLoading: false, clearError: true);
      return syncResult.hasError ? syncResult.errorMessage : null;
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

      final syncResult =
          await _ref.read(householdSyncServiceProvider).syncLocalItemChange(updated);
      _ref.read(syncStatusProvider.notifier).state = syncResult;

      _invalidateItemState(updated.uuid);
      state = state.copyWith(isLoading: false, clearError: true);
      return syncResult.hasError ? syncResult.errorMessage : null;
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

  void _invalidateItemState(String itemUuid) {
    _ref.invalidate(allItemsProvider);
    _ref.invalidate(lentItemsProvider);
    _ref.invalidate(lendableItemsProvider);
    _ref.invalidate(forgottenItemsProvider);
    _ref.invalidate(singleItemProvider(itemUuid));
    _ref.invalidate(itemHistoryProvider(itemUuid));
    _ref.invalidate(itemLatestHistoryProvider(itemUuid));
    _ref.invalidate(householdSharedItemsProvider);
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
