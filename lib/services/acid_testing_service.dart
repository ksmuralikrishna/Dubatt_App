// ─────────────────────────────────────────────────────────────────────────────
// acid_testing_service.dart
// Offline-first service for the Acid Testing module.
//
// Mirrors the exact pattern from receiving_service.dart:
//   Online  → API call + cache to SQLite
//   Offline → read from SQLite cache + sync_queue
//
// API endpoints (from Blade JS):
//   GET    /acid-testings                  → list
//   GET    /acid-testings/:id              → single record
//   POST   /acid-testings                  → create
//   PUT    /acid-testings/:id              → update
//   PATCH  /acid-testings/:id/status       → submit
//   DELETE /acid-testings/:id              → delete
//   GET    /acid-testings/available-lots   → lot dropdown
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dubatt_app/services/auth_service.dart';
import 'package:dubatt_app/services/connectivity_service.dart';
import 'package:dubatt_app/services/local_db_service.dart';
import 'package:dubatt_app/models/acid_testing_model.dart';
import 'package:dubatt_app/models/sync_queue_model.dart';

// Base URL — same constant used in receiving_service.dart
// const kBaseUrl = 'https://your-api-domain.com/api'; // ← update to match your project

class AcidTestingService {
  static final AcidTestingService _i = AcidTestingService._();
  factory AcidTestingService() => _i;
  AcidTestingService._();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer ${AuthService().token}',
  };

  // ── Available lots dropdown ─────────────────────────────────────────────────
  // Online  → fetch from /acid-testings/available-lots + cache
  // Offline → serve from acid_lot_cache table

  Future<List<LotOption>> getAvailableLots() async {
    if (!ConnectivityService().isOnline) {
      return LocalDbService().getCachedAcidLots();
    }
    try {
      final res = await http
          .get(
        Uri.parse('$kBaseUrl/acid-testings/available-lots'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body['data'] ?? []) as List;
        final options = list.map((j) => LotOption.fromJson(j)).toList();
        await LocalDbService().cacheAcidLots(options);
        return options;
      }
      return await LocalDbService().getCachedAcidLots();
    } catch (_) {
      return await LocalDbService().getCachedAcidLots();
    }
  }

  // ── List ────────────────────────────────────────────────────────────────────
  // Online  → API results + cache page-1 / no-filter to SQLite
  // Offline → merge cached server records + sync_queue pending records

  Future<AcidTestingListResult> getList({
    int page = 1,
    int perPage = 20,
    String? search,
    String? status,
  }) async {
    if (!ConnectivityService().isOnline) {
      return _getListFromLocal(search: search, status: status);
    }

    try {
      final params = {
        'page': '$page',
        'per_page': '$perPage',
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null && status != 'all') 'status': status,
      };
      final uri = Uri.parse('$kBaseUrl/acid-testings')
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
            .map((j) => AcidTestingSummary.fromJson(j))
            .toList();

        // Cache page-1, no-filter results for offline use
        if (page == 1 &&
            (search == null || search.isEmpty) &&
            (status == null || status == 'all')) {
          await LocalDbService().cacheAcidTestings(records);
        }

        return AcidTestingListResult(records: records, total: total);
      }

      return _getListFromLocal(search: search, status: status);
    } catch (_) {
      return _getListFromLocal(search: search, status: status);
    }
  }

  // ── Offline list fallback ──────────────────────────────────────────────────
  // Merges:
  //   1. acid_testing_records — server-cached records
  //   2. sync_queue           — offline-created records (table = 'acid-testings')
  //
  // Pending records always shown at top (orange dot in list).

  Future<AcidTestingListResult> _getListFromLocal({
    String? search,
    String? status,
  }) async {
    try {
      // 1. Cached server records
      final cachedRows = await LocalDbService().getAllAcidTestingsForDisplay();

      // 2. Offline-created records from sync_queue
      final queuedRows = await LocalDbService().getQueuedAcidTestings();

      // 3. Map sync_queue rows → AcidTestingSummary
      final queuedSummaries = queuedRows.map((row) {
        final payload = row['payload'] as Map<String, dynamic>;
        return AcidTestingSummary(
          id:                          'queue_${row['queue_id']}',
          lotNumber:                   payload['lot_number']?.toString() ?? '',
          testDate:                    payload['test_date']?.toString() ?? '',
          supplierName:                payload['supplier_name']?.toString() ?? '—',
          vehicleNumber:               payload['vehicle_number']?.toString() ?? '—',
          avgPalletWeight:             _toDouble(payload['avg_pallet_weight']) ?? 0,
          foreignMaterialWeight:       _toDouble(payload['foreign_material_weight']) ?? 0,
          avgPalletAndForeignWeight:   _toDouble(payload['avg_pallet_and_foreign_weight']) ?? 0,
          receivedQty:                 _toDouble(payload['received_qty']) ?? 0,
          statusLabel:                 'Draft',
          statusCode:                  0,
          syncStatus:                  'pending',
          palletCount:                 (payload['details'] as List?)?.length ?? 0,
        );
      }).toList();

      // 4. Map cached server rows → AcidTestingSummary
      final cachedSummaries = cachedRows
          .map((r) => AcidTestingSummary.fromLocal(r))
          .toList();

      // 5. Merge: pending at top
      final allRecords = [...queuedSummaries, ...cachedSummaries];

      // 6. Apply search filter
      var filtered = allRecords;
      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        filtered = filtered.where((r) {
          return r.lotNumber.toLowerCase().contains(q) ||
              r.supplierName.toLowerCase().contains(q) ||
              r.vehicleNumber.toLowerCase().contains(q);
        }).toList();
      }

      // 7. Apply status filter
      if (status != null && status != 'all') {
        if (status == 'submitted') {
          filtered = filtered.where((r) => r.statusCode >= 1).toList();
        } else if (status == 'draft' || status == '0') {
          filtered = filtered.where((r) => r.statusCode == 0).toList();
        }
      }

      return AcidTestingListResult(
        records: filtered,
        total:   filtered.length,
      );
    } catch (e) {
      return AcidTestingListResult.error('Failed to load offline data.');
    }
  }

  // ── Load one ────────────────────────────────────────────────────────────────

  Future<AcidTestingRecord?> getOne(String id) async {
    // ── OFFLINE DRAFT INTERCEPT
    if (id.startsWith('queue_')) {
      final queueId = int.tryParse(id.substring(6));
      if (queueId == null) return null;
      
      final queueRow = await LocalDbService().getQueueItemById(queueId);
      if (queueRow == null) return null;
      
      final payload = jsonDecode(queueRow['payload'] as String) as Map<String, dynamic>;
      final rawDetails = payload['details'] as List? ?? [];
      
      return AcidTestingRecord(
        id: id,
        testDate: payload['test_date']?.toString() ?? '',
        lotNumber: payload['lot_number']?.toString() ?? '',
        supplierId: payload['supplier_id']?.toString() ?? '',
        supplierName: payload['supplier_name']?.toString() ?? '',
        vehicleNumber: payload['vehicle_number']?.toString() ?? '',
        avgPalletWeight: _toDouble(payload['avg_pallet_weight']) ?? 0,
        foreignMaterialWeight: _toDouble(payload['foreign_material_weight']) ?? 0,
        avgPalletAndForeignWeight: _toDouble(payload['avg_pallet_and_foreign_weight']) ?? 0,
        receivedQty: _toDouble(payload['received_qty']),
        invoiceQty: _toDouble(payload['invoice_qty']),
        details: rawDetails.map((d) => AcidTestingDetail.fromJson(d)).toList(),
        status: "0",
      );
    }

    try {
      final res = await http
          .get(
        Uri.parse('$kBaseUrl/acid-testings/$id'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        return AcidTestingRecord.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Save (create / update) ─────────────────────────────────────────────────
  // Online  → POST/PUT to API
  // Offline → add to sync_queue with table = 'acid-testings'
  //           The payload includes supplier_name so the list screen can
  //           show a meaningful name without a join.

  Future<AcidSaveResult> save(
      Map<String, dynamic> payload, {
        String? id,
        String? supplierName, // pass so offline list shows supplier name
      }) async {
    final isQueueEdit = id != null && id.startsWith('queue_');

    // ── OFFLINE path (or editing a queue item while online but before sync finishes)
    if (!ConnectivityService().isOnline || isQueueEdit) {
      try {
        // Embed supplier_name in payload for offline list display
        final offlinePayload = {
          ...payload,
          if (supplierName != null) 'supplier_name': supplierName,
        };

        if (isQueueEdit) {
          final queueId = int.parse(id!.substring(6));
          await LocalDbService().updateQueuePayload(queueId, offlinePayload);
          return AcidSaveResult(success: true, newId: id);
        } else {
          await LocalDbService().addToQueue(SyncOperation(
            operation: id == null
                ? SyncOperation.opCreate
                : SyncOperation.opUpdate,
            table:     'acid-testings',
            serverId:  id,
            payload:   offlinePayload,
            createdAt: DateTime.now(),
          ));
          return const AcidSaveResult(success: true, newId: null);
        }
      } catch (e) {
        return AcidSaveResult.error('Failed to save offline: $e');
      }
    }

    // ── ONLINE path ───────────────────────────────────────────────────────────
    try {
      final isCreate = id == null;
      final uri = Uri.parse(
        isCreate
            ? '$kBaseUrl/acid-testings'
            : '$kBaseUrl/acid-testings/$id',
      );
      final res = await (isCreate
          ? http.post(uri, headers: _headers, body: jsonEncode(payload))
          : http.put(uri, headers: _headers, body: jsonEncode(payload)))
          .timeout(const Duration(seconds: 20));

      final body = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        return AcidSaveResult(
          success: true,
          newId:   body['data']?['id']?.toString(),
        );
      } else if (res.statusCode == 422) {
        return AcidSaveResult(
          success:     false,
          errorMsg:    body['message'],
          fieldErrors: body['errors'] ?? {},
        );
      }
      return AcidSaveResult.error(body['message'] ?? 'Save failed.');
    } catch (_) {
      return AcidSaveResult.error('Network error. Could not save.');
    }
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  // Must be online — submit locks the record server-side.

  Future<String?> submit(String id) async {
    if (id.startsWith('queue_')) {
      return 'Cannot submit an offline draft. Please wait for it to sync to the server first.';
    }

    try {
      final res = await http
          .patch(
        Uri.parse('$kBaseUrl/acid-testings/$id/status'),
        headers: _headers,
        body: jsonEncode({'status': 1}),
      )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) return null; // null = success
      final body = jsonDecode(res.body);
      return body['message'] ?? 'Submit failed.';
    } catch (_) {
      return 'Network error.';
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<String?> delete(String id) async {
    // ── OFFLINE DRAFT INTERCEPT
    if (id.startsWith('queue_')) {
      try {
        final queueId = int.parse(id.substring(6));
        await LocalDbService().deleteQueueItem(queueId);
        return null;
      } catch (e) {
        return 'Failed to delete offline record: $e';
      }
    }

    try {
      final res = await http
          .delete(
        Uri.parse('$kBaseUrl/acid-testings/$id'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200 || res.statusCode == 204) return null;
      final body = jsonDecode(res.body);
      return body['message'] ?? 'Delete failed.';
    } catch (_) {
      return 'Network error. Could not delete.';
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}