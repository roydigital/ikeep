import '../../core/errors/failure.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/household.dart';
import '../../domain/models/household_member.dart';

abstract class HouseholdRepository {
  Future<Household?> getCurrentHousehold();
  Future<Household?> getHousehold(String householdId);
  Future<AppUser?> getUserByEmail(String email);
  Future<Failure?> createHousehold({required String name});
  Future<List<HouseholdMember>> getAllMembers();
  Future<Failure?> addMember({
    required String householdId,
    required String userId,
    String? name,
    String? email,
  });
}
