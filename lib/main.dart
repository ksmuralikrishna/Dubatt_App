import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/receiving/receiving_list_screen.dart';
import 'screens/receiving/receiving_form_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to landscape on tablets, allow both on phones
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);

  // Initialise auth service (load saved token)
  await AuthService().init();

  runApp(const MesApp());
}

class MesApp extends StatelessWidget {
  const MesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MES Portal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _AppRoot(),
      onGenerateRoute: (settings) {
        // All named routes go through here so we can pass onLogout
        final root = _AppRoot.instance;
        switch (settings.name) {
          case '/dashboard':
            return MaterialPageRoute(
              builder: (_) => DashboardScreen(onLogout: root._onLogout),
            );
          case '/receiving':
            return MaterialPageRoute(
              builder: (_) => ReceivingListScreen(onLogout: root._onLogout),
            );
          case '/receiving/create':
            return MaterialPageRoute(
              builder: (_) => ReceivingFormScreen(onLogout: root._onLogout),
            );
          default:
            if (settings.name?.startsWith('/receiving/') == true &&
                settings.name?.endsWith('/edit') == true) {
              final id = settings.name!
                  .replaceFirst('/receiving/', '')
                  .replaceFirst('/edit', '');
              return MaterialPageRoute(
                builder: (_) => ReceivingFormScreen(
                  recordId: id, onLogout: root._onLogout,
                ),
              );
            }
            return null;
        }
      },
    );
  }
}

/// Root widget that decides: show Login or Dashboard
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
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) {
      return LoginScreen(onLoginSuccess: _onLoginSuccess);
    }
    return DashboardScreen(onLogout: _onLogout);
  }
}
