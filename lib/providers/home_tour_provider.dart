import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeTourKeys {
  const HomeTourKeys._();

  static const hasSeenHomeTour = 'has_seen_home_tour';
  static const hasSeenItemListingTour = 'has_seen_item_listing_tour';
  static const hasSeenRoomsTour = 'has_seen_rooms_tour';
  static const hasSeenSettingsTour = 'has_seen_settings_tour';
}

class HomeTourController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(HomeTourKeys.hasSeenHomeTour) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(HomeTourKeys.hasSeenHomeTour, true);
    state = const AsyncData(true);
  }
}

final homeTourControllerProvider =
    AsyncNotifierProvider<HomeTourController, bool>(HomeTourController.new);

class ItemListingTourController extends AutoDisposeAsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(HomeTourKeys.hasSeenItemListingTour) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(HomeTourKeys.hasSeenItemListingTour, true);
    state = const AsyncData(true);
  }
}

final itemListingTourControllerProvider =
    AsyncNotifierProvider.autoDispose<ItemListingTourController, bool>(
  ItemListingTourController.new,
);

class RoomsTourController extends AutoDisposeAsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(HomeTourKeys.hasSeenRoomsTour) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(HomeTourKeys.hasSeenRoomsTour, true);
    state = const AsyncData(true);
  }
}

final roomsTourControllerProvider =
    AsyncNotifierProvider.autoDispose<RoomsTourController, bool>(
  RoomsTourController.new,
);

class SettingsTourController extends AutoDisposeAsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(HomeTourKeys.hasSeenSettingsTour) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(HomeTourKeys.hasSeenSettingsTour, true);
    state = const AsyncData(true);
  }
}

final settingsTourControllerProvider =
    AsyncNotifierProvider.autoDispose<SettingsTourController, bool>(
  SettingsTourController.new,
);
