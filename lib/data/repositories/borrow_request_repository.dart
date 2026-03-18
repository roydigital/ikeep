import '../../core/errors/failure.dart';
import '../../domain/models/borrow_request.dart';
import '../../domain/models/household_member.dart';
import '../../domain/models/item.dart';

abstract class BorrowRequestRepository {
  Future<Failure?> createBorrowRequest({
    required Item item,
    required HouseholdMember requester,
    DateTime? requestedReturnDate,
    String? note,
  });

  Future<Failure?> approveRequest(
    String requestUuid, {
    HouseholdMember? actedBy,
  });

  Future<Failure?> denyRequest(
    String requestUuid, {
    HouseholdMember? actedBy,
  });

  Future<Failure?> cancelRequest(
    String requestUuid, {
    HouseholdMember? actedBy,
  });

  Future<BorrowRequest?> getRequest(String requestUuid);

  Future<List<BorrowRequest>> getIncomingRequests(String ownerMemberUuid);

  Future<List<BorrowRequest>> getOutgoingRequests(String requesterMemberUuid);

  Future<List<BorrowRequest>> getRequestsForItem(String itemUuid);
}
