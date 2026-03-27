import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../domain/models/app_user.dart';
import '../domain/models/household.dart';
import '../domain/models/household_member.dart';
import '../domain/models/item.dart';
import '../domain/models/item_location_history.dart';
import '../domain/models/shared_item.dart';
import '../core/constants/feature_limits.dart';
import 'cloud_observation_service.dart';
import 'cloud_quota_service.dart';
import 'firebase_image_upload_service.dart';
import 'firebase_invoice_storage_service.dart';

enum HouseholdAccessStatus { member, notMember, unknown }

class HouseholdAccessState {
  const HouseholdAccessState({
    required this.householdId,
    required this.status,
    this.ownerUid,
    this.isOwner = false,
  });

  final String householdId;
  final HouseholdAccessStatus status;
  final String? ownerUid;
  final bool isOwner;

  bool get canSync => status == HouseholdAccessStatus.member;
  bool get accessLost => status == HouseholdAccessStatus.notMember;
  bool get accessUncertain => status == HouseholdAccessStatus.unknown;
}

class HouseholdSharedItemRemoteState {
  const HouseholdSharedItemRemoteState({
    required this.householdId,
    required this.itemUuid,
    this.itemData,
    this.tombstoneData,
  });

  final String householdId;
  final String itemUuid;
  final Map<String, dynamic>? itemData;
  final Map<String, dynamic>? tombstoneData;

  bool get hasItem => itemData != null;
  bool get hasTombstone => tombstoneData != null;

  String? get ownerUid =>
      (itemData?['ownerUid'] as String?)?.trim() ??
      (tombstoneData?['ownerUid'] as String?)?.trim();

  String? get tombstoneReason =>
      (tombstoneData?['reason'] as String?)?.trim();
}

