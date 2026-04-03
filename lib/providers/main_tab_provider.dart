import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the currently active main tab in [MainScreen].
///
/// 0 = Items (Home), 1 = Locations (Rooms), 2 = Search, 3 = Settings.
final mainTabProvider = StateProvider<int>((ref) => 0);

/// Tracks the previously active tab so screens like Settings can navigate
/// "back" to the tab the user came from.
final previousTabProvider = StateProvider<int>((ref) => 0);

/// When `true`, the Search tab should activate its "Recent" filter to show
/// all items sorted by recency. Set by "View All" on the Home screen's
/// "Recently Saved" section; consumed and cleared by [SearchScreen].
final viewAllRecentRequestedProvider = StateProvider<bool>((ref) => false);
