/// Controls who can see an item in the lending catalog.
enum ItemVisibility {
  /// Only visible on the owner's device. Default.
  private_('private');

  const ItemVisibility(this.value);
  final String value;

  static ItemVisibility fromString(String? s) {
    return ItemVisibility.values.firstWhere(
      (e) => e.value == s,
      orElse: () => ItemVisibility.private_,
    );
  }
}
