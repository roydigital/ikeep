import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/firestore_borrow_request.dart';
import '../domain/models/household_member.dart';
import '../domain/models/item.dart';
import '../domain/models/shared_item.dart';
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

/// Social sharing is disabled for now, so these always resolve empty.
final currentHouseholdIdProvider = FutureProvider<String?>((ref) async => null);
final householdMembersProvider =
    FutureProvider<List<HouseholdMember>>((ref) async => const []);
final householdSharedItemsProvider =
    FutureProvider<List<SharedItem>>((ref) async => const []);
final incomingBorrowRequestsProvider =
    FutureProvider<List<FirestoreBorrowRequest>>((ref) async => const []);
final outgoingBorrowRequestsProvider =
    FutureProvider<List<FirestoreBorrowRequest>>((ref) async => const []);
final borrowRequestsForItemProvider = FutureProvider.family<
    List<FirestoreBorrowRequest>, String>((ref, itemUuid) async => const []);
final pendingIncomingCountProvider = Provider<int>((ref) => 0);

class HouseholdNotifier extends StateNotifier<bool> {
  HouseholdNotifier(this._ref) : super(false);

  final Ref _ref;
  static const _disabled = 'Social sharing is currently disabled.';

  Future<String?> inviteMember({
    required String name,
    required String email,
  }) async {
    return _disabled;
  }

  Future<String?> toggleItemSharing(Item item) async {
    return _disabled;
  }

  Future<String?> requestToBorrow({
    required SharedItem item,
    DateTime? requestedReturnDate,
    String? note,
  }) async {
    return _disabled;
  }

  Future<String?> approveRequest(FirestoreBorrowRequest request) async {
    return _disabled;
  }

  Future<String?> denyRequest(FirestoreBorrowRequest request) async {
    return _disabled;
  }

  Future<String?> cancelRequest(FirestoreBorrowRequest request) async {
    return _disabled;
  }

  Future<String?> markItemReturned(Item item) async {
    final updated = item.copyWith(
      isLent: false,
      clearLentTo: true,
      clearLentOn: true,
      clearExpectedReturnDate: true,
      clearLentReminderAfterDays: true,
    );
    final failure =
        await _ref.read(itemRepositoryProvider).updateItem(updated);
    if (failure != null) return failure.message;

    await _ref.read(notificationServiceProvider).cancelLentReminder(item.uuid);

    final syncResult = await _ref.read(syncServiceProvider).syncItem(updated);
    _ref.read(syncStatusProvider.notifier).state = syncResult;

    _ref.invalidate(allItemsProvider);
    _ref.invalidate(lentItemsProvider);
    _ref.invalidate(singleItemProvider(item.uuid));
    _ref.invalidate(itemHistoryProvider(item.uuid));
    return null;
  }
}

final householdNotifierProvider =
    StateNotifierProvider<HouseholdNotifier, bool>((ref) {
  return HouseholdNotifier(ref);
});
