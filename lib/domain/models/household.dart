import 'dart:convert';

class Household {
  const Household({
    required this.householdId,
    required this.ownerId,
    required this.name,
    this.memberIds = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String householdId;
  final String ownerId;
  final String name;
  final List<String> memberIds;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Household copyWith({
    String? householdId,
    String? ownerId,
    String? name,
    List<String>? memberIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Household(
      householdId: householdId ?? this.householdId,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'household_id': householdId,
      'owner_id': ownerId,
      'name': name,
      'member_ids': jsonEncode(memberIds),
      'created_at': createdAt?.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
    };
  }

  factory Household.fromMap(Map<String, dynamic> map) {
    return Household(
      householdId: map['household_id'] as String? ?? map['householdId'] as String,
      ownerId: map['owner_id'] as String? ?? map['ownerId'] as String,
      name: map['name'] as String,
      memberIds: List<String>.from(
        jsonDecode((map['member_ids'] as String?) ?? '[]') as List,
      ),
      createdAt: _fromDynamicDate(map['created_at'] ?? map['createdAt']),
      updatedAt: _fromDynamicDate(map['updated_at'] ?? map['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'householdId': householdId,
      'ownerId': ownerId,
      'name': name,
      'members': memberIds,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory Household.fromJson(Map<String, dynamic> json) {
    return Household(
      householdId: json['householdId'] as String,
      ownerId: json['ownerId'] as String,
      name: json['name'] as String,
      memberIds: List<String>.from(
        json['members'] as List<dynamic>? ?? const <dynamic>[],
      ),
      createdAt: _fromDynamicDate(json['createdAt']),
      updatedAt: _fromDynamicDate(json['updatedAt']),
    );
  }

  static DateTime? _fromDynamicDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }
}
