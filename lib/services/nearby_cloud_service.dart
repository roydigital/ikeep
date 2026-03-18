import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/models/item.dart';
import '../domain/models/nearby_item.dart';

/// Manages Firestore operations for locality-based public lending.
/// Uses top-level collections (not nested under households) so items
/// are discoverable by any authenticated user in the same locality.
class NearbyCloudService {
  NearbyCloudService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static const _nearbyItemsCol = 'nearby_items';
  static const _nearbyRequestsCol = 'nearby_borrow_requests';
  static const _usersCol = 'users';

  User? get _currentUser => _auth.currentUser;

  // ── Public item catalog ─────────────────────────────────────────────────

  /// Publishes an item to the nearby catalog so strangers in the same
  /// locality can discover and request it.
  Future<void> publishItem({
    required Item item,
    required String locality,
  }) async {
    final user = _currentUser;
    if (user == null) throw StateError('Sign in to share items nearby');

    final now = FieldValue.serverTimestamp();
    await _firestore.collection(_nearbyItemsCol).doc(item.uuid).set({
      'ownerUid': user.uid,
      'ownerName': user.displayName ?? user.email ?? 'Unknown',
      'name': item.name,
      'tags': item.tags,
      'locationName': item.locationName ?? item.locationFullPath ?? '',
      'locality': locality,
      'country': '', // Can be populated later from geocoding
      'isLent': item.isLent,
      'lentToName': item.lentTo,
      'lentToUid': null,
      'expectedReturnDate': item.expectedReturnDate != null
          ? Timestamp.fromDate(item.expectedReturnDate!)
          : null,
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    // Also update the user's locality in their profile.
    await _firestore.collection(_usersCol).doc(user.uid).set({
      'locality': locality,
      'localityUpdatedAt': now,
      'nearbyEnabled': true,
    }, SetOptions(merge: true));
  }

  /// Removes an item from the nearby catalog.
  Future<void> removeItem(String itemUuid) async {
    await _firestore.collection(_nearbyItemsCol).doc(itemUuid).delete();
  }

  /// Updates the lent status of a nearby item.
  Future<void> updateLentStatus({
    required String itemUuid,
    required bool isLent,
    String? lentToName,
    String? lentToUid,
    DateTime? expectedReturnDate,
  }) async {
    final docRef = _firestore.collection(_nearbyItemsCol).doc(itemUuid);
    final snap = await docRef.get();
    if (!snap.exists) return;

    await docRef.update({
      'isLent': isLent,
      'lentToName': lentToName,
      'lentToUid': lentToUid,
      'expectedReturnDate': expectedReturnDate != null
          ? Timestamp.fromDate(expectedReturnDate)
          : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Discovery ───────────────────────────────────────────────────────────

  /// Fetches nearby items from the same locality, excluding the current user's.
  Future<List<NearbyItem>> fetchNearbyItems(String locality) async {
    final user = _currentUser;
    if (user == null) return const [];

    final snap = await _firestore
        .collection(_nearbyItemsCol)
        .where('locality', isEqualTo: locality)
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .get();

    return snap.docs
        .map((doc) => NearbyItem.fromFirestore(doc))
        .where((item) => item.ownerUid != user.uid)
        .toList();
  }

  // ── Borrow requests ─────────────────────────────────────────────────────

  /// Creates a borrow request for a nearby item.
  Future<String> createBorrowRequest({
    required NearbyItem item,
    DateTime? requestedReturnDate,
    String? note,
  }) async {
    final user = _currentUser;
    if (user == null) throw StateError('Sign in to send borrow requests');

    if (item.ownerUid == user.uid) {
      throw StateError('You cannot borrow your own item');
    }

    // Check for existing pending request from this user for this item.
    final existing = await _firestore
        .collection(_nearbyRequestsCol)
        .where('itemUuid', isEqualTo: item.itemUuid)
        .where('requesterUid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw StateError('You already have a pending request for this item');
    }

    final now = FieldValue.serverTimestamp();
    final docRef = _firestore.collection(_nearbyRequestsCol).doc();
    await docRef.set({
      'itemUuid': item.itemUuid,
      'itemName': item.name,
      'ownerUid': item.ownerUid,
      'ownerName': item.ownerName,
      'requesterUid': user.uid,
      'requesterName': user.displayName ?? user.email ?? 'Unknown',
      'requesterLocality': item.locality,
      'status': 'pending',
      'requestedAt': now,
      'respondedAt': null,
      'requestedReturnDate': requestedReturnDate != null
          ? Timestamp.fromDate(requestedReturnDate)
          : null,
      'note': note,
      'source': 'nearby',
    });

    return docRef.id;
  }

  /// Approves a nearby borrow request.
  Future<void> approveBorrowRequest(String requestId) async {
    await _firestore.collection(_nearbyRequestsCol).doc(requestId).update({
      'status': 'approved',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Denies a nearby borrow request.
  Future<void> denyBorrowRequest(String requestId) async {
    await _firestore.collection(_nearbyRequestsCol).doc(requestId).update({
      'status': 'denied',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Cancels a nearby borrow request (called by requester).
  Future<void> cancelBorrowRequest(String requestId) async {
    await _firestore.collection(_nearbyRequestsCol).doc(requestId).update({
      'status': 'cancelled',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks a nearby item as returned.
  Future<void> markItemReturned(String itemUuid) async {
    // Update the item's lent status.
    await updateLentStatus(itemUuid: itemUuid, isLent: false);

    // Mark all approved requests for this item as returned.
    final user = _currentUser;
    if (user == null) return;

    final requests = await _firestore
        .collection(_nearbyRequestsCol)
        .where('itemUuid', isEqualTo: itemUuid)
        .where('ownerUid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'approved')
        .get();

    for (final doc in requests.docs) {
      await doc.reference.update({
        'status': 'returned',
        'respondedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── Request queries ─────────────────────────────────────────────────────

  /// Fetches incoming nearby borrow requests (where current user is owner).
  Future<List<Map<String, dynamic>>> fetchIncomingRequests() async {
    final user = _currentUser;
    if (user == null) return const [];

    final snap = await _firestore
        .collection(_nearbyRequestsCol)
        .where('ownerUid', isEqualTo: user.uid)
        .orderBy('requestedAt', descending: true)
        .limit(50)
        .get();

    return snap.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  /// Fetches outgoing nearby borrow requests (where current user is requester).
  Future<List<Map<String, dynamic>>> fetchOutgoingRequests() async {
    final user = _currentUser;
    if (user == null) return const [];

    final snap = await _firestore
        .collection(_nearbyRequestsCol)
        .where('requesterUid', isEqualTo: user.uid)
        .orderBy('requestedAt', descending: true)
        .limit(50)
        .get();

    return snap.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }
}
