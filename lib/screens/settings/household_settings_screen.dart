import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/household_member.dart';
import '../../providers/household_providers.dart';
import '../../theme/app_colors.dart';

class HouseholdSettingsScreen extends ConsumerStatefulWidget {
  const HouseholdSettingsScreen({super.key});

  @override
  ConsumerState<HouseholdSettingsScreen> createState() =>
      _HouseholdSettingsScreenState();
}

class _HouseholdSettingsScreenState
    extends ConsumerState<HouseholdSettingsScreen> {
  final TextEditingController _householdNameController =
      TextEditingController();
  final TextEditingController _memberNameController = TextEditingController();
  final TextEditingController _memberEmailController = TextEditingController();

  @override
  void dispose() {
    _householdNameController.dispose();
    _memberNameController.dispose();
    _memberEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final card = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final householdAsync = ref.watch(currentHouseholdProvider);
    final membersAsync = ref.watch(householdMembersProvider);
    final actionState = ref.watch(householdNotifierProvider);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Family Shared Pool'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _HeroCard(
              cardColor: card,
              borderColor: border,
              titleColor: textPrimary,
              bodyColor: textSecondary,
            ),
            const SizedBox(height: 18),
            householdAsync.when(
              data: (household) {
                if (household == null) {
                  return _CreateHouseholdCard(
                    cardColor: card,
                    borderColor: border,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    controller: _householdNameController,
                    isLoading: actionState.isLoading,
                    onCreate: _createHousehold,
                  );
                }

                return Column(
                  children: [
                    _HouseholdSummaryCard(
                      cardColor: card,
                      borderColor: border,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      householdName: household.name,
                      householdId: household.householdId,
                      ownerId: household.ownerId,
                      memberCount: household.memberIds.length,
                    ),
                    const SizedBox(height: 18),
                    _AddMemberCard(
                      cardColor: card,
                      borderColor: border,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      nameController: _memberNameController,
                      emailController: _memberEmailController,
                      isSubmitting: actionState.isLoading,
                      onAdd: _addMember,
                      onReset: _resetMemberLookupForm,
                    ),
                    const SizedBox(height: 18),
                    _MembersCard(
                      cardColor: card,
                      borderColor: border,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      membersAsync: membersAsync,
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
              error: (error, _) => _ErrorCard(
                cardColor: card,
                borderColor: border,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                message: '$error',
              ),
            ),
            if (actionState.lastError != null) ...[
              const SizedBox(height: 18),
              _InlineError(
                message: actionState.lastError!,
                isDark: isDark,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _createHousehold() async {
    final name = _householdNameController.text.trim();
    if (name.isEmpty) {
      _showSnackBar('Enter a household name.');
      return;
    }

    final error = await ref
        .read(householdNotifierProvider.notifier)
        .createHousehold(name: name);
    if (!mounted) return;

    if (error != null) {
      _showSnackBar(error);
      return;
    }

    _householdNameController.clear();
    _showSnackBar('Household created.');
  }

  Future<void> _addMember() async {
    final lookupState = ref.read(householdMemberLookupProvider);
    final userId = lookupState.foundUserId;
    if (userId == null || userId.isEmpty) {
      _showSnackBar('Search for a valid Ikeep account first.');
      return;
    }

    final assignedDisplayName = _memberNameController.text.trim();
    if (assignedDisplayName.isEmpty) {
      _showSnackBar('Enter a relationship or display name.');
      return;
    }

    final error = await ref.read(householdNotifierProvider.notifier).addMember(
          userId: userId,
          name: assignedDisplayName,
          email: lookupState.foundUser?.email ?? lookupState.searchedEmail,
        );
    if (!mounted) return;

    if (error != null) {
      _showSnackBar(error);
      return;
    }

    _resetMemberLookupForm(clearEmail: true);
    _showSnackBar('Member added to household.');
  }

  void _resetMemberLookupForm({bool clearEmail = false}) {
    ref.read(householdMemberLookupProvider.notifier).resetForm();
    _memberNameController.clear();
    if (clearEmail) {
      _memberEmailController.clear();
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.cardColor,
    required this.borderColor,
    required this.titleColor,
    required this.bodyColor,
  });

  final Color cardColor;
  final Color borderColor;
  final Color titleColor;
  final Color bodyColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Household collaboration',
            style: TextStyle(
              color: titleColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a household, add family members, and keep selected inventory items synchronized across everyone in the pool.',
            style: TextStyle(
              color: bodyColor,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateHouseholdCard extends StatelessWidget {
  const _CreateHouseholdCard({
    required this.cardColor,
    required this.borderColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.controller,
    required this.isLoading,
    required this.onCreate,
  });

  final Color cardColor;
  final Color borderColor;
  final Color textPrimary;
  final Color textSecondary;
  final TextEditingController controller;
  final bool isLoading;
  final Future<void> Function() onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create your household',
            style: TextStyle(
              color: textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Example: The Smiths, Flat 7B, Weekend House',
            style: TextStyle(color: textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Household name',
              hintText: 'The Smiths',
            ),
            onSubmitted: (_) => onCreate(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isLoading ? null : onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(52),
              ),
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_home_work_rounded),
              label: const Text('Create Household'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HouseholdSummaryCard extends StatelessWidget {
  const _HouseholdSummaryCard({
    required this.cardColor,
    required this.borderColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.householdName,
    required this.householdId,
    required this.ownerId,
    required this.memberCount,
  });

  final Color cardColor;
  final Color borderColor;
  final Color textPrimary;
  final Color textSecondary;
  final String householdName;
  final String householdId;
  final String ownerId;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  householdName,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$memberCount member${memberCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MetaRow(label: 'Household ID', value: householdId, color: textSecondary),
          const SizedBox(height: 8),
          _MetaRow(label: 'Owner ID', value: ownerId, color: textSecondary),
        ],
      ),
    );
  }
}

class _AddMemberCard extends ConsumerWidget {
  const _AddMemberCard({
    required this.cardColor,
    required this.borderColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.nameController,
    required this.emailController,
    required this.isSubmitting,
    required this.onAdd,
    required this.onReset,
  });

  final Color cardColor;
  final Color borderColor;
  final Color textPrimary;
  final Color textSecondary;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final bool isSubmitting;
  final Future<void> Function() onAdd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookupState = ref.watch(householdMemberLookupProvider);
    final lookupController = ref.read(householdMemberLookupProvider.notifier);
    final hasFoundUser = lookupState.hasFoundUser;
    final hasError =
        lookupState.errorMessage != null && lookupState.errorMessage!.isNotEmpty;
    final canSearch = !lookupState.isLoading && !hasFoundUser && !isSubmitting;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add family member',
            style: TextStyle(
              color: textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Search for an existing Ikeep account by email, then assign how they should appear inside your household.',
            style: TextStyle(color: textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: emailController,
            readOnly: hasFoundUser,
            enabled: !isSubmitting,
            keyboardType: TextInputType.emailAddress,
            textInputAction:
                hasFoundUser ? TextInputAction.next : TextInputAction.search,
            onChanged: (_) {
              if (lookupState.searchedEmail.isNotEmpty) {
                nameController.clear();
                lookupController.resetForm();
              }
            },
            onSubmitted: (_) {
              if (canSearch && emailController.text.trim().isNotEmpty) {
                lookupController.searchUser(emailController.text);
              }
            },
            decoration: InputDecoration(
              labelText: 'Email address',
              hintText: 'family@example.com',
              suffixIcon: hasFoundUser
                  ? const Icon(Icons.verified_rounded, color: AppColors.success)
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          if (lookupState.isLoading)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: const Text('Verifying user...'),
              ),
            )
          else if (!hasFoundUser)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    canSearch ? () => lookupController.searchUser(emailController.text) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.search_rounded),
                label: const Text('Search User'),
              ),
            ),
          if (hasError) ...[
            const SizedBox(height: 12),
            _LookupMessage(
              icon: Icons.error_outline_rounded,
              message: lookupState.errorMessage!,
              color: AppColors.error,
              textPrimary: textPrimary,
            ),
          ],
          if (hasFoundUser) ...[
            const SizedBox(height: 12),
            _LookupMessage(
              icon: Icons.check_circle_rounded,
              message: lookupState.foundUser?.displayName?.trim().isNotEmpty == true
                  ? 'User found: ${lookupState.foundUser!.displayName}'
                  : 'User found!',
              color: AppColors.success,
              textPrimary: textPrimary,
              trailing: TextButton(
                onPressed: isSubmitting
                    ? null
                    : () {
                        onReset();
                        emailController.clear();
                      },
                child: const Text('Search another'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              enabled: !isSubmitting,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!isSubmitting && nameController.text.trim().isNotEmpty) {
                  onAdd();
                }
              },
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'Mom, Dad, Sister',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isSubmitting ? null : onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add To Household'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LookupMessage extends StatelessWidget {
  const _LookupMessage({
    required this.icon,
    required this.message,
    required this.color,
    required this.textPrimary,
    this.trailing,
  });

  final IconData icon;
  final String message;
  final Color color;
  final Color textPrimary;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _MembersCard extends StatelessWidget {
  const _MembersCard({
    required this.cardColor,
    required this.borderColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.membersAsync,
  });

  final Color cardColor;
  final Color borderColor;
  final Color textPrimary;
  final Color textSecondary;
  final AsyncValue<List<HouseholdMember>> membersAsync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Members',
            style: TextStyle(
              color: textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          membersAsync.when(
            data: (members) {
              if (members.isEmpty) {
                return Text(
                  'No members yet.',
                  style: TextStyle(color: textSecondary),
                );
              }

              return Column(
                children: members
                    .map(
                      (member) => _MemberTile(
                        member: member,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
            error: (error, _) => Text(
              'Could not load members: $error',
              style: TextStyle(color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.textPrimary,
    required this.textSecondary,
  });

  final HouseholdMember member;
  final Color textPrimary;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.14),
            foregroundColor: AppColors.primary,
            child: Text(
              member.name.isEmpty ? '?' : member.name.characters.first.toUpperCase(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (member.email?.isNotEmpty ?? false)
                  Text(
                    member.email!,
                    style: TextStyle(color: textSecondary, fontSize: 13),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: member.isOwner
                  ? AppColors.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              member.isOwner ? 'Owner' : 'Member',
              style: TextStyle(
                color: member.isOwner ? AppColors.primary : textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      '$label: $value',
      style: TextStyle(color: color, height: 1.35),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({
    required this.message,
    required this.isDark,
  });

  final String message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.cardColor,
    required this.borderColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.message,
  });

  final Color cardColor;
  final Color borderColor;
  final Color textPrimary;
  final Color textSecondary;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Household unavailable',
            style: TextStyle(
              color: textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: textSecondary)),
        ],
      ),
    );
  }
}
