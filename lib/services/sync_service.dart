import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/conflict_resolver.dart';
import '../models/sync_queue_model.dart';
import '../services/receiving_service.dart';
import '../services/acid_testing_service.dart';
import '../services/bbsu_service.dart';
import '../services/smelting_service.dart';
import '../services/refining_service.dart';

enum SyncState { idle, syncing, done, failed }

class SyncService {
  static final SyncService _i = SyncService._();
  factory SyncService() => _i;
  SyncService._();

  SyncState _state = SyncState.idle;
  SyncState get state => _state;

  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  final List<String> _errors = [];
  List<String> get errors => List.unmodifiable(_errors);

  final _stateController = StreamController<SyncState>.broadcast();
  Stream<SyncState> get stateStream => _stateController.stream;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer ${AuthService().token}',
  };

  /// Manually downloads and caches master data used across modules so that
  /// dropdowns and stock/lot modals work offline.
  ///
  /// This is intentionally idempotent — calling it multiple times just refreshes
  /// local caches from the server.
  Future<void> downloadMasterData() async {
    // Receiving: materials + suppliers
    final receiving = ReceivingService();
    await receiving.getMaterials();  // caches material dropdown
    await receiving.getSuppliers();  // caches supplier dropdown

    // Acid testing: available lots + first page of list (for offline view)
    final acid = AcidTestingService();
    await acid.getAvailableLots(); // caches acid_lot_cache
    await acid.getList(page: 1, perPage: 50);       // caches acid_testing_records

    // BBSU: available lots + acid summary per lot (for qty modal offline)
    final bbsu = BbsuService();
    await bbsu.getAvailableLots(); // caches bbsu_lot_cache
    // await bbsu.preloadAcidSummariesForLots(
    //   bbsuLots.map((l) => l.lotNumber).toList(),
    // );
    await bbsu.preloadAllAcidSummariesForLots();


    // Smelting: materials + BBSU stock per material
    final smelting = SmeltingService();
    await smelting.getMaterials();
    await smelting.preloadBbsuLotsForMaterials();

    // Refining: materials + process names + smelting stock per material
    final refining = RefiningService();
    await refining.getProcessNames();                   // caches refining_process_name_cache
    await refining.preloadSmeltingLotsForMaterials();
    await refining.getMaterials();
  }

  Future<void> syncAll() async {
    if (_state == SyncState.syncing) return; // already running

    _errors.clear();
    _setState(SyncState.syncing);

    final ops = await LocalDbService().getPendingOps();
    _pendingCount = ops.length;

    if (ops.isEmpty) {
      _setState(SyncState.done);
      return;
    }

    for (final op in ops) {
      await _processOp(op);
    }

    _pendingCount = await LocalDbService().getPendingCount();
    _setState(_errors.isEmpty ? SyncState.done : SyncState.failed);
  }

  Future<void> _processOp(SyncOperation op) async {
    try {
      if (op.operation == SyncOperation.opCreate) {
        await _handleCreate(op);
      } else if (op.operation == SyncOperation.opUpdate) {
        await _handleUpdate(op);
      }
    } catch (e) {
      await LocalDbService().incrementRetry(op.localId!, e.toString());
      _errors.add('Failed: ${op.table} op ${op.localId} — $e');
    }
  }

  Future<void> _handleCreate(SyncOperation op) async {
    final uri = Uri.parse('$kBaseUrl/${op.table}');
    final res = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode(op.payload),
    ).timeout(const Duration(seconds: 15));

    final body = jsonDecode(res.body);

    if (res.statusCode == 200 || res.statusCode == 201) {
      final serverId = body['data']?['id']?.toString();
      if (serverId != null && op.localId != null) {
        // await LocalDbService().markSynced(op.localId!, serverId);
      }
      await LocalDbService().deleteQueueItem(op.localId!);
    } else if (res.statusCode == 422) {
      // Validation error — remove from queue, log error
      _errors.add('Validation error on ${op.table}: ${body['message']}');
      await LocalDbService().deleteQueueItem(op.localId!);
    } else {
      await LocalDbService().incrementRetry(
        op.localId!, body['message'] ?? 'HTTP ${res.statusCode}',
      );
    }
  }

  Future<void> _handleUpdate(SyncOperation op) async {
    if (op.serverId == null) return;

    // 1. Fetch current server record to check for conflict
    final getRes = await http.get(
      Uri.parse('$kBaseUrl/${op.table}/${op.serverId}'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));

    if (getRes.statusCode == 200) {
      final serverRecord =
      (jsonDecode(getRes.body)['data'] as Map<String, dynamic>);

      // 2. Resolve conflict
      final result = ConflictResolver().resolve(
        localPayload:   op.payload,
        serverRecord:   serverRecord,
        localUpdatedAt: op.createdAt,
      );

      if (result.resolution == ConflictResolution.useServer) {
        // Server wins — just delete the local queue item
        await LocalDbService().updateReceivingByServerId(
            op.serverId!, serverRecord);
        await LocalDbService().deleteQueueItem(op.localId!);
        _errors.add('⚠️ Conflict on ${op.table}/${op.serverId}: ${result.message}');
        return;
      }
    }

    // 3. Push local to server
    final putRes = await http.put(
      Uri.parse('$kBaseUrl/${op.table}/${op.serverId}'),
      headers: _headers,
      body: jsonEncode(op.payload),
    ).timeout(const Duration(seconds: 15));

    final body = jsonDecode(putRes.body);
    if (putRes.statusCode == 200 || putRes.statusCode == 201) {
      await LocalDbService().deleteQueueItem(op.localId!);
    } else {
      await LocalDbService().incrementRetry(
        op.localId!, body['message'] ?? 'HTTP ${putRes.statusCode}',
      );
    }
  }

  void _setState(SyncState s) {
    _state = s;
    _stateController.add(s);
  }
}