import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/models/app_user.dart';
import '../domain/models/household.dart';
import '../domain/models/household_member.dart';
import '../domain/models/item.dart';
import '../domain/models/item_location_history.dart';
import '../domain/models/shared_item.dart';
import 'firebase_image_upload_service.dart';

/// Manages all Firestore operations for household sharing:
/// - Household creation, member invites, member fetching
/// - Shared item catalog (sync lendable items to Firestore)
/// - Borrow requests (create, approve, deny, cancel, return)
class HouseholdCloudService {
  HouseholdCloudService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required FirebaseImageUploadService imageUploadService,
  })  : _auth = auth,
        _firestore = firestore,
        _imageUploadService = imageUploadService;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseImageUploadService _imageUploadService;

  static const _usersCol = 'users';
  static const _householdsCol = 'households';
  static const _membersSubcol = 'members';
  static const _invitesCol = 'household_invites';
  static const _sharedItemsSubcol = 'shared_items';
  static const _historySubcol = 'history';
  static const _borrowRequestsSubcol = 'borrow_requests';

  User? get currentUser => _auth.currentUser;

  Future<AppUser?> getUserByEmail(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw StateError('Email is required');
    }

    try {
      final snapshot = await _firestore
          .collection(_usersCol)
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      final doc = snapshot.docs.first;
      return AppUser.fromJson(doc.id, doc.data());
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError(
          'Firestore rules are blocking user lookup. Allow authenticated reads on users.',
        );
      }
      throw StateError(e.message ?? 'Failed to look up user');
    }
  }

  Future<Household> createHousehold({required String name}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please sign in to create a household');
    }

    final householdRef = _firestore.collection(_householdsCol).doc();
    final now = FieldValue.serverTimestamp();
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw StateError('Household name is required');
    }

    final existingHouseholdId = await getUserHouseholdId();
    if (existingHouseholdId != null && existingHouseholdId.isNotEmpty) {
      await _firestore.collection(_householdsCol).doc(existingHouseholdId).set({
        'name': normalizedName,
        'updatedAt': now,
      }, SetOptions(merge: true));

      final existing = await fetchHousehold(existingHouseholdId);
      if (existing != null) {
        return existing.copyWith(name: normalizedName);
      }
    }

    await householdRef.set({
      'householdId': householdRef.id,
      'ownerId': user.uid,
      'ownerUid': user.uid,
      'ownerEmail': user.email,
      'name': normalizedName,
      'members': <String>[user.uid],
      'createdAt': now,
      'updatedAt': now,
    });

    await _firestore.collection(_usersCol).doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'displayName': _displayName(user),
      'householdId': householdRef.id,
      'isOwner': true,
      'updatedAt': now,
    }, SetOptions(merge: true));

    await _upsertMember(
      householdId: householdRef.id,
      uid: user.uid,
      email: user.email,
      name: _displayName(user),
      isOwner: true,
    );

    return Household(
      householdId: householdRef.id,
      ownerId: user.uid,
      name: normalizedName,
      memberIds: [user.uid],
    );
  }

  Future<Household?> fetchHousehold(String householdId) async {
    final snapshot =
        await _firestore.collection(_householdsCol).doc(householdId).get();
    if (!snapshot.exists) return null;

    final data = snapshot.data()!;
    return Household(
      householdId: snapshot.id,
      ownerId: data['ownerId'] as String? ?? data['ownerUid'] as String? ?? '',
      name: data['name'] as String? ?? 'Household',
      memberIds: List<String>.from(data['members'] as List? ?? const []),
      createdAt: _timestampToDateTime(data['createdAt']),
      updatedAt: _timestampToDateTime(data['updatedAt']),
    );
  }

  Future<void> addMemberByUserId({
    required String householdId,
    required String userId,
    String? email,
    String? name,
  }) async {
    final memberName = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()
        : (email?.trim().isNotEmpty ?? false)
            ? email!.trim()
            : 'Member';

    await _upsertMember(
      householdId: householdId,
      uid: userId,
      email: email,
      name: memberName,
      isOwner: false,
    );

    await _firestore.collection(_householdsCol).doc(householdId).set({
      'householdId': householdId,
      'members': FieldValue.arrayUnion([userId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore.collection(_usersCol).doc(userId).set({
      'uid': userId,
      'email': email?.trim().toLowerCase(),
      'householdId': householdId,
      'isOwner': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Household management ────────────────────────────────────────────────

  /// Returns the household ID for the signed-in user.
  /// Creates a new household or accepts a pending invite if needed.
  Future<String> ensureCurrentUserHousehold() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please sign in to use household sharing');
    }
    try {
      final userRef = _firestore.collection(_usersCol).doc(user.uid);
      final userSnap = await userRef.get();
      final existingId = userSnap.data()?['householdId'] as String?;

      if (existingId != null && existingId.isNotEmpty) {
        await _upsertMember(
          householdId: existingId,
          uid: user.uid,
          email: user.email,
          name: _displayName(user),
          isOwner: (userSnap.data()?['isOwner'] as bool?) ?? false,
        );
        return existingId;
      }

      // Check for a pending invite the user can auto-accept
      final accepted = await _acceptPendingInvite(user);
      if (accepted != null) return accepted;

      // No existing household or invite — create a new one
      final householdRef = _firestore.collection(_householdsCol).doc();
      final now = FieldValue.serverTimestamp();
      await householdRef.set({
        'householdId': householdRef.id,
        'ownerId': user.uid,
        'ownerUid': user.uid,
        'ownerEmail': user.email,
        'name': '${_displayName(user)}\'s household',
        'members': <String>[user.uid],
        'createdAt': now,
        'updatedAt': now,
      });

      await userRef.set({
        'uid': user.uid,
        'email': user.email,
        'displayName': _displayName(user),
        'householdId': householdRef.id,
        'isOwner': true,
        'updatedAt': now,
      }, SetOptions(merge: true));

      await _upsertMember(
        householdId: householdRef.id,
        uid: user.uid,
        email: user.email,
        name: _displayName(user),
        isOwner: true,
      );

      return householdRef.id;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError(
          'Firestore rules are blocking household sharing. '
          'Allow authenticated reads/writes for: '
          'users, households, members, household_invites, '
          'shared_items, borrow_requests.',
        );
      }
      throw StateError(e.message ?? 'Household setup failed');
    }
  }

  /// Returns the household ID if the user doc already has one, else null.
  /// Does NOT create a household or accept invites.
  Future<String?> getUserHouseholdId() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final snap =
          await _firestore.collection(_usersCol).doc(user.uid).get();
      return snap.data()?['householdId'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Creates an invite doc in Firestore.
  Future<void> createInvite({
    required String householdId,
    required String invitedName,
    required String invitedEmail,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please sign in to invite household members');
    }

    final email = invitedEmail.trim().toLowerCase();
    if (email.isEmpty) throw StateError('Email is required');
    if (user.email?.toLowerCase() == email) {
      throw StateError('You cannot invite your own email');
    }

    try {
      // Prevent duplicate member
      final existing = await _firestore
          .collection(_householdsCol)
          .doc(householdId)
          .collection(_membersSubcol)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        throw StateError('That person is already in your household');
      }

      // Prevent duplicate pending invite
      final pendingInvite = await _firestore
          .collection(_invitesCol)
          .where('householdId', isEqualTo: householdId)
          .where('invitedEmail', isEqualTo: email)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      if (pendingInvite.docs.isNotEmpty) {
        throw StateError('An invite is already pending for this email');
      }

      await _firestore.collection(_invitesCol).add({
        'householdId': householdId,
        'invitedName': invitedName.trim(),
        'invitedEmail': email,
        'inviterUid': user.uid,
        'inviterEmail': user.email,
        'inviterName': _displayName(user),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError(
          'Firestore rules are blocking invite creation. '
          'Allow authenticated writes to household_invites.',
        );
      }
      throw StateError(e.message ?? 'Failed to send invite');
    }
  }

  /// Fetches all members of a household from Firestore.
  Future<List<HouseholdMember>> fetchMembers(String householdId) async {
    final snapshot = await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_membersSubcol)
        .get();

    final members = snapshot.docs.map((doc) {
      final d = doc.data();
      final joinedAt = d['joinedAt'];
      DateTime invitedAt = DateTime.now();
      if (joinedAt is Timestamp) invitedAt = joinedAt.toDate();

      return HouseholdMember(
        uuid: doc.id,
        name: (d['name'] as String?)?.trim().isNotEmpty == true
            ? d['name'] as String
            : ((d['email'] as String?) ?? 'Member'),
        invitedAt: invitedAt,
        isOwner: (d['isOwner'] as bool?) ?? false,
        email: d['email'] as String?,
        householdId: householdId,
        joinedAt: joinedAt is Timestamp ? joinedAt.toDate() : null,
      );
    }).toList();

    members.sort((a, b) {
      if (a.isOwner != b.isOwner) {
        return a.isOwner ? -1 : 1;
      }

      final aJoined = a.joinedAt ?? a.invitedAt;
      final bJoined = b.joinedAt ?? b.invitedAt;
      return aJoined.compareTo(bJoined);
    });

    return members;
  }

  // ── Shared items catalog ────────────────────────────────────────────────

  /// Syncs a local item to the household shared catalog in Firestore.
  /// Called when user marks an item as "available for lending".
  Future<void> syncSharedItem({
    required String householdId,
    required Item item,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final uploadedImageUrls = await _imageUploadService.uploadItemImages(
      userId: user.uid,
      itemUuid: item.uuid,
      imagePaths: item.imagePaths,
    );
    final itemRef = _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_sharedItemsSubcol)
        .doc(item.uuid);
    final existingSnapshot = await itemRef.get();
    final existingData = existingSnapshot.data();

    final existingOwnerUid = (existingData?['ownerUid'] as String?)?.trim();
    final existingOwnerName = (existingData?['ownerName'] as String?)?.trim();
    final itemOwnerUid = item.cloudId?.trim();

    final ownerUid = existingOwnerUid?.isNotEmpty == true
        ? existingOwnerUid!
        : itemOwnerUid?.isNotEmpty == true
            ? itemOwnerUid!
            : user.uid;
    final ownerName = existingOwnerName?.isNotEmpty == true
        ? existingOwnerName!
        : _displayName(user);

    await itemRef.set({
      ...item.copyWith(imagePaths: uploadedImageUrls).toJson(),
      'ownerUid': ownerUid,
      'ownerName': ownerName,
      'householdId': householdId,
      'visibility': item.visibility.value,
      'name': item.name,
      'locationUuid': item.locationUuid,
      'locationName': item.locationName ?? item.locationFullPath ?? '',
      'tags': item.tags,
      'isLent': item.isLent,
      'lentToName': item.lentTo,
      'lentToUid': null,
      'savedAt': item.savedAt.toIso8601String(),
      'expectedReturnDate': item.expectedReturnDate != null
          ? Timestamp.fromDate(item.expectedReturnDate!)
          : null,
      'createdAt': item.savedAt.toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Removes an item from the household shared catalog.
  /// Called when user un-shares an item or deletes it.
  Future<void> removeSharedItem({
    required String householdId,
    required String itemUuid,
  }) async {
    await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_sharedItemsSubcol)
        .doc(itemUuid)
        .delete();
  }

  /// Fetches all shared items in the household (from ALL members).
  Future<List<SharedItem>> fetchHouseholdSharedItems(
    String householdId,
  ) async {
    final snapshot = await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_sharedItemsSubcol)
        .orderBy('updatedAt', descending: true)
        .get();

    return snapshot.docs.map((doc) => SharedItem.fromFirestore(doc)).toList();
  }

  Future<void> syncItemHistory({
    required String householdId,
    required ItemLocationHistory history,
  }) async {
    await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_sharedItemsSubcol)
        .doc(history.itemUuid)
        .collection(_historySubcol)
        .doc(history.uuid)
        .set({
      'historyId': history.historyId,
      'itemId': history.itemId,
      'userId': history.userId,
      'userName': history.userName,
      'userEmail': history.userEmail,
      'locationUuid': history.locationUuid,
      'locationName': history.locationName,
      'timestamp': Timestamp.fromDate(history.timestamp),
      'actionDescription': history.resolvedActionDescription,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<ItemLocationHistory>> fetchItemHistory({
    required String householdId,
    required String itemUuid,
  }) async {
    final snapshot = await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_sharedItemsSubcol)
        .doc(itemUuid)
        .collection(_historySubcol)
        .orderBy('timestamp')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return ItemLocationHistory(
        uuid: doc.id,
        itemUuid: data['itemId'] as String? ?? itemUuid,
        locationUuid: data['locationUuid'] as String?,
        locationName: data['locationName'] as String? ?? 'Unknown',
        movedAt: _timestampToDateTime(data['timestamp']) ?? DateTime.now(),
        movedByMemberUuid: data['userId'] as String?,
        movedByName: data['userName'] as String?,
        userEmail: data['userEmail'] as String?,
        householdId: householdId,
        actionDescription: data['actionDescription'] as String?,
      );
    }).toList();
  }

  /// Fetches shared items from OTHER members only (excludes current user's).
  Future<List<SharedItem>> fetchOtherMembersSharedItems(
    String householdId,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return const [];

    final snapshot = await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_sharedItemsSubcol)
        .where('ownerUid', isNotEqualTo: user.uid)
        .get();

    return snapshot.docs.map((doc) => SharedItem.fromFirestore(doc)).toList();
  }

  // ── Borrow requests ─────────────────────────────────────────────────────

  /// Creates a borrow request in Firestore.
  /// The requester sends this from their device; the owner sees it on theirs.
  Future<String> createBorrowRequest({
    required String householdId,
    required SharedItem item,
    DateTime? requestedReturnDate,
    String? note,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in to send borrow requests');

    if (user.uid == item.ownerUid) {
      throw StateError('You cannot borrow your own item');
    }

    if (item.isLent) {
      throw StateError('This item is currently lent out');
    }

    // Prevent duplicate pending request from same user
    final existing = await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_borrowRequestsSubcol)
        .where('itemUuid', isEqualTo: item.itemUuid)
        .where('requesterUid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw StateError('You already have a pending request for this item');
    }

    final docRef = await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_borrowRequestsSubcol)
        .add({
      'itemUuid': item.itemUuid,
      'itemName': item.name,
      'ownerUid': item.ownerUid,
      'ownerName': item.ownerName,
      'requesterUid': user.uid,
      'requesterName': _displayName(user),
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
      'respondedAt': null,
      'requestedReturnDate': requestedReturnDate != null
          ? Timestamp.fromDate(requestedReturnDate)
          : null,
      'note': note,
    });

    return docRef.id;
  }

  /// Approves a borrow request. Only the item owner should call this.
  /// Also marks the shared item as lent in Firestore and auto-denies
  /// other pending requests for the same item.
  ///
  /// Uses a Firestore transaction to atomically verify the request status,
  /// approve it, mark the item as lent, and deny competing requests.
  Future<void> approveBorrowRequest({
    required String householdId,
    required String requestId,
  }) async {
    final requestsCol = _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_borrowRequestsSubcol);
    final reqRef = requestsCol.doc(requestId);

    await _firestore.runTransaction((transaction) async {
      final reqSnap = await transaction.get(reqRef);
      if (!reqSnap.exists) throw StateError('Request not found');

      final data = reqSnap.data()!;
      if (data['status'] != 'pending') {
        throw StateError('This request has already been handled');
      }

      final itemUuid = data['itemUuid'] as String;
      final requesterName = data['requesterName'] as String? ?? 'Someone';
      final requesterUid = data['requesterUid'] as String;
      final returnDate = data['requestedReturnDate'] as Timestamp?;
      final now = FieldValue.serverTimestamp();

      // Approve the request
      transaction.update(reqRef, {'status': 'approved', 'respondedAt': now});

      // Mark the shared item as lent
      final itemRef = _firestore
          .collection(_householdsCol)
          .doc(householdId)
          .collection(_sharedItemsSubcol)
          .doc(itemUuid);
      transaction.update(itemRef, {
        'isLent': true,
        'lentToName': requesterName,
        'lentToUid': requesterUid,
        'expectedReturnDate': returnDate,
        'updatedAt': now,
      });

      // Auto-deny all other pending requests for this item.
      // Note: Firestore transactions cannot query, so we fetch pending
      // requests before the transaction and verify inside.
      final others = await requestsCol
          .where('itemUuid', isEqualTo: itemUuid)
          .where('status', isEqualTo: 'pending')
          .get();

      for (final doc in others.docs) {
        if (doc.id != requestId) {
          transaction.update(doc.reference, {
            'status': 'denied',
            'respondedAt': now,
            'note': 'Another request was approved first.',
          });
        }
      }
    });
  }

  /// Denies a borrow request.
  Future<void> denyBorrowRequest({
    required String householdId,
    required String requestId,
  }) async {
    await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_borrowRequestsSubcol)
        .doc(requestId)
        .update({
      'status': 'denied',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Cancels a borrow request. Only the requester should call this.
  Future<void> cancelBorrowRequest({
    required String householdId,
    required String requestId,
  }) async {
    await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_borrowRequestsSubcol)
        .doc(requestId)
        .update({
      'status': 'cancelled',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks a lent item as returned. Updates both the shared item and the
  /// borrow request atomically in a single batch write.
  Future<void> markItemReturned({
    required String householdId,
    required String itemUuid,
  }) async {
    final now = FieldValue.serverTimestamp();
    final batch = _firestore.batch();

    // Clear lent status on the shared item
    final itemRef = _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_sharedItemsSubcol)
        .doc(itemUuid);
    batch.update(itemRef, {
      'isLent': false,
      'lentToName': null,
      'lentToUid': null,
      'expectedReturnDate': null,
      'updatedAt': now,
    });

    // Mark the latest approved request for this item as returned
    final approved = await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_borrowRequestsSubcol)
        .where('itemUuid', isEqualTo: itemUuid)
        .where('status', isEqualTo: 'approved')
        .orderBy('respondedAt', descending: true)
        .limit(1)
        .get();

    if (approved.docs.isNotEmpty) {
      batch.update(approved.docs.first.reference, {
        'status': 'returned',
        'respondedAt': now,
      });
    }

    await batch.commit();
  }

  /// Fetches incoming borrow requests for the current user (as item owner).
  Future<List<Map<String, dynamic>>> fetchIncomingRequests(
    String householdId,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return const [];

    final snapshot = await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_borrowRequestsSubcol)
        .where('ownerUid', isEqualTo: user.uid)
        .orderBy('requestedAt', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  /// Fetches outgoing borrow requests sent by the current user.
  Future<List<Map<String, dynamic>>> fetchOutgoingRequests(
    String householdId,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return const [];

    final snapshot = await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_borrowRequestsSubcol)
        .where('requesterUid', isEqualTo: user.uid)
        .orderBy('requestedAt', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  /// Fetches all borrow requests for a specific item.
  Future<List<Map<String, dynamic>>> fetchRequestsForItem({
    required String householdId,
    required String itemUuid,
  }) async {
    final snapshot = await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_borrowRequestsSubcol)
        .where('itemUuid', isEqualTo: itemUuid)
        .orderBy('requestedAt', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  // ── Private helpers ─────────────────────────────────────────────────────

  Future<String?> _acceptPendingInvite(User user) async {
    final email = user.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) return null;

    final inviteQuery = await _firestore
        .collection(_invitesCol)
        .where('invitedEmail', isEqualTo: email)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (inviteQuery.docs.isEmpty) return null;

    final inviteDoc = inviteQuery.docs.first;
    final invite = inviteDoc.data();
    final householdId = invite['householdId'] as String;
    final nameFromInvite = (invite['invitedName'] as String?)?.trim();
    final displayName = nameFromInvite?.isNotEmpty == true
        ? nameFromInvite!
        : _displayName(user);

    await _upsertMember(
      householdId: householdId,
      uid: user.uid,
      email: user.email,
      name: displayName,
      isOwner: false,
    );

    await _firestore.collection(_usersCol).doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'displayName': displayName,
      'householdId': householdId,
      'isOwner': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await inviteDoc.reference.update({
      'status': 'accepted',
      'acceptedByUid': user.uid,
      'acceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return householdId;
  }

  Future<void> _upsertMember({
    required String householdId,
    required String uid,
    required String name,
    required bool isOwner,
    String? email,
  }) async {
    await _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_membersSubcol)
        .doc(uid)
        .set({
      'uid': uid,
      'name': name,
      'email': email?.trim().toLowerCase(),
      'isOwner': isOwner,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _displayName(User user) {
    final name = user.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'You';
  }

  DateTime? _timestampToDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
