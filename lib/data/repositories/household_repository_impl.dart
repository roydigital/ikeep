import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/errors/failure.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/household.dart';
import '../../domain/models/household_member.dart';
import '../database/household_dao.dart';
import '../database/household_member_dao.dart';
import '../../services/household_cloud_service.dart';
import 'household_repository.dart';

class HouseholdRepositoryImpl implements HouseholdRepository {
  HouseholdRepositoryImpl({
    required this.householdDao,
    required this.memberDao,
    required this.cloudService,
  });

  final HouseholdDao householdDao;
  final HouseholdMemberDao memberDao;
  final HouseholdCloudService cloudService;

  @override
  Future<AppUser?> getUserByEmail(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw const FormatException('Email is required');
    }

    try {
      return await cloudService.getUserByEmail(normalizedEmail);
    } on FirebaseAuthException catch (e) {
      throw StateError(e.message ?? 'Authentication failed: ${e.code}');
    } on FirebaseException catch (e) {
      throw StateError(e.message ?? 'Cloud lookup failed: ${e.code}');
    }
  }

  @override
  Future<Household?> getCurrentHousehold() async {
    try {
      final householdId = await cloudService.getUserHouseholdId();
      if (householdId == null || householdId.isEmpty) {
        return householdDao.getLatestHousehold();
      }

      final remote = await cloudService.fetchHousehold(householdId);
      if (remote != null) {
        await householdDao.upsertHousehold(remote);
        return remote;
      }
    } on FirebaseAuthException {
      // Fall back to local cache.
    } on FirebaseException {
      // Fall back to local cache.
    } catch (_) {
      // Fall back to local cache.
    }

    return householdDao.getLatestHousehold();
  }

  @override
  Future<Household?> getHousehold(String householdId) async {
    try {
      final remote = await cloudService.fetchHousehold(householdId);
      if (remote != null) {
        await householdDao.upsertHousehold(remote);
        return remote;
      }
    } catch (_) {
      // Fall back to local cache below.
    }

    return householdDao.getHouseholdById(householdId);
  }

  @override
  Future<Failure?> createHousehold({required String name}) async {
    try {
      final household = await cloudService.createHousehold(name: name);
      await householdDao.upsertHousehold(household);
      await memberDao.ensureOwnerMember();
      return null;
    } on FirebaseAuthException catch (e) {
      return Failure(e.message ?? 'Authentication failed: ${e.code}', e);
    } on FirebaseException catch (e) {
      return Failure(e.message ?? 'Cloud sync failed: ${e.code}', e);
    } on StateError catch (e) {
      return Failure(e.message, e);
    } catch (e) {
      return Failure('Failed to create household: $e', e);
    }
  }

  @override
  Future<List<HouseholdMember>> getAllMembers() async {
    try {
      await memberDao.ensureOwnerMember();

      final household = await getCurrentHousehold();
      if (household == null) {
        return memberDao.getAllMembers();
      }

      final members = await cloudService.fetchMembers(household.householdId);
      if (members.isNotEmpty) {
        await memberDao.replaceAllMembers(members);
      }
      return memberDao.getAllMembers();
    } on FirebaseAuthException {
      return memberDao.getAllMembers();
    } on FirebaseException {
      return memberDao.getAllMembers();
    } catch (_) {
      return memberDao.getAllMembers();
    }
  }

  @override
  Future<Failure?> addMember({
    required String householdId,
    required String userId,
    String? name,
    String? email,
  }) async {
    try {
      await cloudService.addMemberByUserId(
        householdId: householdId,
        userId: userId,
        name: name,
        email: email,
      );

      final updatedHousehold = await cloudService.fetchHousehold(householdId);
      if (updatedHousehold != null) {
        await householdDao.upsertHousehold(updatedHousehold);
      }

      final members = await cloudService.fetchMembers(householdId);
      if (members.isNotEmpty) {
        await memberDao.replaceAllMembers(members);
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return Failure(e.message ?? 'Authentication failed: ${e.code}', e);
    } on FirebaseException catch (e) {
      return Failure(e.message ?? 'Cloud sync failed: ${e.code}', e);
    } on StateError catch (e) {
      return Failure(e.message, e);
    } catch (e) {
      return Failure('Failed to add household member: $e', e);
    }
  }
}
