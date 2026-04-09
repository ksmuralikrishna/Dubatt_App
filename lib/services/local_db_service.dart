import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:dubatt_app/models/receiving_model.dart';
import 'package:dubatt_app/models/sync_queue_model.dart';
import 'package:dubatt_app/models/acid_testing_model.dart';
import 'package:dubatt_app/models/bbsu_model.dart';
import 'package:dubatt_app/models/smelting_model.dart';
import 'package:dubatt_app/models/refining_model.dart';
import '../../services/bbsu_service.dart';

class LocalDbService {
  static final LocalDbService _i = LocalDbService._();
  factory LocalDbService() => _i;
  LocalDbService._();

  Database? _db;

  Future<void> init() async {
    _db = await openDatabase(
        join(await getDatabasesPath(), 'mes_offline.db'),
        version: 5,
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

          // ── Acid testing records
          await db.execute('''
          CREATE TABLE acid_testing_records (
            local_id       INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id      TEXT,
            lot_number     TEXT,
            test_date      TEXT,
            supplier_name  TEXT,
            vehicle_number TEXT,
            avg_pallet_weight           REAL,
            foreign_material_weight     REAL,
            avg_pallet_and_foreign_weight REAL,
            received_qty   REAL,
            status_label   TEXT DEFAULT 'Pending',
            status_code    INTEGER DEFAULT 0,
            sync_status    TEXT DEFAULT 'synced',
            updated_at     TEXT,
            created_at     TEXT
          )
        ''');

          await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_acid_testing_server_id
          ON acid_testing_records (server_id)
          WHERE server_id IS NOT NULL
        ''');

          await db.execute('''
          CREATE TABLE acid_lot_cache (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            lot_no     TEXT NOT NULL,
            supplier_name TEXT,
            supplier_id   TEXT,
            vehicle_number TEXT,
            received_qty  REAL,
            invoice_qty   REAL,
            receipt_date  TEXT,
            cached_at  TEXT NOT NULL
          )
        ''');

          // ── BBSU records
          await db.execute('''
          CREATE TABLE bbsu_records (
            local_id       INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id      TEXT,
            batch_no       TEXT,
            doc_date       TEXT,
            category       TEXT,
            start_time     TEXT,
            end_time       TEXT,
            status_label   TEXT DEFAULT 'Draft',
            status_code    INTEGER DEFAULT 0,
            sync_status    TEXT DEFAULT 'synced',
            updated_at     TEXT,
            created_at     TEXT
          )
        ''');

          await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_bbsu_server_id
          ON bbsu_records (server_id)
          WHERE server_id IS NOT NULL
        ''');

          await db.execute('''
          CREATE TABLE bbsu_lot_cache (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            lot_number    TEXT NOT NULL,
            supplier_name TEXT,
            received_qty  REAL,
            acid_pct      REAL,
            cached_at     TEXT NOT NULL
          )
        ''');

          await db.execute('''
          CREATE TABLE bbsu_acid_summary_cache (
            id                   INTEGER PRIMARY KEY AUTOINCREMENT,
            lot_number           TEXT NOT NULL,
            lot_no               TEXT,
            material_description TEXT,
            avg_acid_pct         REAL,
            net_weight           REAL,
            unit                 TEXT,
            cached_at            TEXT NOT NULL
          )
        ''');

          await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_acid_summary_lot
          ON bbsu_acid_summary_cache (lot_number)
        ''');

          // ── Smelting tables (NEW)
          await db.execute('''
          CREATE TABLE smelting_records (
            local_id     INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id    TEXT,
            batch_no     TEXT,
            doc_date     TEXT,
            rotary_no    TEXT,
            start_time   TEXT,
            end_time     TEXT,
            output_qty   REAL,
            status_label TEXT DEFAULT 'Draft',
            status_code  INTEGER DEFAULT 0,
            sync_status  TEXT DEFAULT 'synced',
            updated_at   TEXT,
            created_at   TEXT
          )
        ''');

          await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_smelting_server_id
          ON smelting_records (server_id)
          WHERE server_id IS NOT NULL
        ''');

