// ─────────────────────────────────────────────────────────────────────────────
// refining_service.dart
//
// API endpoints (from Blade JS):
//   GET  /refining                               → list
//   GET  /refining/:id                           → single record
//   POST /refining                               → create
//   PUT  /refining/:id                           → update
//   POST /refining/:id/submit                    → submit
//   DEL  /refining/:id                           → delete
//   GET  /refining/generate-batch-no             → auto batch no
//   GET  /refining/process-names                 → dynamic process names
//   GET  /refining/smelting-lots/:materialId     → smelting lot modal
//   GET  /materials?per_page=500                 → material dropdown
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dubatt_app/services/auth_service.dart';
import 'package:dubatt_app/services/connectivity_service.dart';
import 'package:dubatt_app/services/local_db_service.dart';
import 'package:dubatt_app/models/refining_model.dart';
import 'package:dubatt_app/models/sync_queue_model.dart';

class RefiningService {
  static final RefiningService _i = RefiningService._();
  factory RefiningService() => _i;
  RefiningService._();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer ${AuthService().token}',
  };

  // ── Materials dropdown ──────────────────────────────────────────────────────
  // Online  → /materials?per_page=500 + cache
  // Offline → refining_material_cache

  Future<List<RefiningMaterialOption>> getMaterials() async {
    if (!ConnectivityService().isOnline) {
      return LocalDbService().getCachedRefiningMaterials();
    }
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/materials?per_page=500'), headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body['data']?['data'] ?? body['data'] ?? []) as List;
        final opts = list.map((j) => RefiningMaterialOption.fromJson(j)).toList();
        await LocalDbService().cacheRefiningMaterials(opts);
        return opts;
      }
      return await LocalDbService().getCachedRefiningMaterials();
    } catch (_) {
      return await LocalDbService().getCachedRefiningMaterials();
    }
  }

  // ── Process names ───────────────────────────────────────────────────────────
  // Online  → /refining/process-names + cache
  // Offline → refining_process_name_cache

  Future<List<String>> getProcessNames() async {
    if (!ConnectivityService().isOnline) {
      return LocalDbService().getCachedRefiningProcessNames();
    }
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/refining/process-names'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body['data'] ?? []) as List;
        final names = list.map((p) => p.toString()).toList();
        await LocalDbService().cacheRefiningProcessNames(names);
        return names;
      }
      return await LocalDbService().getCachedRefiningProcessNames();
    } catch (_) {
      return await LocalDbService().getCachedRefiningProcessNames();
    }
  }

  // ── Smelting lots modal ─────────────────────────────────────────────────────
  // Online  → /refining/smelting-lots/:materialId + cache per materialId
  // Offline → refining_smelting_lot_cache for that materialId

  Future<List<RefiningSmeltingLot>> getSmeltingLots(
      String materialId, {
        String? excludeRefiningId,
      }) async {
    if (!ConnectivityService().isOnline) {
      return LocalDbService().getCachedRefiningSmeltingLots(materialId);
    }
    try {
      final excl = excludeRefiningId != null
          ? '?exclude_refining_id=$excludeRefiningId'
          : '';
      final res = await http
          .get(
        Uri.parse('$kBaseUrl/refining/smelting-lots/$materialId$excl'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body['data'] ?? []) as List;
        final lots = list.map((j) => RefiningSmeltingLot.fromJson(j)).toList();
        await LocalDbService().cacheRefiningSmeltingLots(materialId, lots);
        return lots;
      }
      return await LocalDbService()
          .getCachedRefiningSmeltingLots(materialId);
    } catch (_) {
      return await LocalDbService()
          .getCachedRefiningSmeltingLots(materialId);
    }
  }

  /// Preloads and caches smelting stock lots for all provided materialIds.
  /// This ensures refining stock modal works fully offline for any material.

  // Future<void> preloadSmeltingLotsForMaterials(
  //   List<String> materialIds,
  // ) async {
  //   if (!ConnectivityService().isOnline) return;
  //
  //   final uniqueIds = materialIds
  //       .map((e) => e.trim())
  //       .where((e) => e.isNotEmpty)
  //       .toSet()
  //       .toList();
  //
  //   for (final materialId in uniqueIds) {
  //     try {
  //       // excludeRefiningId intentionally not used for shared offline cache.
  //       await getSmeltingLots(materialId);
  //     } catch (_) {
  //       // Ignore per-material failures and continue preloading others.
  //     }
  //   }
  // }

  Future<void> preloadSmeltingLotsForMaterials() async {
    if (!ConnectivityService().isOnline) {
      return; // No internet → do nothing
    }

    try {
      final res = await http
          .get(
        Uri.parse('$kBaseUrl/smelting-batches/bbsu-lots/all'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body['data'] ?? []) as List;

        final lots = list
            .map((j) => RefiningSmeltingLot.fromJson(j))
            .toList();

        await LocalDbService().cacheAllRefiningSmeltingLots(lots);
      }
    } catch (e) {
      // optional: log error
    }
  }







  // ── Generate batch no ───────────────────────────────────────────────────────
  Future<String> generateBatchNo() async {
    if (!ConnectivityService().isOnline) return _fallback();
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/refining/generate-batch-no'),
          headers: _headers)
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
    final suffix = DateTime.now().millisecondsSinceEpoch.toString().substring(9);
    return 'RFN-$year-$suffix';
  }

  // ── List ────────────────────────────────────────────────────────────────────
  Future<RefiningListResult> getList({
    int page = 1,
    int perPage = 20,
    String? search,
    String? status,
    String? dateFrom,
    String? dateTo,
  }) async {
    if (!ConnectivityService().isOnline) {
      return _listFromLocal(search: search, status: status);
    }
    try {
      final params = {
        'page': '$page',
        'per_page': '$perPage',
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null && status != 'all') 'status': status,
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      };
      final uri = Uri.parse('$kBaseUrl/refining')
          .replace(queryParameters: params);
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      final body = jsonDecode(res.body);

      if (res.statusCode == 200) {
        final data    = body['data'];
        final list    = (data['data'] ?? data ?? []) as List;
        final total   = data['total'] ?? list.length;
        final records = list.map((j) => RefiningSummary.fromJson(j)).toList();
        if (page == 1 &&
            (search == null || search.isEmpty) &&
            (status == null || status == 'all')) {
          await LocalDbService().cacheRefiningRecords(records);
        }
        return RefiningListResult(records: records, total: total);
      }
      return _listFromLocal(search: search, status: status);
    } catch (_) {
      return _listFromLocal(search: search, status: status);
    }
  }

  Future<RefiningListResult> _listFromLocal({
    String? search,
    String? status,
  }) async {
    try {
      final cachedRows = await LocalDbService().getAllRefiningForDisplay();
      final queuedRows = await LocalDbService().getQueuedRefining();

      final queued = queuedRows.map((row) {
        final p = row['payload'] as Map<String, dynamic>;
        return RefiningSummary(
          id:          'queue_${row['queue_id']}',
          batchNo:     p['batch_no']?.toString() ?? '',
          date:        p['date']?.toString() ?? '',
          statusLabel: 'Draft',
          statusCode:  0,
          syncStatus:  'pending',
        );
      }).toList();

      final cached = cachedRows.map((r) => RefiningSummary.fromLocal(r)).toList();
      var all      = [...queued, ...cached];

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
      return RefiningListResult(records: all, total: all.length);
    } catch (e) {
      return RefiningListResult.error('Failed to load offline data.');
    }
  }

  // ── Load one ────────────────────────────────────────────────────────────────
  Future<RefiningRecord?> getOne(String id) async {
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/refining/$id'), headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        return RefiningRecord.fromJson(jsonDecode(res.body)['data']);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────────
  Future<RefiningSaveResult> save(
      Map<String, dynamic> payload, {
        String? id,
      }) async {
    if (!ConnectivityService().isOnline) {
      try {
        await LocalDbService().addToQueue(SyncOperation(
          operation: id == null
              ? SyncOperation.opCreate
              : SyncOperation.opUpdate,
          table:     'refining',
          serverId:  id,
          payload:   payload,
          createdAt: DateTime.now(),
        ));
        return const RefiningSaveResult(success: true, newId: null);
      } catch (e) {
        return RefiningSaveResult.error('Failed to save offline: $e');
      }
    }
    try {
      final isCreate = id == null;
      final uri = Uri.parse(
          isCreate ? '$kBaseUrl/refining' : '$kBaseUrl/refining/$id');
      final res = await (isCreate
          ? http.post(uri, headers: _headers, body: jsonEncode(payload))
          : http.put(uri, headers: _headers, body: jsonEncode(payload)))
          .timeout(const Duration(seconds: 25));
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        if (body['status'] == 'ok' || res.statusCode == 201) {
          return RefiningSaveResult(
            success: true,
            newId:   body['data']?['id']?.toString(),
          );
        }
      } else if (res.statusCode == 422) {
        return RefiningSaveResult(
          success:     false,
          errorMsg:    body['message'],
          fieldErrors: body['errors'] ?? {},
        );
      }
      return RefiningSaveResult.error(body['message'] ?? 'Save failed.');
    } catch (_) {
      return RefiningSaveResult.error('Network error. Could not save.');
    }
  }

  // ── Submit ───────────────────────────────────────────────────────────────────
  Future<String?> submit(String id) async {
    try {
      final res = await http
          .post(Uri.parse('$kBaseUrl/refining/$id/submit'),
          headers: _headers, body: '{}')
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) return null;
      return jsonDecode(res.body)['message'] ?? 'Submit failed.';
    } catch (_) {
      return 'Network error.';
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────────
  Future<String?> delete(String id) async {
    try {
      final res = await http
          .delete(Uri.parse('$kBaseUrl/refining/$id'), headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200 || res.statusCode == 204) return null;
      return jsonDecode(res.body)['message'] ?? 'Delete failed.';
    } catch (_) {
      return 'Network error. Could not delete.';
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  static String toIsoDateTime(String date, String time) {
    try {
      // Handle 12-hour format: "4:14 PM"
      if (time.toUpperCase().contains('AM') || time.toUpperCase().contains('PM')) {
        final parts = time.trim().split(' ');
        final timeParts = parts[0].split(':');
        int hour = int.parse(timeParts[0]);
        final int minute = int.parse(timeParts[1]);
        final String period = parts[1].toUpperCase();

        if (period == 'PM' && hour != 12) hour += 12;
        if (period == 'AM' && hour == 12) hour = 0;

        final String h = hour.toString().padLeft(2, '0');
        final String m = minute.toString().padLeft(2, '0');
        return '${date}T$h:$m:00';
      }

      // Handle 24-hour format: "16:14"
      final parts = time.split(':');
      final String h = parts[0].padLeft(2, '0');
      final String m = parts[1].padLeft(2, '0');
      return '${date}T$h:$m:00';

    } catch (_) {
      return '${date}T00:00:00';
    }
  }

  static String? toHHmm(String? isoDateTime) {
    if (isoDateTime == null || isoDateTime.isEmpty) return null;
    try {
      final dt = DateTime.parse(isoDateTime);
      int hour = dt.hour;
      final int minute = dt.minute;
      final String period = hour >= 12 ? 'PM' : 'AM';

      hour = hour % 12;
      if (hour == 0) hour = 12;

      final String m = minute.toString().padLeft(2, '0');
      return '$hour:$m $period';
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCAL DB ADDITIONS — merge into local_db_service.dart
// Version bump: 5 → 6
// ─────────────────────────────────────────────────────────────────────────────
//
// STEP 1: Bump version: 5 → 6
//
// STEP 2: Add inside onCreate() after smelting_bbsu_lot_cache block:
/*

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

*/
//
// STEP 3: Add inside onUpgrade() — if (oldVersion < 6) { same CREATE IF NOT EXISTS... }
//
// STEP 4: Add these methods to the LocalDbService class body:
/*


*/