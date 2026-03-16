import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const String kBaseUrl = 'http://192.168.2.227:8000/api/auth';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _storage = const FlutterSecureStorage();
  String? _token;
  Map<String, dynamic>? _user;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  Future<void> init() async {
    _token = await _storage.read(key: 'auth_token');
    final userJson = await _storage.read(key: 'auth_user');
    if (userJson != null) {
      _user = jsonDecode(userJson);
    }
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<LoginResult> login(String email, String password) async {
    print('Trying to login...');
    print('POST $kBaseUrl/login with $email / $password');
    try {
      final res = await http.post(
        Uri.parse('$kBaseUrl/login'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'login': email, 'password': password}),
      ).timeout(const Duration(seconds: 15));
      print('Response: ${res.statusCode} - ${res.body}');
      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['status'] == 'ok') {
        _token = data['data']['token'];
        _user  = data['data']['user'];
        await _storage.write(key: 'auth_token', value: _token);
        await _storage.write(key: 'auth_user', value: jsonEncode(_user));
        return LoginResult.success();
      } else if (res.statusCode == 422) {
        final errors = data['errors'] as Map<String, dynamic>?;
        final msg = errors?.values.first?[0] ?? data['message'] ?? 'Validation failed.';
        return LoginResult.failure(msg);
      } else if (res.statusCode == 401) {
        return LoginResult.failure('Invalid email or password.');
      } else {
        return LoginResult.failure(data['message'] ?? 'Login failed. Please try again.');
      }
    } on Exception catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('TimeoutException')) {
        return LoginResult.failure('No internet connection. Check your network and try again.');
      }
      return LoginResult.failure('Something went wrong. Please try again.');
    }
  }

  Future<void> logout() async {
    _token = null;
    _user  = null;
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'auth_user');
  }

  String get userName => _user?['name'] ?? 'User';
  String get userEmail => _user?['email'] ?? '';
  String get userRole => _user?['role'] ?? 'Operator';
  String get userInitials {
    final parts = userName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return userName.isNotEmpty ? userName[0].toUpperCase() : 'U';
  }
}

class LoginResult {
  final bool success;
  final String? error;
  LoginResult.success() : success = true, error = null;
  LoginResult.failure(this.error) : success = false;
}
