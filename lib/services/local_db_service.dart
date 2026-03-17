import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/sync_queue_model.dart';
import '../models/receiving_model.dart';

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
        // Sync queue — pending API operations
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

        // Local receiving records (offline created or cached)
        await db.execute('''
          CREATE TABLE receiving_records (
            local_id     INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id    TEXT,
            lot_no       TEXT,
            receipt_date TEXT,
            supplier_id  TEXT,
            supplier_name TEXT,
            material_id  TEXT,
            material_name TEXT,
            invoice_qty  REAL,
            received_qty REAL,
            unit         TEXT,
            vehicle_number TEXT,
            remarks      TEXT,
            status_label TEXT DEFAULT 'Pending',
            status_code  INTEGER DEFAULT 0,
            sync_status  TEXT DEFAULT 'pending',
            updated_at   TEXT,
            created_at   TEXT
          )
        ''');

        // Dropdown cache
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
    return rows.map((r) => MaterialOption(
      id:   r['item_id'] as String,
      name: r['name'] as String,
      unit: r['extra'] as String?,
    )).toList();
  }

  Future<List<SupplierOption>> getCachedSuppliers() async {
    final rows = await db.query(
      'dropdown_cache',
      where: 'type = ?',
      whereArgs: ['supplier'],
    );
    return rows.map((r) => SupplierOption(
      id:   r['item_id'] as String,
      name: r['name'] as String,
    )).toList();
  }

  // ── Receiving records ───────────────────────────────────────────

  Future<int> insertReceiving(Map<String, dynamic> payload, {
    String syncStatus = 'pending',
    String? serverId,
  }) async {
    return await db.insert('receiving_records', {
      'server_id':     serverId,
      'lot_no':        payload['lot_no'],
      'receipt_date':  payload['receipt_date'],
      'supplier_id':   payload['supplier_id']?.toString(),
      'material_id':   payload['material_id']?.toString(),
      'invoice_qty':   payload['invoice_qty'],
      'received_qty':  payload['received_qty'],
      'unit':          payload['unit'],
      'vehicle_number': payload['vehicle_number'],
      'remarks':       payload['remarks'],
      'status_label':  'Pending',
      'status_code':   0,
      'sync_status':   syncStatus,
      'updated_at':    DateTime.now().toIso8601String(),
      'created_at':    DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateReceivingByServerId(
      String serverId, Map<String, dynamic> payload) async {
    await db.update(
      'receiving_records',
      {
        ...payload,
        'sync_status': 'synced',
        'updated_at':  DateTime.now().toIso8601String(),
      },
      where: 'server_id = ?',
      whereArgs: [serverId],
    );
  }

  Future<void> markSynced(int localId, String serverId) async {
    await db.update(
      'receiving_records',
      {'sync_status': 'synced', 'server_id': serverId},
      where: 'local_id = ?',
      whereArgs: [localId],
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
    final rows = await db.query(
      'sync_queue',
      orderBy: 'created_at ASC',
    );
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