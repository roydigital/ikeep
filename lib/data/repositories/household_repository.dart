import '../../core/errors/failure.dart';
import '../../domain/models/household_member.dart';

abstract class HouseholdRepository {
  Future<List<HouseholdMember>> getAllMembers();
  Future<Failure?> inviteMember({
    required String name,
    required String email,
  });
}
