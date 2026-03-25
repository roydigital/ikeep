import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the currently active main tab in [MainScreen].
///
/// 0 = Items (Home), 1 = Locations (Rooms), 2 = Search, 3 = Settings.
final mainTabProvider = StateProvider<int>((ref) => 0);
