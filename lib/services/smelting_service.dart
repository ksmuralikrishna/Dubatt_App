// ─────────────────────────────────────────────────────────────────────────────
// smelting_service.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dubatt_app/services/auth_service.dart';
import 'package:dubatt_app/services/connectivity_service.dart';
import 'package:dubatt_app/services/local_db_service.dart';
import 'package:dubatt_app/models/smelting_model.dart';
import 'package:dubatt_app/models/sync_queue_model.dart';


class SmeltingService {
  static final SmeltingService _i = SmeltingService._();
  factory SmeltingService() => _i;
  SmeltingService._();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer ${AuthService().token}',
  };

  // ── Materials dropdown ──────────────────────────────────────────────────────
  // Online  → /materials?per_page=1000 + cache
  // Offline → smelting_material_cache

  Future<List<SmeltingMaterialOption>> getMaterials() async {
    if (!ConnectivityService().isOnline) {
      return LocalDbService().getCachedSmeltingMaterials();
    }
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/materials?per_page=1000'),
          headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body['data']?['data'] ?? body['data'] ?? []) as List;
        final opts = list
            .map((j) => SmeltingMaterialOption.fromJson(j))
            .toList();
        await LocalDbService().cacheSmeltingMaterials(opts);
        return opts;
      }
      return await LocalDbService().getCachedSmeltingMaterials();
    } catch (_) {
      return await LocalDbService().getCachedSmeltingMaterials();
    }
  }

  // ── BBSU lots modal ─────────────────────────────────────────────────────────
  // Online  → /smelting-batches/bbsu-lots/:materialId + cache per materialId
  // Offline → smelting_bbsu_lot_cache for that materialId
  //
  // Per-materialId replace: deletes old rows for this material before inserting.

  Future<List<SmeltingBbsuLot>> getBbsuLots(
      String materialId, {
        String? excludeSmeltingId,
      }) async {
    if (!ConnectivityService().isOnline) {
      return LocalDbService().getCachedSmeltingBbsuLots(materialId);
    }
    try {
      final excl = excludeSmeltingId != null
          ? '?exclude_smelting_id=$excludeSmeltingId'
          : '';
      final res = await http
          .get(
        Uri.parse(
            '$kBaseUrl/smelting-batches/bbsu-lots/$materialId$excl'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body['data'] ?? []) as List;
        final lots = list
            .map((j) => SmeltingBbsuLot.fromJson(j))
            .toList();
        // Cache per materialId — replaces previous rows for this material
        await LocalDbService()
            .cacheSmeltingBbsuLots(materialId, lots);
        return lots;
      }
      return await LocalDbService()
          .getCachedSmeltingBbsuLots(materialId);
    } catch (_) {
      return await LocalDbService()
          .getCachedSmeltingBbsuLots(materialId);
    }
  }

  // ── Generate batch no ───────────────────────────────────────────────────────
  // Offline fallback: SMLT-{year}-{4 digits}

  Future<String> generateBatchNo() async {
    if (!ConnectivityService().isOnline) return _fallback();
    try {
      final res = await http
          .get(
        Uri.parse('$kBaseUrl/smelting-batches/generate-batch-no'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['batch_no']?.toString() ?? _fallback();
      }
      return _fallback();
    } catch (_) {
      return _fallback();
    }
  }

  String _fallback() {
    final year   = DateTime.now().year;
    final suffix =
    DateTime.now().millisecondsSinceEpoch.toString().substring(9);
    return 'SMLT-$year-$suffix';
  }

  // ── List ────────────────────────────────────────────────────────────────────

  Future<SmeltingListResult> getList({
    int page = 1,
    int perPage = 20,
    String? search,
    String? status,
    String? rotaryNo,
  }) async {
    if (! ConnectivityService().isOnline) {
      return _listFromLocal(search: search, status: status);
    }
    try {
      final params = {
        'page': '$page',
        'per_page': '$perPage',
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null && status != 'all') 'status': status,
        if (rotaryNo != null && rotaryNo.isNotEmpty) 'rotary_no': rotaryNo,
      };
      final uri = Uri.parse('$kBaseUrl/smelting-batches')
          .replace(queryParameters: params);
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      final body = jsonDecode(res.body);

      if (res.statusCode == 200) {
        final data    = body['data'];
        final list    = (data['data'] ?? []) as List;
        final total   = data['total'] ?? list.length;
        final records = list
            .map((j) => SmeltingSummary.fromJson(j))
            .toList();
        if (page == 1 &&
            (search == null || search.isEmpty) &&
            (status == null || status == 'all')) {
          await LocalDbService().cacheSmeltingRecords(records);
        }
        return SmeltingListResult(records: records, total: total);
      }
      return _listFromLocal(search: search, status: status);
    } catch (_) {
      return _listFromLocal(search: search, status: status);
    }
  }

  Future<SmeltingListResult> _listFromLocal({
    String? search,
    String? status,
  }) async {
    try {
      final cachedRows =
      await LocalDbService().getAllSmeltingForDisplay();
      final queuedRows =
      await LocalDbService().getQueuedSmelting();

      final queued = queuedRows.map((row) {
        final p = row['payload'] as Map<String, dynamic>;
        return SmeltingSummary(
          id:          'queue_${row['queue_id']}',
          batchNo:     p['batch_no']?.toString() ?? '',
          date:        p['date']?.toString() ?? '',
          rotaryNo:    p['rotary_no']?.toString() ?? '',
          statusLabel: 'Draft',
          statusCode:  0,
          syncStatus:  'pending',
        );
      }).toList();

      final cached = cachedRows
          .map((r) => SmeltingSummary.fromLocal(r))
          .toList();

      var all = [...queued, ...cached];

      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        all = all.where((r) => r.batchNo.toLowerCase().contains(q)).toList();
      }
      if (status != null && status != 'all') {
        if (status == 'submitted' || status == '1') {
          all = all.where((r) => r.statusCode >= 1).toList();
        } else if (status == 'draft' || status == '0') {
          all = all.where((r) => r.statusCode == 0).toList();
        }
      }
      return SmeltingListResult(records: all, total: all.length);
    } catch (e) {
      return SmeltingListResult.error('Failed to load offline data.');
    }
  }

  // ── Load one ────────────────────────────────────────────────────────────────

  Future<SmeltingRecord?> getOne(String id) async {
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/smelting-batches/$id'),
          headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        print("DATA: $data");

        return SmeltingRecord.fromJson(data);
        // return SmeltingRecord.fromJson(jsonDecode(res.body)['data']);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<SmeltingSaveResult> save(
      Map<String, dynamic> payload, {
        String? id,
      }) async {
    if (!ConnectivityService().isOnline) {
      try {
        await LocalDbService().addToQueue(SyncOperation(
          operation: id == null
              ? SyncOperation.opCreate
              : SyncOperation.opUpdate,
          table:     'smelting-batches',
          serverId:  id,
          payload:   payload,
          createdAt: DateTime.now(),
        ));
        return const SmeltingSaveResult(success: true, newId: null);
      } catch (e) {
        return SmeltingSaveResult.error('Failed to save offline: $e');
      }
    }
    try {
      final isCreate = id == null;
      final uri = Uri.parse(isCreate
          ? '$kBaseUrl/smelting-batches'
          : '$kBaseUrl/smelting-batches/$id');
      final res = await (isCreate
          ? http.post(uri, headers: _headers, body: jsonEncode(payload))
          : http.put(uri, headers: _headers, body: jsonEncode(payload)))
          .timeout(const Duration(seconds: 25));
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return SmeltingSaveResult(
          success: true,
          newId:   body['data']?['id']?.toString(),
        );
      } else if (res.statusCode == 422) {
        return SmeltingSaveResult(
          success:     false,
          errorMsg:    body['message'],
          fieldErrors: body['errors'] ?? {},
        );
      }
      return SmeltingSaveResult.error(body['message'] ?? 'Save failed.');
    } catch (_) {
      return SmeltingSaveResult.error('Network error. Could not save.');
    }
  }

  // ── Submit (POST /smelting-batches/:id/submit) ──────────────────────────────

  Future<String?> submit(String id) async {
    try {
      final res = await http
          .post(Uri.parse('$kBaseUrl/smelting-batches/$id/submit'),
          headers: _headers, body: '{}')
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) return null;
      return jsonDecode(res.body)['message'] ?? 'Submit failed.';
    } catch (_) {
      return 'Network error.';
    }
  }

  // ── Delete ──────────────────────────────────────────────────────────────────

  Future<String?> delete(String id) async {
    try {
      final res = await http
          .delete(Uri.parse('$kBaseUrl/smelting-batches/$id'),
          headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200 || res.statusCode == 204) return null;
      return jsonDecode(res.body)['message'] ?? 'Delete failed.';
    } catch (_) {
      return 'Network error. Could not delete.';
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Converts HH:mm + date → ISO datetime string.
  static String? toIsoDateTime(String date, String? hhmm) {
    if (date.isEmpty || hhmm == null || hhmm.isEmpty) return null;
    return '${date}T$hhmm:00';
  }

  /// Extracts HH:mm from ISO datetime or returns as-is.
  static String? toHHmm(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.contains('T')) {
      final parts = raw.split('T');
      if (parts.length == 2 && parts[1].length >= 5) {
        return parts[1].substring(0, 5);
      }
    }
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCAL DB ADDITIONS
// Merge into local_db_service.dart — version bump 4 → 5
// ─────────────────────────────────────────────────────────────────────────────
//
// STEP 1: Bump version: 4 → 5
//
// STEP 2: Add inside onCreate() after bbsu_acid_summary_cache block:
/*

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
  // Per-materialId BBSU lot cache for smelting modals
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

*/
//
// STEP 3: Add inside onUpgrade() — if (oldVersion < 5) { same CREATE IF NOT EXISTS ... }
//
// STEP 4: Copy these methods into the LocalDbService class body:
/*

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
              bbsuBatchId:  r['bbsu_batch_id'] as String,
              batchNo:      r['batch_no'] as String? ?? '',
              materialName: r['material_name'] as String? ?? '',
              materialUnit: r['material_unit'] as String? ?? 'KG',
              availableQty: (r['available_qty'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
  }

*/