/// Manages all Firestore operations for household sharing:
/// - Household creation, member invites, member fetching
/// - Shared item catalog (sync lendable items to Firestore)
/// - Borrow requests (create, approve, deny, cancel, return)
class HouseholdCloudService {
  HouseholdCloudService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required FirebaseImageUploadService imageUploadService,
    required FirebaseInvoiceStorageService invoiceStorageService,
    required CloudQuotaService cloudQuotaService,
    required CloudObservationService cloudObservationService,
  })  : _auth = auth,
        _firestore = firestore,
        _imageUploadService = imageUploadService,
        _invoiceStorageService = invoiceStorageService,
        _cloudQuotaService = cloudQuotaService,
        _cloudObservationService = cloudObservationService;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseImageUploadService _imageUploadService;
  final FirebaseInvoiceStorageService _invoiceStorageService;
  final CloudQuotaService _cloudQuotaService;
  final CloudObservationService _cloudObservationService;

  static const _usersCol = 'users';
  static const _householdsCol = 'households';
  static const _membersSubcol = 'members';
  static const _invitesCol = 'household_invites';
  static const _sharedItemsSubcol = 'shared_items';
  static const _sharedItemTombstonesSubcol = 'shared_item_tombstones';
  static const _historySubcol = 'history';
  static const _borrowRequestsSubcol = 'borrow_requests';
  static const _deleteReasonOwnerDeleted = 'owner_deleted';
  static const _deleteReasonOwnerUnshared = 'owner_unshared';
  static const _sharedTombstoneRetention = Duration(days: 45);
  static const _sharedTombstoneCleanupBatchSize = 50;

  User? get currentUser => _auth.currentUser;

  CollectionReference<Map<String, dynamic>> _sharedItemsCollection(
    String householdId,
  ) {
    return _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_sharedItemsSubcol);
  }

  CollectionReference<Map<String, dynamic>> _sharedItemTombstonesCollection(
    String householdId,
  ) {
    return _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_sharedItemTombstonesSubcol);
  }

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

    final batch = _firestore.batch();
    batch.set(householdRef, {
      'householdId': householdRef.id,
      'ownerId': user.uid,
      'ownerUid': user.uid,
      'ownerEmail': user.email,
      'name': normalizedName,
      'members': <String>[user.uid],
      'createdAt': now,
      'updatedAt': now,
    });

    batch.set(
      _firestore.collection(_usersCol).doc(user.uid),
      {
        'uid': user.uid,
        'email': user.email,
        'displayName': _displayName(user),
        'householdId': householdRef.id,
        'isOwner': true,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    batch.set(
      householdRef.collection(_membersSubcol).doc(user.uid),
      {
        'uid': user.uid,
        'name': _displayName(user),
        'email': user.email?.trim().toLowerCase(),
        'isOwner': true,
        'joinedAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    await batch.commit();

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
    final evaluation = await _cloudQuotaService.evaluateHouseholdMemberAddition(
      householdId: householdId,
    );
    if (!evaluation.allowedNow) {
      throw StateError(evaluation.message);
    }

    final memberName = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()
        : (email?.trim().isNotEmpty ?? false)
            ? email!.trim()
            : 'Member';

    final now = FieldValue.serverTimestamp();
    final batch = _firestore.batch();

    batch.set(
      _firestore
          .collection(_householdsCol)
          .doc(householdId)
          .collection(_membersSubcol)
          .doc(userId),
      {
        'uid': userId,
        'name': memberName,
        'email': email?.trim().toLowerCase(),
        'isOwner': false,
        'joinedAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _firestore.collection(_householdsCol).doc(householdId),
      {
        'householdId': householdId,
        'members': FieldValue.arrayUnion([userId]),
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _firestore.collection(_usersCol).doc(userId),
      {
        'uid': userId,
        'email': email?.trim().toLowerCase(),
        'householdId': householdId,
        'isOwner': false,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
    await _cloudQuotaService.refreshHouseholdUsage(householdId);
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

      // No existing household or invite — create a new one using a single
      // batched write (one network round-trip instead of three).
      final householdRef = _firestore.collection(_householdsCol).doc();
      final now = FieldValue.serverTimestamp();
      final displayName = _displayName(user);

      final batch = _firestore.batch();

      batch.set(householdRef, {
        'householdId': householdRef.id,
        'ownerId': user.uid,
        'ownerUid': user.uid,
        'ownerEmail': user.email,
        'name': '$displayName\'s household',
        'members': <String>[user.uid],
        'createdAt': now,
        'updatedAt': now,
      });

      batch.set(
        userRef,
        {
          'uid': user.uid,
          'email': user.email,
          'displayName': displayName,
          'householdId': householdRef.id,
          'isOwner': true,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      batch.set(
        householdRef.collection(_membersSubcol).doc(user.uid),
        {
          'uid': user.uid,
          'name': displayName,
          'email': user.email?.trim().toLowerCase(),
          'isOwner': true,
          'joinedAt': now,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

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
      final snap = await _firestore.collection(_usersCol).doc(user.uid).get();
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
      // Run both duplicate checks in parallel (independent queries).
      final checks = await Future.wait([
        _firestore
            .collection(_householdsCol)
            .doc(householdId)
            .collection(_membersSubcol)
            .where('email', isEqualTo: email)
            .limit(1)
            .get(),
        _firestore
            .collection(_invitesCol)
            .where('householdId', isEqualTo: householdId)
            .where('invitedEmail', isEqualTo: email)
            .where('status', isEqualTo: 'pending')
            .limit(1)
            .get(),
      ]);

      if (checks[0].docs.isNotEmpty) {
        throw StateError('That person is already in your household');
      }
      if (checks[1].docs.isNotEmpty) {
        throw StateError('An invite is already pending for this email');
      }

      final evaluation = await _cloudQuotaService
          .evaluateHouseholdMemberAddition(householdId: householdId);
      if (!evaluation.allowedNow) {
        throw StateError(evaluation.message);
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

  Future<HouseholdAccessState> getAccessState(String householdId) async {
    final user = _auth.currentUser;
    if (user == null || householdId.trim().isEmpty) {
      return HouseholdAccessState(
        householdId: householdId,
        status: HouseholdAccessStatus.unknown,
      );
    }

    try {
      final results = await Future.wait([
        _firestore.collection(_usersCol).doc(user.uid).get(),
        _firestore.collection(_householdsCol).doc(householdId).get(),
        _firestore
            .collection(_householdsCol)
            .doc(householdId)
            .collection(_membersSubcol)
            .doc(user.uid)
            .get(),
      ]);

      final userDoc = results[0];
      final householdDoc = results[1];
      final memberDoc = results[2];
      final userHouseholdId = (userDoc.data()?['householdId'] as String?)?.trim();

      if (userHouseholdId != null &&
          userHouseholdId.isNotEmpty &&
          userHouseholdId != householdId) {
        return HouseholdAccessState(
          householdId: householdId,
          status: HouseholdAccessStatus.notMember,
        );
      }

      if (!householdDoc.exists) {
        return HouseholdAccessState(
          householdId: householdId,
          status: HouseholdAccessStatus.notMember,
        );
      }

      final ownerUid =
          (householdDoc.data()?['ownerUid'] as String?)?.trim() ??
          (householdDoc.data()?['ownerId'] as String?)?.trim();
      final isOwner = ownerUid != null && ownerUid == user.uid;
      if (isOwner || memberDoc.exists) {
        return HouseholdAccessState(
          householdId: householdId,
          status: HouseholdAccessStatus.member,
          ownerUid: ownerUid,
          isOwner: isOwner || ((memberDoc.data()?['isOwner'] as bool?) ?? false),
        );
      }

      return HouseholdAccessState(
        householdId: householdId,
        status: HouseholdAccessStatus.notMember,
        ownerUid: ownerUid,
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return HouseholdAccessState(
          householdId: householdId,
          status: HouseholdAccessStatus.unknown,
        );
      }
      rethrow;
    }
  }

  // ── Shared items catalog ────────────────────────────────────────────────

  /// Syncs a local item to the household shared catalog in Firestore.
  /// Called when user marks an item as "available for lending".
  Future<void> syncSharedItem({
    required String householdId,
    required Item item,
  }) async {
    final evaluation = await _cloudQuotaService.evaluateSharedItemWrite(
      householdId: householdId,
      item: item,
    );
    if (!evaluation.allowedNow) {
      throw StateError(evaluation.message);
    }

    final user = _auth.currentUser;
    if (user == null) return;
    final itemRef = _sharedItemsCollection(householdId).doc(item.uuid);
    final existingSnapshot = await itemRef.get();
    final existingData = existingSnapshot.data();

    final existingOwnerUid = (existingData?['ownerUid'] as String?)?.trim();
    final existingCloudOwnerUid = (existingData?['cloudId'] as String?)?.trim();
    final existingOwnerName = (existingData?['ownerName'] as String?)?.trim();
    final itemOwnerUid = item.cloudId?.trim();

    final ownerUid = existingOwnerUid?.isNotEmpty == true
        ? existingOwnerUid!
        : existingCloudOwnerUid?.isNotEmpty == true
            ? existingCloudOwnerUid!
        : itemOwnerUid?.isNotEmpty == true
            ? itemOwnerUid!
            : user.uid;
    final ownerName = existingOwnerName?.isNotEmpty == true
        ? existingOwnerName!
        : _displayName(user);
    final isOwnerWrite = ownerUid == user.uid;
    if (existingData == null && !isOwnerWrite) {
      throw StateError(
        'Only the owner can recreate a missing shared item document.',
      );
    }

    // Owner-only fields: content, media, share-state, and delete/unshare.
    // Member-safe fields: location metadata and history only.
    final includeAllFields = existingData == null;
    final includeContentFields = includeAllFields ||
        (isOwnerWrite &&
            _sharedContentNeedsPatch(item: item, existingData: existingData));
    final includeLocationFields = includeAllFields ||
        _sharedLocationNeedsPatch(item: item, existingData: existingData);
    final includeImageFields = includeAllFields ||
        (isOwnerWrite &&
            _sharedImageMediaNeedsSync(item: item, existingData: existingData));
    final includeInvoiceFields = includeAllFields ||
        (isOwnerWrite &&
            _sharedInvoiceMediaNeedsSync(item: item, existingData: existingData));

    ImageUploadResult? uploadedImages;
    StoredInvoiceFile? uploadedInvoice;
    if (includeImageFields) {
      uploadedImages = await _imageUploadService.uploadItemImages(
        userId: ownerUid,
        itemUuid: item.uuid,
        imagePaths: item.imagePaths,
      );
    }
    if (includeInvoiceFields) {
      uploadedInvoice = await _invoiceStorageService.uploadItemInvoice(
        userId: ownerUid,
        itemUuid: item.uuid,
        invoicePath: item.invoicePath,
        invoiceFileName: item.invoiceFileName,
        invoiceFileSizeBytes: item.invoiceFileSizeBytes,
      );
    }

    final syncedItem = item.copyWith(
      imagePaths: includeImageFields
          ? (uploadedImages?.downloadUrls ?? item.imagePaths)
          : item.imagePaths,
      invoicePath: includeInvoiceFields
          ? (uploadedInvoice?.path ?? item.invoicePath)
          : item.invoicePath,
      invoiceFileName: includeInvoiceFields
          ? (uploadedInvoice?.fileName ?? item.invoiceFileName)
          : item.invoiceFileName,
      invoiceFileSizeBytes: includeInvoiceFields
          ? (uploadedInvoice?.sizeBytes ?? item.invoiceFileSizeBytes)
          : item.invoiceFileSizeBytes,
      householdId: householdId,
    );
    final patch = _buildSharedItemPatch(
      householdId: householdId,
      ownerUid: ownerUid,
      ownerName: ownerName,
      item: syncedItem,
      includeAllFields: includeAllFields,
      includeContentFields: includeContentFields,
      includeLocationFields: includeLocationFields,
      includeImageFields: includeImageFields,
      includeInvoiceFields: includeInvoiceFields,
      uploadedImages: uploadedImages,
      uploadedInvoice: uploadedInvoice,
    );

    if (patch.isEmpty) {
      return;
    }

    await itemRef.set(patch, SetOptions(merge: true));
    await _clearSharedItemTombstone(
      householdId: householdId,
      itemUuid: item.uuid,
    );
    await _recordUploadObservation(
      source: 'household_shared_item_sync',
      imageResult: uploadedImages,
      uploadedInvoice: uploadedInvoice,
    );
    await _cloudQuotaService.refreshPersonalUsage();
    await _cloudQuotaService.refreshHouseholdUsage(householdId);
  }

  /// Removes an item from the household shared catalog.
  /// Called when owner deletes an item or disables household sharing.
  Future<void> removeSharedItem({
    required String householdId,
    required String itemUuid,
    String reason = _deleteReasonOwnerDeleted,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final itemRef = _sharedItemsCollection(householdId).doc(itemUuid);
    final existingSnapshot = await itemRef.get();
    final existingData = existingSnapshot.data();
    final ownerUid =
        (existingData?['ownerUid'] as String?)?.trim().isNotEmpty == true
            ? (existingData!['ownerUid'] as String).trim()
            : (existingData?['cloudId'] as String?)?.trim().isNotEmpty == true
                ? (existingData!['cloudId'] as String).trim()
            : user.uid;
    if (ownerUid.trim().isNotEmpty && ownerUid.trim() != user.uid) {
      throw StateError('Only the item owner can delete or unshare it.');
    }

    final batch = _firestore.batch();
    batch.set(
      _sharedItemTombstonesCollection(householdId).doc(itemUuid),
      {
        'itemUuid': itemUuid,
        'householdId': householdId,
        'ownerUid': ownerUid,
        'reason': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.delete(itemRef);
    await batch.commit();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchSharedItemsChangedSince({
    required String householdId,
    DateTime? changedAfter,
  }) {
    Query<Map<String, dynamic>> query =
        _sharedItemsCollection(householdId).orderBy('updatedAt');
    if (changedAfter != null) {
      query = query.where(
        'updatedAt',
        isGreaterThan: Timestamp.fromDate(changedAfter.toUtc()),
      );
    }
    return query.get();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchSharedItemTombstonesChangedSince({
    required String householdId,
    DateTime? changedAfter,
  }) {
    Query<Map<String, dynamic>> query =
        _sharedItemTombstonesCollection(householdId).orderBy('updatedAt');
    if (changedAfter != null) {
      query = query.where(
        'updatedAt',
        isGreaterThan: Timestamp.fromDate(changedAfter.toUtc()),
      );
    }
    return query.get();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchAllSharedItemDocs(
    String householdId,
  ) {
    return _sharedItemsCollection(householdId).get();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchAllSharedItemTombstones(
    String householdId,
  ) {
    return _sharedItemTombstonesCollection(householdId).get();
  }

  Future<HouseholdSharedItemRemoteState> fetchSharedItemRemoteState({
    required String householdId,
    required String itemUuid,
  }) async {
    final results = await Future.wait([
      _sharedItemsCollection(householdId).doc(itemUuid).get(),
      _sharedItemTombstonesCollection(householdId).doc(itemUuid).get(),
    ]);

    return HouseholdSharedItemRemoteState(
      householdId: householdId,
      itemUuid: itemUuid,
      itemData: results[0].data(),
      tombstoneData: results[1].data(),
    );
  }

  Future<String?> fetchLatestSharedRemoteCheckpoint(
    String householdId, {
    bool allowCompatibilityScan = false,
  }) async {
    final results = await Future.wait([
      _sharedItemsCollection(householdId)
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get(),
      _sharedItemTombstonesCollection(householdId)
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get(),
    ]);

    final timestamps = <DateTime>[
      if ((results[0] as QuerySnapshot<Map<String, dynamic>>).docs.isNotEmpty)
        _timestampToDateTime(
              (results[0] as QuerySnapshot<Map<String, dynamic>>)
                  .docs
                  .first
                  .data()['updatedAt'],
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      if ((results[1] as QuerySnapshot<Map<String, dynamic>>).docs.isNotEmpty)
        _timestampToDateTime(
              (results[1] as QuerySnapshot<Map<String, dynamic>>)
                  .docs
                  .first
                  .data()['updatedAt'],
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0),
    ].where((value) => value.millisecondsSinceEpoch > 0).toList(growable: false);

    if (timestamps.isEmpty) {
      if (!allowCompatibilityScan) {
        return null;
      }

      final compatibilityResults = await Future.wait([
        _sharedItemsCollection(householdId).get(),
        _sharedItemTombstonesCollection(householdId).get(),
      ]);
      final compatibilityTimestamps = <DateTime>[];
      for (final doc
          in (compatibilityResults[0] as QuerySnapshot<Map<String, dynamic>>)
              .docs) {
        final changedAt = resolveSharedItemChangedAt(doc.data());
        if (changedAt != null) {
          compatibilityTimestamps.add(changedAt);
        }
      }
      for (final doc
          in (compatibilityResults[1] as QuerySnapshot<Map<String, dynamic>>)
              .docs) {
        final changedAt = resolveSharedTombstoneChangedAt(doc.data());
        if (changedAt != null) {
          compatibilityTimestamps.add(changedAt);
        }
      }
      if (compatibilityTimestamps.isEmpty) {
        return null;
      }
      compatibilityTimestamps.sort();
      final compatibilityCheckpoint =
          compatibilityTimestamps.last.toUtc().toIso8601String();
      debugPrint(
        '[IkeepHouseholdDelta] compatibility checkpoint scan '
        'household=$householdId checkpoint=$compatibilityCheckpoint',
      );
      return compatibilityCheckpoint;
    }

    timestamps.sort();
    return timestamps.last.toUtc().toIso8601String();
  }

  Future<int> cleanupExpiredSharedTombstones({
    required String householdId,
    required DateTime cutoffUtc,
    int batchSize = _sharedTombstoneCleanupBatchSize,
  }) async {
    final normalizedCutoff = cutoffUtc.toUtc();
    final snapshot = await _sharedItemTombstonesCollection(householdId)
        .orderBy('updatedAt')
        .where(
          'updatedAt',
          isLessThanOrEqualTo: Timestamp.fromDate(normalizedCutoff),
        )
        .limit(batchSize)
        .get();

    if (snapshot.docs.isEmpty) {
      debugPrint(
        '[IkeepHouseholdDelta] tombstone cleanup skipped '
        'household=$householdId cutoff=${normalizedCutoff.toIso8601String()} '
        'reason=none_due',
      );
      return 0;
    }

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    debugPrint(
      '[IkeepHouseholdDelta] tombstone cleanup deleted '
      'household=$householdId count=${snapshot.docs.length} '
      'cutoff=${normalizedCutoff.toIso8601String()} '
      'retentionDays=${_sharedTombstoneRetention.inDays}',
    );
    return snapshot.docs.length;
  }

  DateTime? resolveSharedItemChangedAt(Map<String, dynamic> data) {
    final updatedAt = _timestampToDateTime(data['updatedAt']);
    if (updatedAt != null) {
      return updatedAt.toUtc();
    }

    final compatibilityChangedAt =
        _timestampToDateTime(data['lastContentUpdatedAt']) ??
        _timestampToDateTime(data['lastUpdatedAt']) ??
        _timestampToDateTime(data['createdAt']) ??
        _timestampToDateTime(data['savedAt']);
    if (compatibilityChangedAt != null) {
      debugPrint(
        '[IkeepHouseholdDelta] old-doc compatibility shared-item '
        'item=${(data["uuid"] as String?) ?? (data["itemId"] as String?) ?? "unknown"} '
        'changedAt=${compatibilityChangedAt.toUtc().toIso8601String()}',
      );
      return compatibilityChangedAt.toUtc();
    }

    return null;
  }

  DateTime? resolveSharedTombstoneChangedAt(Map<String, dynamic> data) {
    final updatedAt = _timestampToDateTime(data['updatedAt']);
    if (updatedAt != null) {
      return updatedAt.toUtc();
    }

    final compatibilityChangedAt =
        _timestampToDateTime(data['createdAt']) ??
        _timestampToDateTime(data['deletedAt']);
    if (compatibilityChangedAt != null) {
      debugPrint(
        '[IkeepHouseholdDelta] old-doc compatibility tombstone '
        'item=${(data["itemUuid"] as String?) ?? "unknown"} '
        'changedAt=${compatibilityChangedAt.toUtc().toIso8601String()}',
      );
      return compatibilityChangedAt.toUtc();
    }

    return null;
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

  Future<void> _clearSharedItemTombstone({
    required String householdId,
    required String itemUuid,
  }) async {
    try {
      await _sharedItemTombstonesCollection(householdId).doc(itemUuid).delete();
    } on FirebaseException catch (error) {
      if (error.code == 'not-found') {
        return;
      }
      rethrow;
    }
  }

  Map<String, dynamic> _buildSharedItemPatch({
    required String householdId,
    required String ownerUid,
    required String ownerName,
    required Item item,
    required bool includeAllFields,
    required bool includeContentFields,
    required bool includeLocationFields,
    required bool includeImageFields,
    required bool includeInvoiceFields,
    required ImageUploadResult? uploadedImages,
    required StoredInvoiceFile? uploadedInvoice,
  }) {
    final patch = <String, dynamic>{};
    final contentAt = item.lastUpdatedAt ?? item.updatedAt ?? item.savedAt;
    final includeAnyFields = includeAllFields ||
        includeContentFields ||
        includeLocationFields ||
        includeImageFields ||
        includeInvoiceFields;
    if (!includeAnyFields) {
      return patch;
    }

    patch['updatedAt'] = FieldValue.serverTimestamp();

    if (includeAllFields) {
      patch.addAll({
        'uuid': item.uuid,
        'itemId': item.uuid,
        'cloudId': ownerUid,
        'ownerUid': ownerUid,
        'ownerName': ownerName,
        'householdId': householdId,
        'visibility': item.visibility.value,
        'savedAt': item.savedAt.toIso8601String(),
        'createdAt': item.savedAt.toIso8601String(),
      });
    }

    if (includeAllFields || includeContentFields) {
      patch.addAll({
        'name': item.name,
        'title': item.name,
        'notes': item.notes,
        'note': item.notes,
        'tags': item.tags,
        'sharedWithMemberUuids': item.sharedWithMemberUuids,
        'isArchived': item.isArchived,
        'isLent': item.isLent,
        'lentToName': item.lentTo,
        'lentToUid': null,
        'expectedReturnDate': item.expectedReturnDate != null
            ? Timestamp.fromDate(item.expectedReturnDate!.toUtc())
            : null,
        'expiryDate': item.expiryDate?.toIso8601String(),
        'warrantyEndDate': item.warrantyEndDate?.toIso8601String(),
        'seasonCategory': item.seasonCategory,
        'lentReminderAfterDays': item.lentReminderAfterDays,
        'isAvailableForLending': item.isAvailableForLending,
        'lastUpdatedAt': item.lastUpdatedAt?.toIso8601String(),
        'lastContentUpdatedAt': contentAt.toIso8601String(),
        'syncVersion': contentAt.millisecondsSinceEpoch,
      });
    }

    if (includeAllFields || includeLocationFields) {
      patch.addAll({
        'locationUuid': item.locationUuid,
        'areaUuid': item.areaUuid,
        'roomUuid': item.roomUuid,
        'zoneUuid': item.zoneUuid,
        'locationName': item.locationName ?? item.locationFullPath ?? '',
        'latitude': item.latitude,
        'longitude': item.longitude,
        'lastMovedAt': item.lastMovedAt?.toIso8601String(),
      });
    }

    if (includeAllFields || includeImageFields) {
      final mediaDescriptors = uploadedImages?.mediaDescriptors ?? const [];
      patch.addAll({
        'imagePaths': uploadedImages?.downloadUrls ?? const <String>[],
        'imageStoragePaths': uploadedImages?.storagePaths ?? const <String>[],
        'imageMedia': mediaDescriptors
            .map((descriptor) => descriptor.toJson())
            .toList(growable: false),
      });
    }

    if (includeAllFields || includeInvoiceFields) {
      final hasInvoice = item.invoicePath?.trim().isNotEmpty ?? false;
      patch.addAll({
        'invoicePath': hasInvoice ? uploadedInvoice?.path : null,
        'invoiceFileName': hasInvoice
            ? (uploadedInvoice?.fileName ?? item.invoiceFileName)
            : null,
        'invoiceFileSizeBytes': hasInvoice
            ? (uploadedInvoice?.sizeBytes ?? item.invoiceFileSizeBytes)
            : null,
        'invoiceStoragePath': hasInvoice ? uploadedInvoice?.storagePath : null,
        'invoiceMedia': hasInvoice ? uploadedInvoice?.mediaDescriptor?.toJson() : null,
        'invoiceOriginalFileName':
            hasInvoice ? uploadedInvoice?.originalFileName : null,
        'invoiceOriginalFileSizeBytes':
            hasInvoice ? uploadedInvoice?.originalFileSizeBytes : null,
        'invoiceUploadedFileSizeBytes':
            hasInvoice ? uploadedInvoice?.sizeBytes : null,
        'invoiceMimeType': hasInvoice ? uploadedInvoice?.mimeType : null,
        'invoiceCompressionApplied':
            hasInvoice ? uploadedInvoice?.compressionApplied : null,
        'invoiceUploadedAt': hasInvoice ? FieldValue.serverTimestamp() : null,
      });
    }

    return patch;
  }

  bool _sharedContentNeedsPatch({
    required Item item,
    required Map<String, dynamic>? existingData,
  }) {
    if (existingData == null) {
      return true;
    }

    return _trimmedString(existingData['name']) != item.name.trim() ||
        _trimmedString(existingData['notes']) != (item.notes?.trim() ?? '') ||
        !_stringListsEqual(existingData['tags'] as List?, item.tags) ||
        !_stringListsEqual(
          existingData['sharedWithMemberUuids'] as List?,
          item.sharedWithMemberUuids,
        ) ||
        (existingData['isArchived'] as bool? ?? false) != item.isArchived ||
        (existingData['isLent'] as bool? ?? false) != item.isLent ||
        _trimmedString(existingData['lentToName']) != (item.lentTo?.trim() ?? '') ||
        !_sameDateTime(
          _timestampToDateTime(existingData['expectedReturnDate']),
          item.expectedReturnDate,
        ) ||
        _trimmedString(existingData['seasonCategory']) != item.seasonCategory ||
        (existingData['lentReminderAfterDays'] as num?)?.toInt() !=
            item.lentReminderAfterDays ||
        (existingData['isAvailableForLending'] as bool? ?? false) !=
            item.isAvailableForLending ||
        !_sameDateTime(
          _timestampToDateTime(existingData['expiryDate']),
          item.expiryDate,
        ) ||
        !_sameDateTime(
          _timestampToDateTime(existingData['warrantyEndDate']),
          item.warrantyEndDate,
        ) ||
        !_sameDateTime(
          _timestampToDateTime(existingData['lastUpdatedAt']),
          item.lastUpdatedAt,
        );
  }

  bool _sharedLocationNeedsPatch({
    required Item item,
    required Map<String, dynamic>? existingData,
  }) {
    if (existingData == null) {
      return true;
    }

    return _trimmedString(existingData['locationUuid']) !=
            (item.locationUuid?.trim() ?? '') ||
        _trimmedString(existingData['areaUuid']) != (item.areaUuid?.trim() ?? '') ||
        _trimmedString(existingData['roomUuid']) != (item.roomUuid?.trim() ?? '') ||
        _trimmedString(existingData['zoneUuid']) != (item.zoneUuid?.trim() ?? '') ||
        _trimmedString(existingData['locationName']) !=
            ((item.locationName ?? item.locationFullPath ?? '').trim()) ||
        !_sameDouble(existingData['latitude'], item.latitude) ||
        !_sameDouble(existingData['longitude'], item.longitude) ||
        !_sameDateTime(
          _timestampToDateTime(existingData['lastMovedAt']),
          item.lastMovedAt,
        );
  }

  bool _sharedImageMediaNeedsSync({
    required Item item,
    required Map<String, dynamic>? existingData,
  }) {
    final remotePaths =
        List<String>.from((existingData?['imagePaths'] as List?) ?? const []);
    final remoteStoragePaths = List<String>.from(
      (existingData?['imageStoragePaths'] as List?) ?? const [],
    );

    if (item.imagePaths.isEmpty) {
      return remotePaths.isNotEmpty || remoteStoragePaths.isNotEmpty;
    }
    if (item.imagePaths.length != remotePaths.length &&
        item.imagePaths.length != remoteStoragePaths.length) {
      return true;
    }

    for (var index = 0; index < item.imagePaths.length; index++) {
      final candidate = item.imagePaths[index];
      final remoteUrl = index < remotePaths.length ? remotePaths[index] : null;
      final remoteStoragePath =
          index < remoteStoragePaths.length ? remoteStoragePaths[index] : null;
      if (!_pathMatchesRemoteCandidate(
        candidate,
        remoteUrl: remoteUrl,
        remoteStoragePath: remoteStoragePath,
      )) {
        return true;
      }
    }
    return false;
  }

  bool _sharedInvoiceMediaNeedsSync({
    required Item item,
    required Map<String, dynamic>? existingData,
  }) {
    final candidate = item.invoicePath?.trim();
    final remoteUrl = (existingData?['invoicePath'] as String?)?.trim();
    final remoteStoragePath =
        (existingData?['invoiceStoragePath'] as String?)?.trim();

    if (candidate == null || candidate.isEmpty) {
      return (remoteUrl?.isNotEmpty ?? false) ||
          (remoteStoragePath?.isNotEmpty ?? false);
    }

    return !_pathMatchesRemoteCandidate(
      candidate,
      remoteUrl: remoteUrl,
      remoteStoragePath: remoteStoragePath,
    );
  }

  bool _pathMatchesRemoteCandidate(
    String candidate, {
    String? remoteUrl,
    String? remoteStoragePath,
  }) {
    final trimmedCandidate = candidate.trim();
    final trimmedRemoteUrl = remoteUrl?.trim() ?? '';
    final trimmedRemoteStoragePath = remoteStoragePath?.trim() ?? '';
    if (trimmedCandidate.isEmpty) {
      return trimmedRemoteUrl.isEmpty && trimmedRemoteStoragePath.isEmpty;
    }
    if (trimmedCandidate == trimmedRemoteUrl ||
        trimmedCandidate == trimmedRemoteStoragePath) {
      return true;
    }

    final candidateStoragePath = _storagePathCandidate(trimmedCandidate);
    if (candidateStoragePath != null &&
        candidateStoragePath == trimmedRemoteStoragePath) {
      return true;
    }

    final remoteUrlStoragePath = _storagePathCandidate(trimmedRemoteUrl);
    if (candidateStoragePath != null &&
        remoteUrlStoragePath != null &&
        candidateStoragePath == remoteUrlStoragePath) {
      return true;
    }

    return false;
  }

  String? _storagePathCandidate(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('users/')) {
      return trimmed;
    }
    return null;
  }

  bool _stringListsEqual(List? remoteValues, List<String> localValues) {
    final normalizedRemoteValues =
        List<String>.from(remoteValues ?? const []).map((v) => v.trim()).toList();
    final normalizedLocalValues =
        localValues.map((value) => value.trim()).toList(growable: false);
    if (normalizedRemoteValues.length != normalizedLocalValues.length) {
      return false;
    }
    for (var index = 0; index < normalizedRemoteValues.length; index++) {
      if (normalizedRemoteValues[index] != normalizedLocalValues[index]) {
        return false;
      }
    }
    return true;
  }

  String _trimmedString(dynamic value) {
    return (value as String?)?.trim() ?? '';
  }

  bool _sameDouble(dynamic remoteValue, double? localValue) {
    return (remoteValue as num?)?.toDouble() == localValue;
  }

  bool _sameDateTime(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    return a.toUtc().millisecondsSinceEpoch == b.toUtc().millisecondsSinceEpoch;
  }

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
    final evaluation = await _cloudQuotaService.evaluateHouseholdMemberAddition(
      householdId: householdId,
    );
    if (!evaluation.allowedNow) {
      throw StateError(evaluation.message);
    }

    // Batch all three writes into a single network round-trip.
    final now = FieldValue.serverTimestamp();
    final batch = _firestore.batch();

    batch.set(
      _firestore
          .collection(_householdsCol)
          .doc(householdId)
          .collection(_membersSubcol)
          .doc(user.uid),
      {
        'uid': user.uid,
        'name': displayName,
        'email': user.email?.trim().toLowerCase(),
        'isOwner': false,
        'joinedAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _firestore.collection(_usersCol).doc(user.uid),
      {
        'uid': user.uid,
        'email': user.email,
        'displayName': displayName,
        'householdId': householdId,
        'isOwner': false,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    batch.update(inviteDoc.reference, {
      'status': 'accepted',
      'acceptedByUid': user.uid,
      'acceptedAt': now,
      'updatedAt': now,
    });

    await batch.commit();
    await _cloudQuotaService.refreshHouseholdUsage(householdId);

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
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  Future<void> _recordUploadObservation({
    required String source,
    ImageUploadResult? imageResult,
    StoredInvoiceFile? uploadedInvoice,
  }) async {
    final estimatedBytes = _estimatedUploadBytesForResult(
      imageResult: imageResult,
      uploadedInvoice: uploadedInvoice,
    );
    if (estimatedBytes <= 0) {
      return;
    }

    try {
      await _cloudObservationService.recordUpload(
        estimatedBytes: estimatedBytes,
        source: source,
      );
    } catch (error) {
      debugPrint(
        '[IkeepObserve] household upload observation failed '
        'source=$source error=$error',
      );
    }
  }

  int _estimatedUploadBytesForResult({
    ImageUploadResult? imageResult,
    StoredInvoiceFile? uploadedInvoice,
  }) {
    var totalBytes = 0;

    if (imageResult != null) {
      for (final descriptor in imageResult.mediaDescriptors) {
        totalBytes += descriptor.byteSize;
        if ((descriptor.thumbnailPath?.trim().isNotEmpty ?? false)) {
          totalBytes += targetThumbnailBytes;
        }
      }
    }

    totalBytes += uploadedInvoice?.sizeBytes ??
        uploadedInvoice?.mediaDescriptor?.byteSize ??
        uploadedInvoice?.originalFileSizeBytes ??
        0;
    return totalBytes;
  }
}
