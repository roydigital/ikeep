import 'package:sqflite/sqflite.dart';

import '../../core/errors/failure.dart';
import '../../core/utils/uuid_generator.dart';
import '../../domain/models/borrow_request.dart';
import '../../domain/models/household_member.dart';
import '../../domain/models/item.dart';
import '../../domain/models/item_location_history.dart';
import '../database/borrow_request_dao.dart';
import '../database/history_dao.dart';
import '../database/item_dao.dart';
import 'borrow_request_repository.dart';

class BorrowRequestRepositoryImpl implements BorrowRequestRepository {
  BorrowRequestRepositoryImpl({
    required this.borrowRequestDao,
    required this.itemDao,
    required this.historyDao,
  });

  final BorrowRequestDao borrowRequestDao;
  final ItemDao itemDao;
  final HistoryDao historyDao;

  @override
  Future<Failure?> createBorrowRequest({
    required Item item,
    required HouseholdMember requester,
    DateTime? requestedReturnDate,
    String? note,
  }) async {
    try {
      if (!item.isAvailableForLending) {
        return Failure('This item is private and not available to borrow yet.');
      }
      if (item.isLent) {
        return Failure('This item is currently lent out.');
      }
      if (requester.uuid == HouseholdMember.localOwnerUuid) {
        return Failure('Switch to a household member to request this item.');
      }

      final existingPending = await borrowRequestDao
          .getPendingRequestForItemByRequester(item.uuid, requester.uuid);
      if (existingPending != null) {
        return Failure('A request is already pending for this item.');
      }

      await borrowRequestDao.insertRequest(
        BorrowRequest(
          uuid: generateUuid(),
          itemUuid: item.uuid,
          ownerMemberUuid: HouseholdMember.localOwnerUuid,
          ownerMemberName: HouseholdMember.localOwnerName,
          requesterMemberUuid: requester.uuid,
          requesterMemberName: requester.name,
          status: BorrowRequestStatus.pending,
          requestedAt: DateTime.now(),
          requestedReturnDate: requestedReturnDate,
          note: note,
        ),
      );
      return null;
    } on DatabaseException catch (e) {
      return Failure('Failed to create borrow request', e);
    } catch (e) {
      return Failure('Failed to create borrow request', e);
    }
  }

  @override
  Future<Failure?> approveRequest(
    String requestUuid, {
    HouseholdMember? actedBy,
  }) async {
    try {
      final request = await borrowRequestDao.getRequestByUuid(requestUuid);
      if (request == null) return Failure('Borrow request not found.');
      if (!request.isPending) {
        return Failure('This request has already been handled.');
      }

      final item = await itemDao.getItemByUuid(request.itemUuid);
      if (item == null) return Failure('Item not found.');
      if (!item.isAvailableForLending) {
        return Failure('This item is no longer shared in your lend catalog.');
      }
      if (item.isLent) return Failure('This item has already been lent out.');

      final now = DateTime.now();
      final actor = actedBy ?? HouseholdMember.localOwner();

      await borrowRequestDao.updateRequest(
        request.copyWith(
          status: BorrowRequestStatus.approved,
          respondedAt: now,
        ),
      );
      await borrowRequestDao.resolvePendingRequestsForItem(
        request.itemUuid,
        status: BorrowRequestStatus.denied,
        respondedAt: now,
        exceptRequestUuid: request.uuid,
        note: 'Another borrow request was approved first.',
      );

      await itemDao.updateItem(
        item.copyWith(
          isLent: true,
          lentTo: request.requesterMemberName,
          lentOn: now,
          expectedReturnDate: request.requestedReturnDate,
          updatedAt: now,
        ),
      );

      await historyDao.insertHistory(
        ItemLocationHistory(
          uuid: generateUuid(),
          itemUuid: item.uuid,
          locationName: 'Lent to ${request.requesterMemberName}',
          movedAt: now,
          movedByMemberUuid: actor.uuid,
          movedByName: actor.name,
          note: 'Approved from Lend & Borrow Network',
        ),
      );
      return null;
    } on DatabaseException catch (e) {
      return Failure('Failed to approve borrow request', e);
    } catch (e) {
      return Failure('Failed to approve borrow request', e);
    }
  }

  @override
  Future<Failure?> denyRequest(
    String requestUuid, {
    HouseholdMember? actedBy,
  }) async {
    try {
      final request = await borrowRequestDao.getRequestByUuid(requestUuid);
      if (request == null) return Failure('Borrow request not found.');
      if (!request.isPending) {
        return Failure('This request has already been handled.');
      }

      await borrowRequestDao.updateRequest(
        request.copyWith(
          status: BorrowRequestStatus.denied,
          respondedAt: DateTime.now(),
        ),
      );
      return null;
    } on DatabaseException catch (e) {
      return Failure('Failed to deny borrow request', e);
    } catch (e) {
      return Failure('Failed to deny borrow request', e);
    }
  }

  @override
  Future<Failure?> cancelRequest(
    String requestUuid, {
    HouseholdMember? actedBy,
  }) async {
    try {
      final request = await borrowRequestDao.getRequestByUuid(requestUuid);
      if (request == null) return Failure('Borrow request not found.');
      if (!request.isPending) {
        return Failure('This request can no longer be cancelled.');
      }

      await borrowRequestDao.updateRequest(
        request.copyWith(
          status: BorrowRequestStatus.cancelled,
          respondedAt: DateTime.now(),
        ),
      );
      return null;
    } on DatabaseException catch (e) {
      return Failure('Failed to cancel borrow request', e);
    } catch (e) {
      return Failure('Failed to cancel borrow request', e);
    }
  }

  @override
  Future<BorrowRequest?> getRequest(String requestUuid) {
    return borrowRequestDao.getRequestByUuid(requestUuid);
  }

  @override
  Future<List<BorrowRequest>> getIncomingRequests(String ownerMemberUuid) {
    return borrowRequestDao.getRequestsForOwner(ownerMemberUuid);
  }

  @override
  Future<List<BorrowRequest>> getOutgoingRequests(String requesterMemberUuid) {
    return borrowRequestDao.getRequestsForRequester(requesterMemberUuid);
  }

  @override
  Future<List<BorrowRequest>> getRequestsForItem(String itemUuid) {
    return borrowRequestDao.getRequestsForItem(itemUuid);
  }
}