          await db.execute('''
          CREATE TABLE smelting_material_cache (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id   TEXT NOT NULL,
            name      TEXT NOT NULL,
            unit      TEXT,
            cached_at TEXT NOT NULL
          )
        ''');

          await db.execute('''
          CREATE TABLE smelting_bbsu_lot_cache (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            material_id   TEXT NOT NULL,
            bbsu_batch_id TEXT NOT NULL,
            batch_no      TEXT,
            material_name TEXT,
            material_unit TEXT,
            available_qty REAL,
            cached_at     TEXT NOT NULL
          )
        ''');

          await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_smelting_bbsu_lot_mat
          ON smelting_bbsu_lot_cache (material_id)
        ''');
// Refining
          await db.execute('''
    CREATE TABLE refining_records (
      local_id               INTEGER PRIMARY KEY AUTOINCREMENT,
      server_id              TEXT,
      batch_no               TEXT,
      pot_no                 TEXT,
      doc_date               TEXT,
      lpg_consumption        REAL,
      electricity_consumption REAL,
      status_label           TEXT DEFAULT 'Draft',
      status_code            INTEGER DEFAULT 0,
      sync_status            TEXT DEFAULT 'synced',
      updated_at             TEXT,
      created_at             TEXT
    )
  ''');
          await db.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_refining_server_id
    ON refining_records (server_id)
    WHERE server_id IS NOT NULL
  ''');
          await db.execute('''
    CREATE TABLE refining_material_cache (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id   TEXT NOT NULL,
      name      TEXT NOT NULL,
      unit      TEXT,
      cached_at TEXT NOT NULL
    )
  ''');
          await db.execute('''
    CREATE TABLE refining_process_name_cache (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      name      TEXT NOT NULL,
      sort_order INTEGER DEFAULT 0,
      cached_at TEXT NOT NULL
    )
  ''');
          await db.execute('''
    CREATE TABLE refining_smelting_lot_cache (
      id                  INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id         TEXT NOT NULL,
      smelting_batch_id   TEXT NOT NULL,
      batch_no            TEXT,
      secondary_name      TEXT,
      material_unit       TEXT,
      available_qty       REAL,
      cached_at           TEXT NOT NULL
    )
  ''');
          await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_refining_smt_lot_mat
    ON refining_smelting_lot_cache (material_id)
  ''');



















        },
        // Optional: Keep onUpgrade minimal for development
        onUpgrade: (db, oldVersion, newVersion) async {
          // For development, you can keep this empty or just log
          print('Database upgraded from $oldVersion to $newVersion');
          // If you ever need to add migrations later, add them here
        }
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

  // ── Acid Testing: cache server records ───────────────────────────────────
  Future<void> cacheAcidTestings(List<AcidTestingSummary> records) async {
    final batch = db.batch();
    for (final r in records) {
      batch.rawInsert('''
        INSERT OR IGNORE INTO acid_testing_records
          (server_id, lot_number, test_date, supplier_name, vehicle_number,
           avg_pallet_weight, foreign_material_weight, avg_pallet_and_foreign_weight,
           received_qty, status_label, status_code, sync_status,
           updated_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', datetime('now'), ?)
      ''', [
        r.id, r.lotNumber, r.testDate, r.supplierName, r.vehicleNumber,
        r.avgPalletWeight, r.foreignMaterialWeight, r.avgPalletAndForeignWeight,
        r.receivedQty, r.statusLabel, r.statusCode, r.testDate,
      ]);

      batch.rawUpdate('''
        UPDATE acid_testing_records
        SET lot_number=?, test_date=?, supplier_name=?, vehicle_number=?,
            avg_pallet_weight=?, foreign_material_weight=?,
            avg_pallet_and_foreign_weight=?, received_qty=?,
            status_label=?, status_code=?, sync_status='synced',
            updated_at=datetime('now')
        WHERE server_id=? AND sync_status='synced'
      ''', [
        r.lotNumber, r.testDate, r.supplierName, r.vehicleNumber,
        r.avgPalletWeight, r.foreignMaterialWeight, r.avgPalletAndForeignWeight,
        r.receivedQty, r.statusLabel, r.statusCode, r.id,
      ]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getAllAcidTestingsForDisplay() async {
    return await db.query('acid_testing_records', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getQueuedAcidTestings() async {
    final rows = await db.query(
      'sync_queue',
      where: 'operation = ? AND table_name = ?',
      whereArgs: [SyncOperation.opCreate, 'acid-testings'],
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

  // ── Acid lot cache ────────────────────────────────────────────────────────
  Future<void> cacheAcidLots(List<LotOption> lots) async {
    final batch = db.batch();
    batch.delete('acid_lot_cache');
    for (final l in lots) {
      batch.insert('acid_lot_cache', {
        'lot_no':        l.lotNo,
        'supplier_name': l.supplierName,
        'supplier_id':   l.supplierId,
        'vehicle_number': l.vehicleNumber,
        'received_qty':  l.receivedQty,
        'invoice_qty':   l.invoiceQty,
        'receipt_date':  l.receiptDate,
        'cached_at':     DateTime.now().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<LotOption>> getCachedAcidLots() async {
    final rows = await db.query('acid_lot_cache', orderBy: 'lot_no ASC');
    return rows.map((r) => LotOption(
      lotNo:         r['lot_no'] as String,
      supplierName:  r['supplier_name'] as String? ?? '',
      supplierId:    r['supplier_id'] as String?,
      vehicleNumber: r['vehicle_number'] as String?,
      receivedQty:   r['received_qty'] as double?,
      invoiceQty:    r['invoice_qty'] as double?,
      receiptDate:   r['receipt_date'] as String?,
    )).toList();

  }
  Future<void> cacheBbsuRecords(List<BbsuSummary> records) async {
    final batch = db.batch();
    for (final r in records) {
      batch.rawInsert('''
        INSERT OR IGNORE INTO bbsu_records
          (server_id, batch_no, doc_date, category, start_time, end_time,
           status_label, status_code, sync_status, updated_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'synced', datetime('now'), ?)
      ''', [
        r.id, r.batchNo, r.docDate, r.category,
        r.startTime, r.endTime,
        r.statusLabel, r.statusCode, r.docDate,
      ]);

      batch.rawUpdate('''
        UPDATE bbsu_records
        SET batch_no=?, doc_date=?, category=?, start_time=?, end_time=?,
            status_label=?, status_code=?, sync_status='synced',
            updated_at=datetime('now')
        WHERE server_id=? AND sync_status='synced'
      ''', [
        r.batchNo, r.docDate, r.category,
        r.startTime, r.endTime,
        r.statusLabel, r.statusCode, r.id,
      ]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getAllBbsuForDisplay() async {
    return await db.query('bbsu_records', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getQueuedBbsu() async {
    final rows = await db.query(
      'sync_queue',
      where: 'operation = ? AND table_name = ?',
      whereArgs: [SyncOperation.opCreate, 'bbsu-batches'],
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

  // ── BBSU lot cache ─────────────────────────────────────────────────────────
  Future<void> cacheBbsuLots(List<BbsuLotOption> lots) async {
    final batch = db.batch();
    batch.delete('bbsu_lot_cache');
    for (final l in lots) {
      batch.insert('bbsu_lot_cache', {
        'lot_number':   l.lotNumber,
        'supplier_name': l.supplierName,
        'received_qty': l.receivedQty,
        'acid_pct':     l.acidPct,
        'cached_at':    DateTime.now().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<BbsuLotOption>> getCachedBbsuLots() async {
    final rows = await db.query('bbsu_lot_cache', orderBy: 'lot_number ASC');
    return rows.map((r) => BbsuLotOption(
      lotNumber:    r['lot_number'] as String,
      supplierName: r['supplier_name'] as String?,
      receivedQty:  r['received_qty'] as double?,
      acidPct:      r['acid_pct'] as double?,
    )).toList();
  }
  // ── BBSU acid summary cache ────────────────────────────────────────────────
  // Stores all rows returned by /bbsu-batches/acid-summary/:lotNo.
  // Per-lot replace: all existing rows for the lot are deleted first,
  // then the fresh rows are inserted.

  Future<void> cacheAcidSummary(
      String lotNumber,
      List<Map<String, dynamic>> rows,
      ) async {
    final batch = db.batch();

    // Delete all existing rows for this lot before re-inserting
    batch.delete(
      'bbsu_acid_summary_cache',
      where: 'lot_number = ?',
      whereArgs: [lotNumber],
    );

    final now = DateTime.now().toIso8601String();
    for (final row in rows) {
      batch.insert('bbsu_acid_summary_cache', {
        'lot_number':           lotNumber,
        'lot_no':               row['lot_no']?.toString(),
        'material_description': row['material_description']?.toString(),
        'avg_acid_pct':         _toDoubleOrNull(row['avg_acid_pct']),
        'net_weight':           _toDoubleOrNull(row['net_weight']),
        'unit':                 row['unit']?.toString(),
        'cached_at':            now,
      });
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedAcidSummary(
      String lotNumber) async {
    final rows = await db.query(
      'bbsu_acid_summary_cache',
      where: 'lot_number = ?',
      whereArgs: [lotNumber],
      orderBy: 'id ASC',
    );

    // Return as plain maps so the caller (BbsuService / _QtyModal)
    // gets the same shape as the API response.
    return rows.map((r) => {
      'lot_no':               r['lot_no'],
      'material_description': r['material_description'],
      'avg_acid_pct':         r['avg_acid_pct'],
      'net_weight':           r['net_weight'],
      'unit':                 r['unit'],
    }).toList();
  }

  /// Returns true when at least one cached row exists for this lot.
  Future<bool> hasAcidSummaryCache(String lotNumber) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM bbsu_acid_summary_cache WHERE lot_number = ?',
      [lotNumber],
    );
    return (result.first['count'] as int) > 0;
  }

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  // ── Smelting: cache server records ────────────────────────────────────────
  Future<void> cacheSmeltingRecords(List<SmeltingSummary> records) async {
    final batch = db.batch();
    for (final r in records) {
      batch.rawInsert('''
        INSERT OR IGNORE INTO smelting_records
          (server_id, batch_no, doc_date, rotary_no, start_time, end_time,
           output_qty, status_label, status_code, sync_status,
           updated_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', datetime('now'), ?)
      ''', [
        r.id, r.batchNo, r.date, r.rotaryNo, r.startTime, r.endTime,
        r.outputQty, r.statusLabel, r.statusCode, r.date,
      ]);
      batch.rawUpdate('''
        UPDATE smelting_records
        SET batch_no=?, doc_date=?, rotary_no=?, start_time=?, end_time=?,
            output_qty=?, status_label=?, status_code=?,
            sync_status='synced', updated_at=datetime('now')
        WHERE server_id=? AND sync_status='synced'
      ''', [
        r.batchNo, r.date, r.rotaryNo, r.startTime, r.endTime,
        r.outputQty, r.statusLabel, r.statusCode, r.id,
      ]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getAllSmeltingForDisplay() async {
    return await db.query('smelting_records', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getQueuedSmelting() async {
    final rows = await db.query(
      'sync_queue',
      where: 'operation = ? AND table_name = ?',
      whereArgs: [SyncOperation.opCreate, 'smelting-batches'],
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

  // ── Smelting material cache ─────────────────────────────────────────────────
  Future<void> cacheSmeltingMaterials(
      List<SmeltingMaterialOption> items) async {
    final batch = db.batch();
    batch.delete('smelting_material_cache');
    final now = DateTime.now().toIso8601String();
    for (final m in items) {
      batch.insert('smelting_material_cache', {
        'item_id':   m.id,
        'name':      m.name,
        'unit':      m.unit,
        'cached_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<SmeltingMaterialOption>> getCachedSmeltingMaterials() async {
    final rows = await db.query('smelting_material_cache',
        orderBy: 'name ASC');
    return rows
        .map((r) => SmeltingMaterialOption(
      id:   r['item_id'] as String,
      name: r['name'] as String,
      unit: r['unit'] as String?,
    ))
        .toList();
  }

  // ── Smelting BBSU lot cache (per materialId) ────────────────────────────────
  Future<void> cacheSmeltingBbsuLots(
      String materialId, List<SmeltingBbsuLot> lots) async {
    final batch = db.batch();
    // Per-materialId replace
    batch.delete('smelting_bbsu_lot_cache',
        where: 'material_id = ?', whereArgs: [materialId]);
    final now = DateTime.now().toIso8601String();
    for (final l in lots) {
      batch.insert('smelting_bbsu_lot_cache', {
        'material_id':   materialId,
        'bbsu_batch_id': l.bbsuBatchId,
        'batch_no':      l.batchNo,
        'material_name': l.materialName,
        'material_unit': l.materialUnit,
        'available_qty': l.availableQty,
        'cached_at':     now,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> cacheAllSmeltingBbsuLots(
      List<SmeltingBbsuLot> lots) async {

    final batch = db.batch();

    // Full refresh → delete everything
    batch.delete('smelting_bbsu_lot_cache');

    final now = DateTime.now().toIso8601String();

    for (final l in lots) {
      batch.insert('smelting_bbsu_lot_cache', {
        'material_id':   l.materialId,
        'bbsu_batch_id': l.bbsuBatchId,
        'batch_no':      l.batchNo,
        'material_name': l.materialName,
        'material_unit': l.materialUnit,
        'available_qty': l.availableQty,
        'cached_at':     now,
      });
    }

    await batch.commit(noResult: true);
  }

  Future<List<SmeltingBbsuLot>> getCachedSmeltingBbsuLots(
      String materialId) async {
    final rows = await db.query(
      'smelting_bbsu_lot_cache',
      where: 'material_id = ?',
      whereArgs: [materialId],
      orderBy: 'batch_no ASC',
    );
    return rows
        .map((r) => SmeltingBbsuLot(
      materialId:  int.tryParse(r['material_id'].toString()) ?? 0,
      bbsuBatchId:  r['bbsu_batch_id'] as String,
      batchNo:      r['batch_no'] as String? ?? '',
      materialName: r['material_name'] as String? ?? '',
      materialUnit: r['material_unit'] as String? ?? 'KG',
      availableQty: (r['available_qty'] as num?)?.toDouble() ?? 0,
    ))
        .toList();
  }
// ── Refining: cache server records ────────────────────────────────────────
  Future<void> cacheRefiningRecords(List<RefiningSummary> records) async {
    final batch = db.batch();
    for (final r in records) {
      batch.rawInsert('''
        INSERT OR IGNORE INTO refining_records
          (server_id, batch_no, pot_no, doc_date,
           lpg_consumption, electricity_consumption,
           status_label, status_code, sync_status,
           updated_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'synced', datetime('now'), ?)
      ''', [
        r.id, r.batchNo, r.potNo, r.date,
        r.lpgConsumption, r.electricityConsumption,
        r.statusLabel, r.statusCode, r.date,
      ]);
      batch.rawUpdate('''
        UPDATE refining_records
        SET batch_no=?, pot_no=?, doc_date=?,
            lpg_consumption=?, electricity_consumption=?,
            status_label=?, status_code=?,
            sync_status='synced', updated_at=datetime('now')
        WHERE server_id=? AND sync_status='synced'
      ''', [
        r.batchNo, r.potNo, r.date,
        r.lpgConsumption, r.electricityConsumption,
        r.statusLabel, r.statusCode, r.id,
      ]);
    }
    await batch.commit(noResult: true);
  }



  Future<List<Map<String, dynamic>>> getAllRefiningForDisplay() async {
    return await db.query('refining_records', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getQueuedRefining() async {
    final rows = await db.query(
      'sync_queue',
      where: 'operation = ? AND table_name = ?',
      whereArgs: [SyncOperation.opCreate, 'refining'],
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

  // ── Refining material cache ─────────────────────────────────────────────────
  Future<void> cacheRefiningMaterials(List<RefiningMaterialOption> items) async {
    final batch = db.batch();
    batch.delete('refining_material_cache');
    final now = DateTime.now().toIso8601String();
    for (final m in items) {
      batch.insert('refining_material_cache', {
        'item_id':   m.id,
        'name':      m.name,
        'unit':      m.unit,
        'cached_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<RefiningMaterialOption>> getCachedRefiningMaterials() async {
    final rows = await db.query('refining_material_cache', orderBy: 'name ASC');
    return rows.map((r) => RefiningMaterialOption(
      id:   r['item_id'] as String,
      name: r['name'] as String,
      unit: r['unit'] as String?,
    )).toList();
  }

  // ── Refining process name cache ─────────────────────────────────────────────
  Future<void> cacheRefiningProcessNames(List<String> names) async {
    final batch = db.batch();
    batch.delete('refining_process_name_cache');
    final now = DateTime.now().toIso8601String();
    for (int i = 0; i < names.length; i++) {
      batch.insert('refining_process_name_cache', {
        'name':       names[i],
        'sort_order': i,
        'cached_at':  now,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<String>> getCachedRefiningProcessNames() async {
    final rows = await db.query('refining_process_name_cache',
        orderBy: 'sort_order ASC');
    return rows.map((r) => r['name'] as String).toList();
  }

  // ── Refining smelting lot cache (per materialId) ────────────────────────────
  Future<void> cacheRefiningSmeltingLots(
      String materialId, List<RefiningSmeltingLot> lots) async {
    final batch = db.batch();
    batch.delete('refining_smelting_lot_cache',
        where: 'material_id = ?', whereArgs: [materialId]);
    final now = DateTime.now().toIso8601String();
    for (final l in lots) {
      batch.insert('refining_smelting_lot_cache', {
        'material_id':        materialId,
        'smelting_batch_id':  l.smeltingBatchId,
        'batch_no':           l.batchNo,
        'secondary_name':     l.secondaryName,
        'material_unit':      l.materialUnit,
        'available_qty':      l.availableQty,
        'cached_at':          now,
      });
    }
    await batch.commit(noResult: true);
  }


  Future<void> cacheAllRefiningSmeltingLots(
      List<RefiningSmeltingLot> lots) async {

    final batch = db.batch();

    // Full refresh → clear entire table
    batch.delete('refining_smelting_lot_cache');

    final now = DateTime.now().toIso8601String();

    for (final l in lots) {
      batch.insert('refining_smelting_lot_cache', {
        'material_id':       l.materialId,   // ← from model
        'smelting_batch_id': l.smeltingBatchId,
        'batch_no':          l.batchNo,
        'secondary_name':    l.secondaryName,
        'material_unit':     l.materialUnit,
        'available_qty':     l.availableQty,
        'cached_at':         now,
      });
    }

    await batch.commit(noResult: true);
  }

  Future<List<RefiningSmeltingLot>> getCachedRefiningSmeltingLots(
      String materialId) async {
    final rows = await db.query(
      'refining_smelting_lot_cache',
      where: 'material_id = ?',
      whereArgs: [materialId],
      orderBy: 'batch_no ASC',
    );
    return rows.map((r) => RefiningSmeltingLot(
      materialId:  int.tryParse(r['material_id'].toString()) ?? 0, // ✅ ADD THIS
      smeltingBatchId: r['smelting_batch_id'] as String,
      batchNo:         r['batch_no'] as String? ?? '',
      secondaryName:   r['secondary_name'] as String? ?? '',
      materialUnit:    r['material_unit'] as String? ?? 'KG',
      availableQty:    (r['available_qty'] as num?)?.toDouble() ?? 0,
    )).toList();
  }

  Future<void> preloadAllAcidSummaries() async {
    final lots = await getCachedAcidLots();

    for (var lot in lots) {
      try {
        // ✅ Just call getAcidSummary() - it will cache automatically
        await BbsuService().getAcidSummary(lot.lotNo);
      } catch (e) {
        print('Failed to preload ${lot.lotNo}: $e');
      }
    }
  }


}