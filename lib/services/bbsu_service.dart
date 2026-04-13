import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dubatt_app/services/auth_service.dart';
import 'package:dubatt_app/services/connectivity_service.dart';
import 'package:dubatt_app/services/local_db_service.dart';
import 'package:dubatt_app/models/bbsu_model.dart';
import 'package:dubatt_app/models/sync_queue_model.dart';
import 'package:intl/intl.dart';

// const kBaseUrl = 'https://your-api-domain.com/api'; // ← FIX 1: was commented out

class BbsuService {
  static final BbsuService _i = BbsuService._();
  factory BbsuService() => _i;
  BbsuService._();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer ${AuthService().token}',
  };

  Future<List<BbsuLotOption>> getAvailableLots() async {
    if (!ConnectivityService().isOnline) {
      return LocalDbService().getCachedBbsuLots();
    }
    try {
      final res = await http
          .get(
        Uri.parse('$kBaseUrl/bbsu-batches/acid-test-lot-numbers'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);

        if (body['status'] == 'ok' && body['data'] is List) {
          final List list = body['data'];



          final options =
          list.map((j) => BbsuLotOption.fromJson(j)).toList();

          await LocalDbService().cacheBbsuLots(options);
          return options;
        }
      }
      return await LocalDbService().getCachedBbsuLots();
    } catch (_) {
      return await LocalDbService().getCachedBbsuLots();
    }
  }

  Future<List<Map<String, dynamic>>?> getAcidSummary(String lotNo) async {
    // ── OFFLINE path ──────────────────────────────────────────────────────────
    if (!ConnectivityService().isOnline) {
      final cached = await LocalDbService().getCachedAcidSummary(lotNo);
      // Return cached rows if available, otherwise return null so the
      // caller (_QtyModal) falls back to the simple cached-receivedQty row.
      return cached.isNotEmpty ? cached : null;
    }

    // ── ONLINE path ───────────────────────────────────────────────────────────
    try {
      final res = await http
          .get(
        Uri.parse(
            '$kBaseUrl/bbsu-batches/acid-summary/${Uri.encodeComponent(lotNo)}'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body['data'] as List? ?? [])
            .cast<Map<String, dynamic>>();

        // Cache all rows for this lot — replaces any previous cache
        if (list.isNotEmpty) {
          await LocalDbService().cacheAcidSummary(lotNo, list);
        }

        return list;
      }

      // Non-200 — try to serve from cache before giving up
      final cached = await LocalDbService().getCachedAcidSummary(lotNo);
      return cached.isNotEmpty ? cached : null;
    } catch (_) {
      // Network error — serve from cache if available
      final cached = await LocalDbService().getCachedAcidSummary(lotNo);
      return cached.isNotEmpty ? cached : null;
    }
  }

  /// Preload acid summary rows for all provided lot numbers.
  /// This is used to make BBSU qty modal fully usable offline.
  Future<void> preloadAcidSummariesForLots(List<String> lotNos) async {
    if (!ConnectivityService().isOnline) return;

    // Avoid duplicate requests for repeated lot numbers.
    final uniqueLotNos = lotNos
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    for (final lotNo in uniqueLotNos) {
      try {
        await getAcidSummary(lotNo);
      } catch (_) {
        // Ignore per-lot failures; continue preloading remaining lots.
      }
    }
  }

  Future<String> generateBatchNo() async {
    if (!ConnectivityService().isOnline) {
      return _fallbackBatchNo();
    }
    try {
      final res = await http
          .get(
        Uri.parse('$kBaseUrl/bbsu-batches/generate-batch-no'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['batch_no']?.toString() ?? _fallbackBatchNo();
      }
      return _fallbackBatchNo();
    } catch (_) {
      return _fallbackBatchNo();
    }
  }

  String _fallbackBatchNo() {
    final year = DateTime.now().year;
    final suffix = DateTime.now().millisecondsSinceEpoch
        .toString()
        .substring(9);
    return 'BBSU-$year-$suffix';
  }

  Future<BbsuListResult> getList({
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
      final uri = Uri.parse('$kBaseUrl/bbsu-batches')
          .replace(queryParameters: params);
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      final body = jsonDecode(res.body);

      if (res.statusCode == 200) {
        final data    = body['data'];
        final list    = (data['data'] ?? []) as List;
        final total   = data['total'] ?? list.length;
        final records = list.map((j) => BbsuSummary.fromJson(j)).toList();

        if (page == 1 &&
            (search == null || search.isEmpty) &&
            (status == null || status == 'all')) {
          await LocalDbService().cacheBbsuRecords(records);
        }

        return BbsuListResult(records: records, total: total);
      }

      return _getListFromLocal(search: search, status: status);
    } catch (_) {
      return _getListFromLocal(search: search, status: status);
    }
  }

  Future<BbsuListResult> _getListFromLocal({
    String? search,
    String? status,
  }) async {
    try {
      final cachedRows = await LocalDbService().getAllBbsuForDisplay();
      final queuedRows = await LocalDbService().getQueuedBbsu();

      final queuedSummaries = queuedRows.map((row) {
        final payload = row['payload'] as Map<String, dynamic>;
        return BbsuSummary(
          id:          'queue_${row['queue_id']}',
          batchNo:     payload['batch_no']?.toString() ?? '',
          docDate:     payload['doc_date']?.toString() ?? '',
          startTime:   payload['start_time']?.toString() ?? '',
          endTime:     payload['end_time']?.toString() ?? '',
          category:    payload['category']?.toString() ?? '',
          statusLabel: 'Draft',
          statusCode:  0,
          syncStatus:  'pending',
        );
      }).toList();

      final cachedSummaries =
      cachedRows.map((r) => BbsuSummary.fromLocal(r)).toList();

      final allRecords = [...queuedSummaries, ...cachedSummaries];

      // Search filter
      var filtered = allRecords;
      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        filtered = filtered.where((r) {
          return r.batchNo.toLowerCase().contains(q) ||
              r.category.toLowerCase().contains(q);
        }).toList();
      }

      // Status filter — FIX 2: removed stray `final code = r.statusCode ?? 0`
      // that was outside the where() closure
      if (status != null && status != 'all') {
        if (status == 'submitted' || status == '1') {
          filtered =
              filtered.where((r) => r.statusCode >= 1).toList();
        } else if (status == 'draft' || status == '0') {
          filtered =
              filtered.where((r) => r.statusCode == 0).toList();
        }
      }

      return BbsuListResult(records: filtered, total: filtered.length);
    } catch (e) {
      return BbsuListResult.error('Failed to load offline data.');
    }
  }

  Future<BbsuRecord?> getOne(String id) async {
    // ── OFFLINE DRAFT INTERCEPT
    if (id.startsWith('queue_')) {
      final queueId = int.tryParse(id.substring(6));
      if (queueId == null) return null;
      
      final queueRow = await LocalDbService().getQueueItemById(queueId);
      if (queueRow == null) return null;
      
      final payload = jsonDecode(queueRow['payload'] as String) as Map<String, dynamic>;
      
      final rawInputs = payload['input_details'] as List? ?? [];
      final inputs = rawInputs.map((d) => BbsuInputDetail.fromJson(d)).toList();

      final rawOutputMat = payload['output_material'] as Map<String, dynamic>? ?? {};
      final outputs = <String, BbsuOutputDetail>{};
      for (final kv in rawOutputMat.entries) {
        final code = kv.key;
        final data = kv.value;
        outputs[code] = BbsuOutputDetail(
           materialCode: code,
           qty: double.tryParse(data['qty']?.toString() ?? '0') ?? 0,
           yieldPct: 0,
        );
      }
      
      BbsuPowerConsumption? power;
      if (payload['power_consumption'] != null) {
        power = BbsuPowerConsumption.fromJson(payload['power_consumption'] as Map<String, dynamic>);
      }
      
      return BbsuRecord(
        id: id,
        batchNo: payload['batch_no']?.toString() ?? '',
        docDate: payload['doc_date']?.toString() ?? '',
        category: payload['category']?.toString() ?? 'BBSU',
        startTime: payload['start_time']?.toString() ?? '',
        endTime: payload['end_time']?.toString() ?? '',
        inputDetails: inputs,
        outputMaterials: outputs,
        powerConsumption: power,
        status: "0",
      );
    }

    try {
      final res = await http
          .get(
        Uri.parse('$kBaseUrl/bbsu-batches/$id'),
        headers: _headers,
      )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        return BbsuRecord.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<BbsuSaveResult> save(
      Map<String, dynamic> payload, {
        String? id,
      }) async {
    final isQueueEdit = id != null && id.startsWith('queue_');

    if (!ConnectivityService().isOnline || isQueueEdit) {
      try {
        if (isQueueEdit) {
          final queueId = int.parse(id!.substring(6));
          await LocalDbService().updateQueuePayload(queueId, payload);
          return BbsuSaveResult(success: true, newId: id);
        } else {
          await LocalDbService().addToQueue(SyncOperation(
            operation: id == null
                ? SyncOperation.opCreate
                : SyncOperation.opUpdate,
            table:     'bbsu-batches',
            serverId:  id,
            payload:   payload,
            createdAt: DateTime.now(),
          ));
          return const BbsuSaveResult(success: true, newId: null);
        }
      } catch (e) {
        return BbsuSaveResult.error('Network error: ${e.toString()}');
      }
    }

    try {
      final isCreate = id == null;
      final uri = Uri.parse(
        isCreate
            ? '$kBaseUrl/bbsu-batches'
            : '$kBaseUrl/bbsu-batches/$id',
      );
      final res = await (isCreate
          ? http.post(uri, headers: _headers, body: jsonEncode(payload))
          : http.put(uri,  headers: _headers, body: jsonEncode(payload)))
          .timeout(const Duration(seconds: 20));

      final body = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        return BbsuSaveResult(
          success: true,
          newId:   body['data']?['id']?.toString(),
        );
      } else if (res.statusCode == 422) {
        return BbsuSaveResult(
          success:     false,
          errorMsg:    body['message'],
          fieldErrors: body['errors'] ?? {},
        );
      }
      print("FULL RESPONSE: ${res.body}");

      return BbsuSaveResult.error(
          body['error'] ?? body['message'] ?? 'Save failed.'
      );
    } catch (e) {
      print('Network/parsing error: $e');
      return BbsuSaveResult.error('Network error: ${e.toString()}');
    }
  }

  Future<String?> submit(String id) async {
    if (id.startsWith('queue_')) {
      return 'Cannot submit an offline draft. Please wait for it to sync to the server first.';
    }

    try {
      final res = await http
          .patch(
        Uri.parse('$kBaseUrl/bbsu-batches/$id/status'),
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

  Future<String?> delete(String id) async {
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
        Uri.parse('$kBaseUrl/bbsu-batches/$id'),
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

  static String formatForDatetimeLocal(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      return DateFormat('yyyy-MM-ddTHH:mm').format(d);
    } catch (_) {
      return iso.length >= 16 ? iso.substring(0, 16) : iso;
    }
  }
}