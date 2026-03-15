/// Sealed hierarchy for all typed errors in Ikeep.
sealed class AppException implements Exception {
  const AppException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message${cause != null ? ' (caused by: $cause)' : ''}';
}

class DatabaseException extends AppException {
  const DatabaseException(super.message, [super.cause]);
}

class SyncException extends AppException {
  const SyncException(super.message, [super.cause]);
}

class ImageException extends AppException {
  const ImageException(super.message, [super.cause]);
}

class PermissionException extends AppException {
  const PermissionException(super.message, [super.cause]);
}

class NotFoundItemException extends AppException {
  const NotFoundItemException(String uuid)
      : super('Item not found: $uuid');
}

class NotFoundLocationException extends AppException {
  const NotFoundLocationException(String uuid)
      : super('Location not found: $uuid');
}

class MlException extends AppException {
  const MlException(super.message, [super.cause]);
}
