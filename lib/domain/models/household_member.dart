class HouseholdMember {
  static const String localOwnerUuid = 'owner-local';
  static const String localOwnerName = 'You';

  const HouseholdMember({
    required this.uuid,
    required this.name,
    required this.invitedAt,
    this.isOwner = false,
  });

  final String uuid;
  final String name;
  final DateTime invitedAt;
  final bool isOwner;

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
    };
  }

  factory HouseholdMember.fromMap(Map<String, dynamic> map) {
    return HouseholdMember(
      uuid: map['uuid'] as String,
      name: map['name'] as String,
      invitedAt: DateTime.fromMillisecondsSinceEpoch(map['invited_at'] as int),
      isOwner: (map['is_owner'] as int? ?? 0) == 1,
    );
  }
}
