import '../models/receiving_model.dart';

enum ConflictResolution { useServer, useLocal, merged }

class ConflictResult {
  final ConflictResolution resolution;
  final Map<String, dynamic> payload;  // final payload to push/keep
  final String message;

  const ConflictResult({
    required this.resolution,
    required this.payload,
    required this.message,
  });
}

class ConflictResolver {
  static final ConflictResolver _i = ConflictResolver._();
  factory ConflictResolver() => _i;
  ConflictResolver._();

  /// Last-write-wins strategy based on updatedAt timestamps.
  /// If server record is newer → discard local.
  /// If local record is newer → keep local (re-push).
  ConflictResult resolve({
    required Map<String, dynamic> localPayload,
    required Map<String, dynamic> serverRecord,
    required DateTime localUpdatedAt,
  }) {
    final serverUpdatedAtRaw = serverRecord['updated_at'] as String?;
    final serverUpdatedAt = serverUpdatedAtRaw != null
        ? DateTime.tryParse(serverUpdatedAtRaw)
        : null;

    // No server timestamp — local wins by default
    if (serverUpdatedAt == null) {
      return ConflictResult(
        resolution: ConflictResolution.useLocal,
        payload: localPayload,
        message: 'Server record has no timestamp. Local changes kept.',
      );
    }

    if (serverUpdatedAt.isAfter(localUpdatedAt)) {
      // Server is newer — discard local
      return ConflictResult(
        resolution: ConflictResolution.useServer,
        payload: serverRecord,
        message:
        'Server record is newer (updated ${serverUpdatedAt.toLocal()}). '
            'Local changes discarded.',
      );
    } else if (localUpdatedAt.isAfter(serverUpdatedAt)) {
      // Local is newer — push local to server
      return ConflictResult(
        resolution: ConflictResolution.useLocal,
        payload: localPayload,
        message: 'Local changes are newer. Pushing to server.',
      );
    } else {
      // Same timestamp — no conflict
      return ConflictResult(
        resolution: ConflictResolution.merged,
        payload: localPayload,
        message: 'No conflict detected.',
      );
    }
  }
}