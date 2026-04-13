import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dubatt_app/services/auth_service.dart';
import 'package:dubatt_app/services/connectivity_service.dart';
import 'package:dubatt_app/services/local_db_service.dart';
import 'package:dubatt_app/models/receiving_model.dart';
import 'package:dubatt_app/models/sync_queue_model.dart';

class ReceivingService {
  static final ReceivingService _i = ReceivingService._();
  factory ReceivingService() => _i;
  ReceivingService._();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer ${AuthService().token}',
  };

  // ── List ────────────────────────────────────────────────────────
  // Online  → API results only (sync_queue records hidden until synced)
  //           + cache page-1 results to SQLite for offline use
  // Offline → merge cached server records (receiving_records)
  //           + offline-created records (sync_queue CREATE ops)

  Future<ReceivingListResult> getList({
    int page = 1,
    int perPage = 20,
    String? search,
    String? status,
  }) async {
    // ── OFFLINE path
    if (!ConnectivityService().isOnline) {
      return _getListFromLocal(search: search, status: status);
    }

    // ── ONLINE path
    try {
      final params = {
        'page': '$page',
        'per_page': '$perPage',
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null && status != 'all') 'status': status,
      };
      final uri = Uri.parse('$kBaseUrl/receivings')
          .replace(queryParameters: params);
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      final body = jsonDecode(res.body);

      if (res.statusCode == 200) {
        final data    = body['data'];
        final list    = (data['data'] ?? []) as List;
        final total   = data['total'] ?? list.length;
        final records = list.map((j) => ReceivingSummary.fromJson(j)).toList();

        // Cache to SQLite on page 1 with no active filters
        // so offline access always has the latest server data
        if (page == 1 &&
            (search == null || search.isEmpty) &&
            (status == null || status == 'all')) {
          await LocalDbService().cacheServerReceivings(records);
        }

        // Online → API results only, no sync_queue records shown
        return ReceivingListResult(records: records, total: total);
      }

      // Non-200 → fall back to local
      return _getListFromLocal(search: search, status: status);
    } catch (_) {
      // Network error → fall back to local
      return _getListFromLocal(search: search, status: status);
    }
  }

  // ── Local fallback ──────────────────────────────────────────────
  // Merges two sources:
  //   1. receiving_records  — server-cached records (sync_status = 'synced')
  //   2. sync_queue         — offline-created records (operation = 'CREATE')
  //
  // Pending records always shown at top, then cached records.
  // Supplier/material names for queue records resolved from dropdown cache.

  Future<ReceivingListResult> _getListFromLocal({
    String? search,
    String? status,
  }) async {
    try {
      // ── 1. Load cached server records
      final cachedRows = await LocalDbService().getAllReceivingsForDisplay();

      // ── 2. Load offline-created records from sync_queue
      final queuedRows = await LocalDbService().getQueuedReceivings();

      // ── 3. Build id → name lookup maps from dropdown cache
      //       sync_queue payload only has supplier_id / material_id,
      //       so we resolve the display names here
      final materials  = await LocalDbService().getCachedMaterials();
      final suppliers  = await LocalDbService().getCachedSuppliers();
      final materialMap = { for (final m in materials) m.id: m.name };
      final supplierMap = { for (final s in suppliers) s.id: s.name };

      // ── 4. Map sync_queue rows → ReceivingSummary
      //       These go at the TOP of the list (pending records first)
      final queuedSummaries = queuedRows.map((row) {
        final payload    = row['payload'] as Map<String, dynamic>;
        final supplierId = payload['supplier_id']?.toString() ?? '';
        final materialId = payload['material_id']?.toString() ?? '';

        return ReceivingSummary(
          // Prefix with 'queue_' so it never clashes with a server id
          id:               'queue_${row['queue_id']}',
          // lot_no comes from what the user typed in the form
          lotNo:            payload['lot_no']?.toString() ?? '',
          receiptDate:      payload['receipt_date']?.toString() ?? '',
          // Resolve names from dropdown cache using the stored ids
          materialName:     materialMap[materialId] ?? materialId,
          materialCategory: '-',
          supplierName:     supplierMap[supplierId] ?? supplierId,
          receivedQty:      _toDouble(payload['received_qty']) ?? 0.0,
          unit:             payload['unit']?.toString() ?? '',
          statusLabel:      'Pending',
          statusCode:       0,
          syncStatus:       'pending', // shows orange dot in list
        );
      }).toList();

      // ── 5. Map cached server rows → ReceivingSummary
      final cachedSummaries = cachedRows
          .map((r) => ReceivingSummary.fromLocal(r))
          .toList();

      // ── 6. Merge: pending at top, then cached server records
      final allRecords = [...queuedSummaries, ...cachedSummaries];

      // ── 7. Apply search filter across the merged list
      var filtered = allRecords;
      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        filtered = filtered.where((r) {
          return r.lotNo.toLowerCase().contains(q) ||
              r.supplierName.toLowerCase().contains(q) ||
              r.materialName.toLowerCase().contains(q);
        }).toList();
      }

      // ── 8. Apply status filter
      //       Note: all queue records have statusLabel = 'Pending'
      //       so filtering by 'approved' / 'in_progress' hides them,
      //       which is correct behaviour
      if (status != null && status != 'all') {
        final filterLabel = status.replaceAll('_', ' ').toLowerCase();
        filtered = filtered.where((r) {
          return r.statusLabel.toLowerCase() == filterLabel;
        }).toList();
      }

      return ReceivingListResult(
        records: filtered,
        total:   filtered.length,
      );
    } catch (e) {
      return ReceivingListResult.error('Failed to load offline data.');
    }
  }

  // ── Load one ────────────────────────────────────────────────────
  Future<ReceivingRecord?> getOne(String id) async {
    // ── OFFLINE DRAFT INTERCEPT
    if (id.startsWith('queue_')) {
      final queueId = int.tryParse(id.substring(6));
      if (queueId == null) return null;
      
      final queueRow = await LocalDbService().getQueueItemById(queueId);
      if (queueRow == null) return null;
      
      final payload = jsonDecode(queueRow['payload'] as String) as Map<String, dynamic>;
      
      return ReceivingRecord(
        id: id,
        lotNo: payload['lot_no']?.toString() ?? '',
        docDate: payload['receipt_date']?.toString() ?? '',
        supplierId: payload['supplier_id']?.toString() ?? '',
        materialId: payload['material_id']?.toString() ?? '',
        invoiceQty: _toDouble(payload['invoice_qty']),
        receiveQty: _toDouble(payload['received_qty']),
        unit: payload['unit']?.toString() ?? '',
        vehicleNo: payload['vehicle_number']?.toString() ?? '',
        remarks: payload['remarks']?.toString() ?? '',
        status: "0",
      );
    }

    try {
      final res = await http
          .get(
        Uri.parse('$kBaseUrl/receivings/$id'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        return ReceivingRecord.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Generate lot no ─────────────────────────────────────────────
  Future<String?> generateLotNo() async {
    try {
      final res = await http
          .get(
        Uri.parse('$kBaseUrl/receiving-lots/generate-lot-no'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['lot_no'] ?? data['data']?['lot_no'];
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Materials dropdown ──────────────────────────────────────────
  // Online  → fetch from API + cache to SQLite
  // Offline → serve from SQLite cache

  Future<List<MaterialOption>> getMaterials() async {
    if (!ConnectivityService().isOnline) {
      return LocalDbService().getCachedMaterials();
    }
    try {
      final res = await http
          .get(
        Uri.parse('$kBaseUrl/materials?per_page=500'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body    = jsonDecode(res.body);
        final list    = body['data']?['data'] ?? body['data'] ?? [];
        final options = (list as List)
            .map((j) => MaterialOption.fromJson(j))
            .toList();
        await LocalDbService().cacheDropdown('material', options);
        return options;
      }
      return await LocalDbService().getCachedMaterials();
    } catch (_) {
      return await LocalDbService().getCachedMaterials();
    }
  }

  // ── Suppliers dropdown ──────────────────────────────────────────
  Future<List<SupplierOption>> getSuppliers() async {
    if (!ConnectivityService().isOnline) {
      return LocalDbService().getCachedSuppliers();
    }
    try {
      final res = await http
          .get(
        Uri.parse('$kBaseUrl/suppliers'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body    = jsonDecode(res.body);
        final list    = body['data']?['data'] ?? body['data'] ?? [];
        final options = (list as List)
            .map((j) => SupplierOption.fromJson(j))
            .toList();
        await LocalDbService().cacheDropdown('supplier', options);
        return options;
      }
      return await LocalDbService().getCachedSuppliers();
    } catch (_) {
      return await LocalDbService().getCachedSuppliers();
    }
  }

  // ── Save (create / update) ──────────────────────────────────────
  // Online  → POST/PUT to API
  // Offline → add to sync_queue only (no receiving_records insert)
  //           List reads sync_queue directly to show pending records

  Future<SaveResult> save(Map<String, dynamic> payload, {String? id}) async {
    final isQueueEdit = id != null && id.startsWith('queue_');

    // ── OFFLINE path (or editing a queue item while online but before sync finishes)
    if (!ConnectivityService().isOnline || isQueueEdit) {
      try {
        if (isQueueEdit) {
          final queueId = int.parse(id!.substring(6));
          await LocalDbService().updateQueuePayload(queueId, payload);
          return SaveResult(success: true, newId: id);
        } else {
          // Only queue the operation — receiving_records is for server cache only
          await LocalDbService().addToQueue(SyncOperation(
            operation: id == null
                ? SyncOperation.opCreate
                : SyncOperation.opUpdate,
            table:     'receivings',
            serverId:  id,
            payload:   payload,
            createdAt: DateTime.now(),
          ));
          return const SaveResult(success: true, newId: null);
        }
      } catch (e) {
        return SaveResult.error('Failed to save offline: $e');
      }
    }

    // ── ONLINE path
    try {
      final isCreate = id == null;
      final uri = Uri.parse(
          isCreate ? '$kBaseUrl/receivings' : '$kBaseUrl/receivings/$id');
      final res = await (isCreate
          ? http.post(uri, headers: _headers, body: jsonEncode(payload))
          : http.put(uri, headers: _headers, body: jsonEncode(payload)))
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        return SaveResult(
          success: true,
          newId:   body['data']?['id']?.toString(),
        );
      } else if (res.statusCode == 422) {
        return SaveResult(
          success:     false,
          errorMsg:    body['message'],
          fieldErrors: body['errors'] ?? {},
        );
      }
      return SaveResult.error(body['message'] ?? 'Save failed.');
    } catch (_) {
      return SaveResult.error('Network error. Could not save.');
    }
  }
  // ── Delete ──────────────────────────────────────────────────────
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
      final res = await http.delete(
        Uri.parse('$kBaseUrl/receivings/$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200 || res.statusCode == 204) return null;
      final body = jsonDecode(res.body);
      return body['message'] ?? 'Delete failed.';
    } catch (_) {
      return 'Network error. Could not delete.';
    }
  }

  // ── Submit ──────────────────────────────────────────────────────
  Future<String?> submit(String id) async {
    if (id.startsWith('queue_')) {
      return 'Cannot submit an offline draft. Please wait for it to sync to the server first.';
    }

    try {
      final res = await http
          .patch(
        Uri.parse('$kBaseUrl/receivings/$id/status'),
        headers: _headers,
        body: jsonEncode({'status': 1}), // 1 = Approved
      )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) return null; // null = success
      final body = jsonDecode(res.body);
      return body['message'] ?? 'Submit failed.';
    } catch (_) {
      return 'Network error.';
    }
  }

  // ── Private helpers ─────────────────────────────────────────────

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}