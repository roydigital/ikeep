class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.householdId,
  });

  final String uid;
  final String email;
  final String? displayName;
  final String? householdId;

  factory AppUser.fromJson(String uid, Map<String, dynamic> json) {
    return AppUser(
      uid: uid,
      email: (json['email'] as String? ?? '').trim().toLowerCase(),
      displayName: (json['displayName'] as String?)?.trim(),
      householdId: (json['householdId'] as String?)?.trim(),
    );
  }
}
