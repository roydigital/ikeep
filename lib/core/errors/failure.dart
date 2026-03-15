import 'app_exception.dart';

/// Value object used at the repository boundary instead of throwing exceptions.
/// Providers receive [Failure] values via AsyncError and surface them to the UI.
class Failure {
  const Failure(this.message, [this.cause]);

  /// Factory from any [AppException].
  factory Failure.fromException(AppException e) =>
      Failure(e.message, e);

  final String message;
  final Object? cause;

  @override
  String toString() => 'Failure($message)';
}
