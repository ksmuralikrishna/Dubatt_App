import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final ConnectivityService _i = ConnectivityService._();
  factory ConnectivityService() => _i;
  ConnectivityService._();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onlineStream => _controller.stream;

  StreamSubscription? _sub;

  Future<void> init() async {
    // ✅ checkConnectivity() also returns List in v5+
    final results = await Connectivity().checkConnectivity();
    _isOnline = _mapResults(results);

    // ✅ onConnectivityChanged emits List<ConnectivityResult> in v5+
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final online = _mapResults(results);
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(_isOnline);
      }
    });
  }

  // ✅ Check if ANY result in the list is not 'none'
  bool _mapResults(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}