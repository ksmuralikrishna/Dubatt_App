import 'dart:io';                                          // ✅ add
import 'package:sqflite_common_ffi/sqflite_ffi.dart';     // ✅ add

import 'package:dubatt_app/services/connectivity_service.dart';
import 'package:dubatt_app/services/local_db_service.dart';
import 'services/app_sync_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/receiving/receiving_list_screen.dart';
import 'screens/receiving/receiving_form_screen.dart';


// ── Uncomment each import as you create the screen files
import 'screens/acid_testing/acid_testing_list_screen.dart';
import 'screens/acid_testing/acid_testing_form_screen.dart';
import 'screens/bbsu/bbsu_list_screen.dart';
import 'screens/bbsu/bbsu_form_screen.dart';
import 'screens/smelting/smelting_list_screen.dart';
import 'screens/smelting/smelting_form_screen.dart';
import 'screens/refining/refining_list_screen.dart';
import 'screens/refining/refining_form_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initialize sqflite for desktop/web platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);

  await AuthService().init();
  await LocalDbService().init();
  await ConnectivityService().init();

  AppSyncManager().init();

  runApp(const MesApp());
}

class MesApp extends StatelessWidget {
  const MesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dubatt Nexus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _AppRoot(),
      onGenerateRoute: _generateRoute,
    );
  }

  static Route<dynamic>? _generateRoute(RouteSettings settings) {
    final root = _AppRoot.instance;
    final name = settings.name ?? '';

    // ── Dashboard ──────────────────────────────────────────────
    if (name == '/dashboard') {
      return _slide(DashboardScreen(onLogout: root._onLogout));
    }

    // ── Receiving ──────────────────────────────────────────────
    if (name == '/receiving') {
      return _slide(ReceivingListScreen(onLogout: root._onLogout));
    }
    if (name == '/receiving/create') {
      return _slide(ReceivingFormScreen(onLogout: root._onLogout));
    }
    if (name.startsWith('/receiving/') && name.endsWith('/edit')) {
      final id = name
          .replaceFirst('/receiving/', '')
          .replaceFirst('/edit', '');
      return _slide(ReceivingFormScreen(
          recordId: id, onLogout: root._onLogout));
    }

    // ── Acid Testing ───────────────────────────────────────────
    if (name == '/acid-testing') {
      return _slide(AcidTestingListScreen(onLogout: root._onLogout));
    }
    if (name == '/acid-testing/create') {
      return _slide(AcidTestingFormScreen(onLogout: root._onLogout));
    }
    if (name.startsWith('/acid-testing/') && name.endsWith('/edit')) {
      final id = name
          .replaceFirst('/acid-testing/', '')
          .replaceFirst('/edit', '');
      return _slide(AcidTestingFormScreen(
          recordId: id, onLogout: root._onLogout));
    }

    // ── BBSU ───────────────────────────────────────────────────
    if (name == '/bbsu') {
      return _slide(BbsuListScreen(onLogout: root._onLogout));
    }
    if (name == '/bbsu/create') {
      return _slide(BbsuFormScreen(onLogout: root._onLogout));
    }
    if (name.startsWith('/bbsu/') && name.endsWith('/edit')) {
      final id = name
          .replaceFirst('/bbsu/', '')
          .replaceFirst('/edit', '');
      return _slide(BbsuFormScreen(
          recordId: id, onLogout: root._onLogout));
    }

    // ── Smelting ───────────────────────────────────────────────
    if (name == '/smelting') {
      return _slide(SmeltingListScreen(onLogout: root._onLogout));
    }
    if (name == '/smelting/create') {
      return _slide(SmeltingFormScreen(onLogout: root._onLogout));
    }
    if (name.startsWith('/smelting/') && name.endsWith('/edit')) {
      final id = name
          .replaceFirst('/smelting/', '')
          .replaceFirst('/edit', '');
      return _slide(SmeltingFormScreen(
          recordId: id, onLogout: root._onLogout));
    }

    // ── Refining ───────────────────────────────────────────────
    if (name == '/refining') {
      return _slide(RefiningListScreen(onLogout: root._onLogout));
    }
    if (name == '/refining/create') {
      return _slide(RefiningFormScreen(onLogout: root._onLogout));
    }
    if (name.startsWith('/refining/') && name.endsWith('/edit')) {
      final id = name
          .replaceFirst('/refining/', '')
          .replaceFirst('/edit', '');
      return _slide(RefiningFormScreen(
          recordId: id, onLogout: root._onLogout));
    }

    // ── 404 ─────────────────────────────────────────────────────
    return _slide(const _NotFoundScreen());
  }

  static PageRouteBuilder<dynamic> _slide(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 220),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// App root
// ────────────────────────────────────────────────────────────────
class _AppRoot extends StatefulWidget {
  const _AppRoot();
  static late _AppRootState instance;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool get _isLoggedIn => AuthService().isAuthenticated;

  @override
  void initState() {
    super.initState();
    _AppRoot.instance = this;
  }

  void _onLoginSuccess() => setState(() {});

  Future<void> _onLogout() async {
    await AuthService().logout();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) {
      return LoginScreen(onLoginSuccess: _onLoginSuccess);
    }
    return DashboardScreen(onLogout: _onLogout);
  }
}

// ────────────────────────────────────────────────────────────────
// 404 screen
// ────────────────────────────────────────────────────────────────
class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Page not found',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context)
                  .pushReplacementNamed('/dashboard'),
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}