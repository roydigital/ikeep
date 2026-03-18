import 'package:firebase_auth/firebase_auth.dart';

import '../../core/errors/failure.dart';
import '../database/household_member_dao.dart';
import '../../domain/models/household_member.dart';
import '../../services/household_cloud_service.dart';
import 'household_repository.dart';

class HouseholdRepositoryImpl implements HouseholdRepository {
  HouseholdRepositoryImpl({
    required this.memberDao,
    required this.cloudService,
  });

  final HouseholdMemberDao memberDao;
  final HouseholdCloudService cloudService;

  @override
  Future<List<HouseholdMember>> getAllMembers() async {
    try {
      await memberDao.ensureOwnerMember();

      final currentUser = cloudService.currentUser;
      if (currentUser == null) {
        return memberDao.getAllMembers();
      }

      final householdId = await cloudService.ensureCurrentUserHousehold();
      final members = await cloudService.fetchMembers(householdId);
      if (members.isNotEmpty) {
        await memberDao.replaceAllMembers(members);
      }
      return memberDao.getAllMembers();
    } on FirebaseAuthException {
      return memberDao.getAllMembers();
    } catch (_) {
      return memberDao.getAllMembers();
    }
  }

  @override
  Future<Failure?> inviteMember({
    required String name,
    required String email,
  }) async {
    try {
      await memberDao.ensureOwnerMember();
      final householdId = await cloudService.ensureCurrentUserHousehold();
      await cloudService.createInvite(
        householdId: householdId,
        invitedName: name,
        invitedEmail: email,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return Failure(e.message ?? 'Authentication failed: ${e.code}', e);
    } on FirebaseException catch (e) {
      return Failure(e.message ?? 'Cloud sync failed: ${e.code}', e);
    } on StateError catch (e) {
      return Failure(e.message, e);
    } catch (e) {
      return Failure('Failed to invite household member: $e', e);
    }
  }
}
