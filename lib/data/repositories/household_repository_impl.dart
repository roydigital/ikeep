import 'dart:async';

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
    final localHousehold = await householdDao.getLatestHousehold();
    try {
      final householdId = await cloudService.getUserHouseholdId();
      if (householdId == null || householdId.isEmpty) {
        return localHousehold;
      }

      if (localHousehold != null && localHousehold.householdId == householdId) {
        unawaited(_refreshHouseholdCache(householdId));
        return localHousehold;
      }

      final remote = await _refreshHouseholdCache(householdId);
      if (remote != null) {
        return remote;
      }
    } on FirebaseAuthException {
      // Fall back to local cache.
    } on FirebaseException {
      // Fall back to local cache.
    } catch (_) {
      // Fall back to local cache.
    }

    return localHousehold;
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
      final user = cloudService.currentUser;
      if (user != null) {
        final now = DateTime.now();
        await memberDao.insertMember(
          HouseholdMember(
            uuid: user.uid,
            name: _resolveCurrentUserName(user),
            invitedAt: now,
            isOwner: true,
            email: user.email,
            householdId: household.householdId,
            joinedAt: now,
          ),
        );
        await memberDao.removeLocalOwnerPlaceholderIfRealOwnerExists();
      } else {
        await memberDao.ensureOwnerMember();
      }
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
      // Drop the legacy `owner-local` placeholder if a real owner row already
      // exists — otherwise the Members list shows a duplicate "Owner" tile.
      await memberDao.removeLocalOwnerPlaceholderIfRealOwnerExists();
      await memberDao.ensureOwnerMember();
      final household = await getCurrentHousehold();
      final localMembers = await memberDao.getAllMembers();
      if (household == null) {
        return localMembers;
      }

      final hasCachedMembers = localMembers.any(
        (member) => member.householdId == household.householdId,
      );
      if (hasCachedMembers) {
        unawaited(_refreshMembersCache(household.householdId));
        return localMembers;
      }

      final members = await _refreshMembersCache(household.householdId);
      return members.isNotEmpty ? members : localMembers;
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
      await _cacheAddedMember(
        householdId: householdId,
        userId: userId,
        name: name,
        email: email,
      );
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

  Future<Household?> _refreshHouseholdCache(String householdId) async {
    final remote = await cloudService.fetchHousehold(householdId);
    if (remote != null) {
      await householdDao.upsertHousehold(remote);
    }
    return remote;
  }

  Future<List<HouseholdMember>> _refreshMembersCache(String householdId) async {
    final members = await cloudService.fetchMembers(householdId);
    if (members.isNotEmpty) {
      await memberDao.replaceAllMembers(members);
      return memberDao.getAllMembers();
    }
    return memberDao.getAllMembers();
  }

  Future<void> _cacheAddedMember({
    required String householdId,
    required String userId,
    String? name,
    String? email,
  }) async {
    final latestHousehold = await householdDao.getLatestHousehold();
    final cachedHousehold =
        await householdDao.getHouseholdById(householdId) ??
            (latestHousehold?.householdId == householdId
                ? latestHousehold
                : null);
    if (cachedHousehold != null) {
      final nextMemberIds = <String>{
        ...cachedHousehold.memberIds,
        userId,
      }.toList();
      await householdDao.upsertHousehold(
        cachedHousehold.copyWith(
          memberIds: nextMemberIds,
          updatedAt: DateTime.now(),
        ),
      );
    }

    final now = DateTime.now();
    final memberName = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()
        : (email?.trim().isNotEmpty ?? false)
            ? email!.trim()
            : 'Member';
    await memberDao.insertMember(
      HouseholdMember(
        uuid: userId,
        name: memberName,
        invitedAt: now,
        isOwner: false,
        email: email?.trim().toLowerCase(),
        householdId: householdId,
        joinedAt: now,
      ),
    );
  }

  String _resolveCurrentUserName(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }
    return 'You';
  }
}
