import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Generates a new v4 UUID string. Isolates the uuid package import.
String generateUuid() => _uuid.v4();
