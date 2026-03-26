import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dubatt_app/services/auth_service.dart';
import 'package:dubatt_app/services/connectivity_service.dart';
import 'package:dubatt_app/services/local_db_service.dart';
import 'package:dubatt_app/models/acid_testing_model.dart';
import 'package:dubatt_app/models/sync_queue_model.dart';

class AcidTestingService {
  static final AcidTestingService _i = AcidTestingService._();
  factory AcidTestingService() => _i;
  AcidTestingService._();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept':       'application/json',
    'Authorization': 'Bearer ${AuthService().token}',
  };

  // ── List ────────────────────────────────────────────────────────
  Future<AcidTestingListResult> getList({
    int page    = 1,
    int perPage = 20,
    String? search,
    String? status,
  }) async {
    if (!ConnectivityService().isOnline) {
      return _getListFromLocal(search: search, status: status);
    }

    try {
      final params = {
        'page':     '$page',
        'per_page': '$perPage',
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null && status != 'all')   'status': status,
      };
      final uri = Uri.parse('$kBaseUrl/acid-testings')
          .replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      final body = jsonDecode(res.body);

      if (res.statusCode == 200) {
        final data    = body['data'];
        final list    = (data['data'] ?? []) as List;
        final total   = data['total'] ?? list.length;
        final records = list
            .map((j) => AcidTestingSummary.fromJson(j as Map<String, dynamic>))
            .toList();

        // Cache page-1 with no filters for offline access
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

  // ── Local fallback ──────────────────────────────────────────────
  Future<AcidTestingListResult> _getListFromLocal({
    String? search,
    String? status,
  }) async {
    try {
      // Cached server records
      final cachedRows  = await LocalDbService().getAllAcidTestingsForDisplay();
      // Offline-created records from sync_queue
      final queuedRows  = await LocalDbService().getQueuedAcidTestings();

      final queuedSummaries = queuedRows.map((row) {
        final payload = row['payload'] as Map<String, dynamic>;
        return AcidTestingSummary(
          id:                        'queue_${row['queue_id']}',
          lotNumber:                 payload['lot_number']?.toString() ?? '',
          testDate:                  payload['test_date']?.toString() ?? '',
          supplierName:              payload['supplier_name']?.toString() ?? '-',
          vehicleNumber:             payload['vehicle_number']?.toString() ?? '-',
          avgPalletWeight:           _toDouble(payload['avg_pallet_weight']) ?? 0,
          foreignMaterialWeight:     _toDouble(payload['foreign_material_weight']) ?? 0,
          avgPalletAndForeignWeight: _toDouble(payload['avg_pallet_and_foreign_weight']) ?? 0,
          receivedQty:               _toDouble(payload['received_qty']) ?? 0,
          statusLabel:               'Pending',
          statusCode:                0,
          syncStatus:                'pending',
        );
      }).toList();

      final cachedSummaries = cachedRows
          .map((r) => AcidTestingSummary.fromLocal(r))
          .toList();

      var allRecords = [...queuedSummaries, ...cachedSummaries];

      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        allRecords = allRecords.where((r) =>
        r.lotNumber.toLowerCase().contains(q) ||
            r.supplierName.toLowerCase().contains(q) ||
            r.vehicleNumber.toLowerCase().contains(q)).toList();
      }

      if (status != null && status != 'all') {
        final label = status.replaceAll('_', ' ').toLowerCase();
        allRecords = allRecords
            .where((r) => r.statusLabel.toLowerCase() == label)
            .toList();
      }

      return AcidTestingListResult(
          records: allRecords, total: allRecords.length);
    } catch (e) {
      return AcidTestingListResult.error('Failed to load offline data.');
    }
  }

  // ── Load one ────────────────────────────────────────────────────
  Future<AcidTestingRecord?> getOne(String id) async {
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/acid-testings/$id'), headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        return AcidTestingRecord.fromJson(
            jsonDecode(res.body)['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Available lots dropdown ─────────────────────────────────────
  Future<List<LotOption>> getAvailableLots() async {
    if (!ConnectivityService().isOnline) {
      return LocalDbService().getCachedAcidLots();
    }
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/acid-testings/available-lots'),
          headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body['data'] ?? []) as List;
        final options = list
            .map((j) => LotOption.fromJson(j as Map<String, dynamic>))
            .toList();
        await LocalDbService().cacheAcidLots(options);
        return options;
      }
      return await LocalDbService().getCachedAcidLots();
    } catch (_) {
      return await LocalDbService().getCachedAcidLots();
    }
  }

  // ── Save (create / update) ──────────────────────────────────────
  Future<AcidTestingSaveResult> save(
      Map<String, dynamic> payload, {
        String? id,
      }) async {
    // Offline — queue only
    if (!ConnectivityService().isOnline) {
      try {
        await LocalDbService().addToQueue(SyncOperation(
          operation: id == null
              ? SyncOperation.opCreate
              : SyncOperation.opUpdate,
          table:     'acid-testings',
          serverId:  id,
          payload:   payload,
          createdAt: DateTime.now(),
        ));
        return const AcidTestingSaveResult(success: true, newId: null);
      } catch (e) {
        return AcidTestingSaveResult.error('Failed to save offline: $e');
      }
    }

    // Online
    try {
      final isCreate = id == null;
      final uri = Uri.parse(isCreate
          ? '$kBaseUrl/acid-testings'
          : '$kBaseUrl/acid-testings/$id');
      final res = await (isCreate
          ? http.post(uri, headers: _headers, body: jsonEncode(payload))
          : http.put(uri,  headers: _headers, body: jsonEncode(payload)))
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        return AcidTestingSaveResult(
          success: true,
          newId:   body['data']?['id']?.toString(),
        );
      } else if (res.statusCode == 422) {
        return AcidTestingSaveResult(
          success:     false,
          errorMsg:    body['message'],
          fieldErrors: body['errors'] ?? {},
        );
      }
      return AcidTestingSaveResult.error(body['message'] ?? 'Save failed.');
    } catch (_) {
      return AcidTestingSaveResult.error('Network error. Could not save.');
    }
  }

  // ── Submit  PATCH /acid-testings/{id}/status  {status: 1} ──────
  Future<String?> submit(String id) async {
    try {
      final res = await http
          .patch(
        Uri.parse('$kBaseUrl/acid-testings/$id/status'),
        headers: _headers,
        body: jsonEncode({'status': 1}),
      )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) return null;
      final body = jsonDecode(res.body);
      return body['message'] ?? 'Submit failed.';
    } catch (_) {
      return 'Network error.';
    }
  }

  // ── Delete ──────────────────────────────────────────────────────
  Future<String?> delete(String id) async {
    try {
      final res = await http
          .delete(Uri.parse('$kBaseUrl/acid-testings/$id'),
          headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200 || res.statusCode == 204) return null;
      final body = jsonDecode(res.body);
      return body['message'] ?? 'Delete failed.';
    } catch (_) {
      return 'Network error. Could not delete.';
    }
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}