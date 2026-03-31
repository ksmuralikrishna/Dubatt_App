// lib/services/app_sync_manager.dart
//
// Listens to connectivity changes for the entire app lifetime.
// Call AppSyncManager().init() once from main.dart.
// Call AppSyncManager().dispose() if you ever fully tear down the app.

import 'dart:async';
import 'connectivity_service.dart';
import 'sync_service.dart';

class AppSyncManager {
  AppSyncManager._();
  static final AppSyncManager _instance = AppSyncManager._();
  factory AppSyncManager() => _instance;

  StreamSubscription<bool>? _sub;
  bool _initialized = false;

  void init() {
    if (_initialized) return; // guard against double-init
    _initialized = true;

    _sub = ConnectivityService().onlineStream.listen((online) {
      if (online) {
        SyncService().syncAll();
      }
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }
}