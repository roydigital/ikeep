/// Controls who can see an item in the lending catalog.
enum ItemVisibility {
  /// Only visible on the owner's device. Default.
  private_('private'),

  /// Visible to all members in the active household pool.
  household('household');

  const ItemVisibility(this.value);
  final String value;

  static ItemVisibility fromString(String? s) {
    return ItemVisibility.values.firstWhere(
      (e) => e.value == s,
      orElse: () => ItemVisibility.private_,
    );
  }

  bool get isHousehold => this == ItemVisibility.household;
  bool get isPrivate => this == ItemVisibility.private_;
}
