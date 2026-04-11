import 'package:flutter/material.dart';
import '../../widgets/common/app_shell.dart';
import '../dashboard/dashboard_screen.dart';
import '../receiving/receiving_list_screen.dart';
import '../acid_testing/acid_testing_list_screen.dart';
import '../bbsu/bbsu_list_screen.dart';
import '../smelting/smelting_list_screen.dart';
import '../refining/refining_list_screen.dart';

class HomeShellScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final String initialRoute;

  const HomeShellScreen({
    super.key,
    required this.onLogout,
    this.initialRoute = '/dashboard',
  });

  @override
  State<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends State<HomeShellScreen> {
  late String _currentRoute;

  static const _routes = <String>[
    '/dashboard',
    '/receiving',
    '/acid-testing',
    '/bbsu',
    '/smelting',
    '/refining',
  ];

  @override
  void initState() {
    super.initState();
    _currentRoute = _routes.contains(widget.initialRoute)
        ? widget.initialRoute
        : '/dashboard';
  }

  int get _index => _routes.indexOf(_currentRoute).clamp(0, _routes.length - 1);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      currentRoute: _currentRoute,
      onLogout: widget.onLogout,
      onNavigate: (route) {
        if (_routes.contains(route)) {
          setState(() => _currentRoute = route);
        }
      },
      child: IndexedStack(
        index: _index,
        children: [
          DashboardScreen(onLogout: widget.onLogout, embedInShell: false),
          ReceivingListScreen(onLogout: widget.onLogout, embedInShell: false),
          AcidTestingListScreen(onLogout: widget.onLogout, embedInShell: false),
          BbsuListScreen(onLogout: widget.onLogout, embedInShell: false),
          SmeltingListScreen(onLogout: widget.onLogout, embedInShell: false),
          RefiningListScreen(onLogout: widget.onLogout, embedInShell: false),
        ],
      ),
    );
  }
}
