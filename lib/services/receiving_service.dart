// import 'dart:convert';
// import 'package:dubatt_app/models/sync_queue_model.dart';
// import 'package:dubatt_app/services/connectivity_service.dart';
// import 'package:dubatt_app/services/local_db_service.dart';
// import 'package:http/http.dart' as http;
// import '../services/auth_service.dart';
// import '../models/receiving_model.dart';

import 'dart:convert';                    // ✅ must be first
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
  Future<ReceivingListResult> getList({
    int page = 1,
    int perPage = 20,
    String? search,
    String? status,
  }) async {
    try {
      final params = {
        'page': '$page',
        'per_page': '$perPage',
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null && status != 'all') 'status': status,
      };
      final uri = Uri.parse('$kBaseUrl/receivings')
          .replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      final body = jsonDecode(res.body);
      if (res.statusCode == 200) {
        final data   = body['data'];
        final list   = (data['data'] ?? data ?? []) as List;
        final total  = data['total'] ?? list.length;
        return ReceivingListResult(
          records: list.map((j) => ReceivingSummary.fromJson(j)).toList(),
          total: total,
        );
      }
      return ReceivingListResult.error(body['message'] ?? 'Failed to load records.');
    } catch (e) {
      return ReceivingListResult.error('Network error. Check your connection.');
    }
  }

  // ── Load one ────────────────────────────────────────────────────
  Future<ReceivingRecord?> getOne(String id) async {
    try {
      final res = await http.get(
        Uri.parse('$kBaseUrl/receivings/$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        return ReceivingRecord.fromJson(data);
      }
      return null;
    } catch (_) { return null; }
  }

  // ── Generate lot no ─────────────────────────────────────────────
  Future<String?> generateLotNo() async {
    try {
      final res = await http.get(
        Uri.parse('$kBaseUrl/receivings/generate-lot-no'),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['lot_no'] ?? data['data']?['lot_no'];
      }
      return null;
    } catch (_) { return null; }
  }

  // ── Materials dropdown ──────────────────────────────────────────
  // Future<List<MaterialOption>> getMaterials() async {
  //   try {
  //     final res = await http.get(
  //       Uri.parse('$kBaseUrl/materials?per_page=500'),
  //       headers: _headers,
  //     ).timeout(const Duration(seconds: 10));
  //     print('📦 Materials status: ${res.statusCode}');      // check status
  //     print('📦 Materials body: ${res.body}');
  //     if (res.statusCode == 200) {
  //       final body = jsonDecode(res.body);
  //       final list = body['data']?['data'] ?? body['data'] ?? [];
  //       return (list as List).map((j) => MaterialOption.fromJson(j)).toList();
  //     }
  //     return [];
  //   } catch (_) { return []; }
  // }
  // Future<List<SupplierOption>> getSuppliers() async {
  //   try {
  //     final res = await http.get(
  //       Uri.parse('$kBaseUrl/suppliers'),
  //       headers: _headers,
  //     ).timeout(const Duration(seconds: 10));
  //     if (res.statusCode == 200) {
  //       final body = jsonDecode(res.body);
  //       final list = body['data']?['data'] ?? body['data'] ?? [];
  //       return (list as List).map((j) => SupplierOption.fromJson(j)).toList();  // ✅
  //     }
  //     return [];
  //   } catch (_) { return []; }
  // }
  Future<List<MaterialOption>> getMaterials() async {
    try {
      final res = await http.get(
        Uri.parse('$kBaseUrl/materials?per_page=500'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = body['data']?['data'] ?? body['data'] ?? [];
        final options = (list as List).map((j) => MaterialOption.fromJson(j)).toList();
        await LocalDbService().cacheDropdown('material', options); // ✅ cache for offline
        return options;
      }
      return await LocalDbService().getCachedMaterials(); // fallback
    } catch (_) {
      return await LocalDbService().getCachedMaterials(); // fallback
    }
  }

  Future<List<SupplierOption>> getSuppliers() async {
    try {
      final res = await http.get(
        Uri.parse('$kBaseUrl/suppliers'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = body['data']?['data'] ?? body['data'] ?? [];
        final options = (list as List).map((j) => SupplierOption.fromJson(j)).toList();
        await LocalDbService().cacheDropdown('supplier', options); // ✅ cache for offline
        return options;
      }
      return await LocalDbService().getCachedSuppliers(); // fallback
    } catch (_) {
      return await LocalDbService().getCachedSuppliers(); // fallback
    }
  }
  // ── Save (create / update) ──────────────────────────────────────
  Future<SaveResult> save(Map<String, dynamic> payload, {String? id}) async {
    if (!ConnectivityService().isOnline) {
      // Save locally
      final localId = await LocalDbService().insertReceiving(payload);
      // Add to sync queue
      await LocalDbService().addToQueue(SyncOperation(
        operation: id == null ? SyncOperation.opCreate : SyncOperation.opUpdate,
        table:     'receivings',
        serverId:  id,
        payload:   payload,
        createdAt: DateTime.now(),
      ));
      return SaveResult.ok(null); // pending — will sync later
    }
    try {
      final isCreate = id == null;
      final uri = Uri.parse(isCreate
          ? '$kBaseUrl/receivings'
          : '$kBaseUrl/receivings/$id');
      final res = await (isCreate
          ? http.post(uri, headers: _headers, body: jsonEncode(payload))
          : http.put(uri,  headers: _headers, body: jsonEncode(payload)))
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return SaveResult.ok(body['data']?['id']?.toString());
      } else if (res.statusCode == 422) {
        return SaveResult.validation(body['errors'] ?? {}, body['message']);
      }
      return SaveResult.error(body['message'] ?? 'Save failed.');
    } catch (_) {
      return SaveResult.error('Network error. Could not save.');
    }
  }

  // ── Submit ──────────────────────────────────────────────────────
  Future<String?> submit(String id) async {
    try {
      final res = await http.post(
        Uri.parse('$kBaseUrl/receivings/$id/submit'),
        headers: _headers,
        body: '{}',
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) return null; // null = success
      final body = jsonDecode(res.body);
      return body['message'] ?? 'Submit failed.';
    } catch (_) {
      return 'Network error.';
    }
  }
}

class ReceivingListResult {
  final List<ReceivingSummary> records;
  final int total;
  final String? errorMsg;
  bool get hasError => errorMsg != null;

  ReceivingListResult({required this.records, required this.total})
      : errorMsg = null;
  ReceivingListResult.error(this.errorMsg)
      : records = [], total = 0;
}

class SaveResult {
  final bool success;
  final String? newId;
  final String? errorMsg;
  final Map<String, dynamic> fieldErrors;

  SaveResult.ok(this.newId)
      : success = true, errorMsg = null, fieldErrors = {};
  SaveResult.error(this.errorMsg)
      : success = false, newId = null, fieldErrors = {};
  SaveResult.validation(this.fieldErrors, this.errorMsg)
      : success = false, newId = null;
}
