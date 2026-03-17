// ignore: depend_on_referenced_packages
import 'dart:convert';

class SyncOperation {
  static const opCreate = 'CREATE';
  static const opUpdate = 'UPDATE';

  final int? localId;
  final String operation;        // CREATE or UPDATE
  final String table;            // e.g. 'receivings'
  final String? serverId;        // null if not yet synced
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;

  const SyncOperation({
    this.localId,
    required this.operation,
    required this.table,
    this.serverId,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.lastError,
  });

  SyncOperation copyWith({
    int? localId,
    String? serverId,
    int? retryCount,
    String? lastError,
  }) {
    return SyncOperation(
      localId:    localId    ?? this.localId,
      operation:  operation,
      table:      table,
      serverId:   serverId   ?? this.serverId,
      payload:    payload,
      createdAt:  createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastError:  lastError  ?? this.lastError,
    );
  }

  Map<String, dynamic> toDb() => {
    if (localId != null) 'id': localId,
    'operation':   operation,
    'table_name':  table,
    'server_id':   serverId,
    'payload':     jsonEncode(payload),
    'created_at':  createdAt.toIso8601String(),
    'retry_count': retryCount,
    'last_error':  lastError,
  };

  factory SyncOperation.fromDb(Map<String, dynamic> row) {
    return SyncOperation(
      localId:    row['id'] as int?,
      operation:  row['operation'] as String,
      table:      row['table_name'] as String,
      serverId:   row['server_id'] as String?,
      payload:    jsonDecode(row['payload'] as String),
      createdAt:  DateTime.parse(row['created_at'] as String),
      retryCount: row['retry_count'] as int? ?? 0,
      lastError:  row['last_error'] as String?,
    );
  }
}

