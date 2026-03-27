import 'dart:typed_data';

/// Lightweight metadata for a single media asset stored in cloud storage.
///
/// This contract is intentionally UI-agnostic. The current app still uses
/// legacy `imagePaths` and `invoicePath` fields for rendering/opening media,
/// while this descriptor is written alongside them to support the later
/// metadata-first restore and lazy media phases.
class CloudMediaDescriptor {
  const CloudMediaDescriptor({
    required this.storagePath,
    this.thumbnailPath,
    required this.mimeType,
    required this.byteSize,
    this.contentHash,
    required this.version,
    required this.updatedAt,
  });

  final String storagePath;
  final String? thumbnailPath;
  final String mimeType;
  final int byteSize;
  final String? contentHash;
  final int version;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'storagePath': storagePath,
      'thumbnailPath': thumbnailPath,
      'mimeType': mimeType,
      'byteSize': byteSize,
      'contentHash': contentHash,
      'version': version,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory CloudMediaDescriptor.fromJson(Map<String, dynamic> json) {
    return CloudMediaDescriptor(
      storagePath: json['storagePath'] as String? ?? '',
      thumbnailPath: json['thumbnailPath'] as String?,
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      byteSize: (json['byteSize'] as num?)?.toInt() ?? 0,
      contentHash: json['contentHash'] as String?,
      version: (json['version'] as num?)?.toInt() ?? 1,
      updatedAt: _parseDateTime(json['updatedAt']) ?? DateTime.now().toUtc(),
    );
  }

  CloudMediaDescriptor copyWith({
    String? storagePath,
    String? thumbnailPath,
    String? mimeType,
    int? byteSize,
    String? contentHash,
    int? version,
    DateTime? updatedAt,
    bool clearThumbnailPath = false,
    bool clearContentHash = false,
  }) {
    return CloudMediaDescriptor(
      storagePath: storagePath ?? this.storagePath,
      thumbnailPath: clearThumbnailPath
          ? null
          : (thumbnailPath ?? this.thumbnailPath),
      mimeType: mimeType ?? this.mimeType,
      byteSize: byteSize ?? this.byteSize,
      contentHash:
          clearContentHash ? null : (contentHash ?? this.contentHash),
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}

/// Stable, dependency-free content hashing for media metadata.
///
/// This is not used for security. It is a lightweight fingerprint so later
/// phases can invalidate cached files without depending on expiring URLs.
class CloudMediaHashing {
  const CloudMediaHashing._();

  static String hashBytes(Uint8List bytes) {
    const int fnvOffset = 0xcbf29ce484222325;
    const int fnvPrime = 0x100000001b3;
    var hash = fnvOffset;

    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * fnvPrime) & 0xffffffffffffffff;
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }
}
