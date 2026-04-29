import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const String kBaseUrl = 'http://192.168.2.227:8000/api';
// const String kBaseUrl = 'http://192.168.151.7:8000/api'; // Dubatt IP

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _storage = const FlutterSecureStorage();
  String? _token;
  Map<String, dynamic>? _user;

  // Stores { "receiving": true, "acid_testing": false, ... }
  // Null means permissions have not been loaded yet (or user has full_access)
  Map<String, bool>? _permissions;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  /// True for admin / management users who can see everything.
  bool get fullAccess => _user?['full_access'] == true;

  /// Returns true if the current user may view the given module.
  ///
  /// [moduleKey] must match the API "module" field exactly, e.g.
  ///   'receiving', 'acid_testing', 'smelting', 'refining'
  ///
  /// Special values:
  ///   'dashboard' — always visible to everyone.
  ///   'bbsu'      — no API key yet; shown only to full_access users.
  bool canViewModule(String moduleKey) {
    if (moduleKey == 'dashboard') return true;
    if (fullAccess) return true;
    // if (moduleKey == 'bbsu') return false; // no API permission key yet
    return _permissions?[moduleKey] ?? false;
  }

  Future<void> init() async {
    _token = await _storage.read(key: 'auth_token');
    final userJson = await _storage.read(key: 'auth_user');
    if (userJson != null) {
      _user = jsonDecode(userJson);
    }
    final permJson = await _storage.read(key: 'auth_permissions');
    if (permJson != null) {
      _permissions = Map<String, bool>.from(jsonDecode(permJson));
    }
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<LoginResult> login(String loginIdentifier, String password) async {
    try {
      final res = await http
          .post(
        Uri.parse('$kBaseUrl/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: jsonEncode(
            {'login': loginIdentifier, 'password': password}),
      )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['status'] == 'ok') {
        _token = data['data']['token'];
        _user = data['data']['user'];
        await _storage.write(key: 'auth_token', value: _token);
        await _storage.write(key: 'auth_user', value: jsonEncode(_user));

        // Fetch granular permissions for non-full-access users.
        // full_access users skip this call entirely.
        if (!fullAccess) {
          await _fetchAndStorePermissions();
        }

        return LoginResult.success();
      } else if (res.statusCode == 422) {
        final errors = data['errors'] as Map<String, dynamic>?;
        final msg = errors?.values.first?[0] ??
            data['message'] ??
            'Validation failed.';
        return LoginResult.failure(msg);
      } else if (res.statusCode == 401) {
        return LoginResult.failure(
            'Invalid email, username, or password.');
      } else {
        return LoginResult.failure(
            data['message'] ?? 'Login failed. Please try again.');
      }
    } on Exception catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('TimeoutException')) {
        return LoginResult.failure(
            'No internet connection. Check your network and try again.');
      }
      return LoginResult.failure(
          'Something went wrong. Please try again.');
    }
  }

  /// Calls GET /auth/me and stores the permissions map.
  /// Safe to call at any time (e.g. on app resume).
  Future<void> _fetchAndStorePermissions() async {
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/auth/me'), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final me = data['data'] as Map<String, dynamic>;

        // Update stored user (e.g. last_login_at may have changed)
        _user = me;
        await _storage.write(key: 'auth_user', value: jsonEncode(_user));

        final raw = me['permissions'] as List<dynamic>?;
        if (raw != null) {
          _permissions = {
            for (final p in raw)
              (p['module'] as String): p['can_view'] == true,
          };
          await _storage.write(
              key: 'auth_permissions',
              value: jsonEncode(_permissions));
        }
      }
    } catch (_) {
      // Non-fatal — fall back to whatever was cached on disk.
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _permissions = null;
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'auth_user');
    await _storage.delete(key: 'auth_permissions');
  }

  String get userName => _user?['name'] ?? 'User';
  String get userEmail => _user?['email'] ?? '';
  String get userRole => _user?['role'] ?? 'Operator';
  String get userInitials {
    final parts = userName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return userName.isNotEmpty ? userName[0].toUpperCase() : 'U';
  }
}

class LoginResult {
  final bool success;
  final String? error;
  LoginResult.success()
      : success = true,
        error = null;
  LoginResult.failure(this.error) : success = false;
}