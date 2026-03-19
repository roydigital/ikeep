class HouseholdMember {
  static const String localOwnerUuid = 'owner-local';
  static const String localOwnerName = 'You';

  const HouseholdMember({
    required this.uuid,
    required this.name,
    required this.invitedAt,
    this.isOwner = false,
    this.email,
    this.householdId,
    this.joinedAt,
  });

  final String uuid;
  final String name;
  final DateTime invitedAt;
  final bool isOwner;
  final String? email;
  final String? householdId;
  final DateTime? joinedAt;

  static HouseholdMember localOwner() {
    return HouseholdMember(
      uuid: localOwnerUuid,
      name: localOwnerName,
      invitedAt: DateTime.now(),
      isOwner: true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'name': name,
      'invited_at': invitedAt.millisecondsSinceEpoch,
      'is_owner': isOwner ? 1 : 0,
      'email': email,
      'household_uuid': householdId,
      'joined_at': joinedAt?.millisecondsSinceEpoch,
    };
  }

  factory HouseholdMember.fromMap(Map<String, dynamic> map) {
    return HouseholdMember(
      uuid: map['uuid'] as String,
      name: map['name'] as String,
      invitedAt: DateTime.fromMillisecondsSinceEpoch(map['invited_at'] as int),
      isOwner: (map['is_owner'] as int? ?? 0) == 1,
      email: map['email'] as String?,
      householdId:
          map['household_uuid'] as String? ?? map['householdId'] as String?,
      joinedAt: map['joined_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['joined_at'] as int)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': uuid,
      'name': name,
      'email': email,
      'householdId': householdId,
      'invitedAt': invitedAt.toIso8601String(),
      'joinedAt': joinedAt?.toIso8601String(),
      'isOwner': isOwner,
    };
  }

  factory HouseholdMember.fromJson(Map<String, dynamic> json) {
    return HouseholdMember(
      uuid: json['userId'] as String? ?? json['uuid'] as String,
      name: json['name'] as String,
      invitedAt: DateTime.tryParse(json['invitedAt'] as String? ?? '') ??
          DateTime.now(),
      isOwner: json['isOwner'] as bool? ?? false,
      email: json['email'] as String?,
      householdId: json['householdId'] as String?,
      joinedAt: DateTime.tryParse(json['joinedAt'] as String? ?? ''),
    );
  }
}
