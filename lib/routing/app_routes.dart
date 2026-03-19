/// All named route paths for the app.
/// Import this in both [AppRouter] and any widget that navigates.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String save = '/save';
  static const String itemDetail = '/item/:uuid';
  static const String rooms = '/rooms';
  static const String settings = '/settings';
  static const String manageFamily = '/settings/manage-family';
  static const String search = '/search';

  /// Constructs the [itemDetail] path with the given [uuid].
  static String itemDetailPath(String uuid) => '/item/$uuid';
}
