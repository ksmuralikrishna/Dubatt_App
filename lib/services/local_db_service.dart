import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:dubatt_app/models/receiving_model.dart';
import 'package:dubatt_app/models/sync_queue_model.dart';

class LocalDbService {
  static final LocalDbService _i = LocalDbService._();
  factory LocalDbService() => _i;
  LocalDbService._();

  Database? _db;

  Future<void> init() async {
    _db = await openDatabase(
      join(await getDatabasesPath(), 'mes_offline.db'),
      version: 1,
      onCreate: (db, version) async {

        // ── Sync queue — pending API operations
        await db.execute('''
          CREATE TABLE sync_queue (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            operation    TEXT NOT NULL,
            table_name   TEXT NOT NULL,
            server_id    TEXT,
            payload      TEXT NOT NULL,
            created_at   TEXT NOT NULL,
            retry_count  INTEGER DEFAULT 0,
            last_error   TEXT
          )
        ''');

        // ── Receiving records
        // ONLY used for caching server records (sync_status = 'synced').
        // Offline-created records live in sync_queue only.
        await db.execute('''
          CREATE TABLE receiving_records (
            local_id       INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id      TEXT,
            lot_no         TEXT,
            receipt_date   TEXT,
            supplier_id    TEXT,
            supplier_name  TEXT,
            material_id    TEXT,
            material_name  TEXT,
            invoice_qty    REAL,
            received_qty   REAL,
            unit           TEXT,
            vehicle_number TEXT,
            remarks        TEXT,
            status_label   TEXT DEFAULT 'Pending',
            status_code    INTEGER DEFAULT 0,
            sync_status    TEXT DEFAULT 'synced',
            updated_at     TEXT,
            created_at     TEXT
          )
        ''');

        // Unique index on server_id (only for non-null values)
        // Allows multiple offline rows (server_id IS NULL) while
        // preventing duplicate cached server records
        await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_receiving_server_id
          ON receiving_records (server_id)
          WHERE server_id IS NOT NULL
        ''');

        // ── Dropdown cache
        await db.execute('''
          CREATE TABLE dropdown_cache (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            type      TEXT NOT NULL,
            item_id   TEXT NOT NULL,
            name      TEXT NOT NULL,
            extra     TEXT,
            cached_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Database get db {
    assert(_db != null, 'LocalDbService not initialized. Call init() first.');
    return _db!;
  }

  // ── Dropdown cache ──────────────────────────────────────────────

  Future<void> cacheDropdown(String type, List<dynamic> items) async {
    final batch = db.batch();
    batch.delete('dropdown_cache', where: 'type = ?', whereArgs: [type]);
    for (final item in items) {
      batch.insert('dropdown_cache', {
        'type':      type,
        'item_id':   item.id,
        'name':      item.name,
        'extra':     item is MaterialOption ? item.unit : null,
        'cached_at': DateTime.now().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<MaterialOption>> getCachedMaterials() async {
    final rows = await db.query(
      'dropdown_cache',
      where: 'type = ?',
      whereArgs: ['material'],
    );
    return rows
        .map((r) => MaterialOption(
      id:   r['item_id'] as String,
      name: r['name'] as String,
      unit: r['extra'] as String?,
    ))
        .toList();
  }

  Future<List<SupplierOption>> getCachedSuppliers() async {
    final rows = await db.query(
      'dropdown_cache',
      where: 'type = ?',
      whereArgs: ['supplier'],
    );
    return rows
        .map((r) => SupplierOption(
      id:   r['item_id'] as String,
      name: r['name'] as String,
    ))
        .toList();
  }

  // ── Cache server records ────────────────────────────────────────
  // Called after every successful API list fetch (page 1, no filters).
  // Uses INSERT OR IGNORE + UPDATE pattern to avoid duplicates.
  // Only updates rows where sync_status = 'synced' (never touches
  // offline-created rows — but those now live in sync_queue anyway).

  Future<void> cacheServerReceivings(List<ReceivingSummary> records) async {
    final batch = db.batch();
    for (final r in records) {
      // Step 1: Insert if server_id not yet in table
      batch.rawInsert('''
        INSERT OR IGNORE INTO receiving_records
          (server_id, lot_no, receipt_date, supplier_name, material_name,
           received_qty, unit, status_label, status_code,
           sync_status, updated_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', datetime('now'), ?)
      ''', [
        r.id,
        r.lotNo,
        r.receiptDate,
        r.supplierName,
        r.materialName,
        r.receivedQty,
        r.unit,
        r.statusLabel,
        r.statusCode,
        r.receiptDate,
      ]);

      // Step 2: Update existing row if already cached
      batch.rawUpdate('''
        UPDATE receiving_records
        SET
          lot_no        = ?,
          receipt_date  = ?,
          supplier_name = ?,
          material_name = ?,
          received_qty  = ?,
          unit          = ?,
          status_label  = ?,
          status_code   = ?,
          sync_status   = 'synced',
          updated_at    = datetime('now')
        WHERE server_id = ?
          AND sync_status = 'synced'
      ''', [
        r.lotNo,
        r.receiptDate,
        r.supplierName,
        r.materialName,
        r.receivedQty,
        r.unit,
        r.statusLabel,
        r.statusCode,
        r.id,
      ]);
    }
    await batch.commit(noResult: true);
  }

  // ── Offline list queries ────────────────────────────────────────

  /// Returns all cached server records from receiving_records.
  /// Sorted by created_at DESC.
  Future<List<Map<String, dynamic>>> getAllReceivingsForDisplay() async {
    return await db.query(
      'receiving_records',
      orderBy: 'created_at DESC',
    );
  }

  /// Returns all CREATE operations from sync_queue for receivings.
  /// These are offline-created records not yet synced to server.
  /// Each returned map contains:
  ///   - queue_id   : the sync_queue row id
  ///   - created_at : when the record was saved offline
  ///   - payload    : decoded Map of the form data
  Future<List<Map<String, dynamic>>> getQueuedReceivings() async {
    final rows = await db.query(
      'sync_queue',
      where: 'operation = ? AND table_name = ?',
      whereArgs: [SyncOperation.opCreate, 'receivings'],
      orderBy: 'created_at DESC',
    );

    return rows.map((row) {
      final payload =
      jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      return {
        'queue_id':   row['id'],
        'created_at': row['created_at'],
        'payload':    payload,
      };
    }).toList();
  }

  // ── Sync helpers ────────────────────────────────────────────────

  Future<void> markSynced(int localId, String serverId) async {
    await db.update(
      'receiving_records',
      {'sync_status': 'synced', 'server_id': serverId},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> updateReceivingByServerId(
      String serverId, Map<String, dynamic> data) async {
    await db.update(
      'receiving_records',
      {
        ...data,
        'sync_status': 'synced',
        'updated_at':  DateTime.now().toIso8601String(),
      },
      where: 'server_id = ?',
      whereArgs: [serverId],
    );
  }

  Future<List<Map<String, dynamic>>> getLocalReceivings() async {
    return await db.query(
      'receiving_records',
      orderBy: 'created_at DESC',
    );
  }

  // ── Sync queue ──────────────────────────────────────────────────

  Future<int> addToQueue(SyncOperation op) async {
    return await db.insert('sync_queue', op.toDb());
  }

  Future<List<SyncOperation>> getPendingOps() async {
    final rows = await db.query('sync_queue', orderBy: 'created_at ASC');
    return rows.map(SyncOperation.fromDb).toList();
  }

  Future<void> deleteQueueItem(int id) async {
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> incrementRetry(int id, String error) async {
    await db.rawUpdate('''
      UPDATE sync_queue
      SET retry_count = retry_count + 1, last_error = ?
      WHERE id = ?
    ''', [error, id]);
  }

  Future<int> getPendingCount() async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_queue',
    );
    return result.first['count'] as int;
  }
}