import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/widgets.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  final String currentRoute;
  final VoidCallback onLogout;

  const AppShell({
    super.key,
    required this.child,
    required this.currentRoute,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Responsive.isTablet(context)
        ? _TabletShell(
            currentRoute: currentRoute,
            onLogout: onLogout,
            child: child,
          )
        : _MobileShell(
            currentRoute: currentRoute,
            onLogout: onLogout,
            child: child,
          );
  }
}

// ────────────────────────────────────────────────────────────────
// TABLET SHELL — sidebar layout
// ────────────────────────────────────────────────────────────────
class _TabletShell extends StatelessWidget {
  final Widget child;
  final String currentRoute;
  final VoidCallback onLogout;

  const _TabletShell({
    required this.child,
    required this.currentRoute,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(currentRoute: currentRoute, onLogout: onLogout),
          Expanded(
            child: Container(
              color: AppColors.bg,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// SIDEBAR
// ────────────────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  final String currentRoute;
  final VoidCallback onLogout;

  const _Sidebar({required this.currentRoute, required this.onLogout});

  static const _navItems = [
    _NavItemData(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard,
        label: 'Dashboard', route: '/dashboard'),
    _NavItemData(icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2,
        label: 'Receiving', route: '/receiving'),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();

    return Container(
      width: 220,
      color: AppColors.greenDark,
      child: Column(
        children: [
          // ── Top: Logo + app name
          Container(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.factory_outlined,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MES Portal',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 14, fontWeight: FontWeight.w700,
                          )),
                      Text('Manufacturing',
                          style: GoogleFonts.outfit(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 11, fontWeight: FontWeight.w400,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Divider(color: Colors.white.withOpacity(0.1), height: 1),
          const SizedBox(height: 10),

          // ── Nav items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: _navItems.map((item) => _NavItem(
                data: item,
                isActive: currentRoute.startsWith(item.route),
                onTap: () {
                  if (!currentRoute.startsWith(item.route)) {
                    Navigator.of(context).pushReplacementNamed(item.route);
                  }
                },
              )).toList(),
            ),
          ),

          const Spacer(),

          // ── Sync indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 7, height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4ade80),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text('Connected',
                    style: GoogleFonts.outfit(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 11,
                    )),
              ],
            ),
          ),

          // Divider
          Divider(color: Colors.white.withOpacity(0.1), height: 1),

          // ── User row + logout
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: Text(
                      auth.userInitials,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.userName,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 12, fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        auth.userRole,
                        style: GoogleFonts.outfit(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Logout
                GestureDetector(
                  onTap: onLogout,
                  child: Icon(
                    Icons.logout,
                    size: 17,
                    color: Colors.white.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
  const _NavItemData({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });
}

class _NavItem extends StatelessWidget {
  final _NavItemData data;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.data,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              isActive ? data.activeIcon : data.icon,
              size: 17,
              color: isActive
                  ? AppColors.greenDark
                  : Colors.white.withOpacity(0.7),
            ),
            const SizedBox(width: 10),
            Text(
              data.label,
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? AppColors.greenDark
                    : Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// MOBILE SHELL — bottom nav bar
// ────────────────────────────────────────────────────────────────
class _MobileShell extends StatelessWidget {
  final Widget child;
  final String currentRoute;
  final VoidCallback onLogout;

  const _MobileShell({
    required this.child,
    required this.currentRoute,
    required this.onLogout,
  });

  int get _currentIndex {
    if (currentRoute.startsWith('/receiving')) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.greenDark,
        elevation: 0,
        leading: Container(
          padding: const EdgeInsets.all(10),
          child: const Icon(Icons.factory_outlined,
              color: Colors.white, size: 22),
        ),
        title: Text('MES Portal',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 16, fontWeight: FontWeight.w700,
            )),
        actions: [
          // Avatar + logout
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: onLogout,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppColors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(auth.userInitials,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12, fontWeight: FontWeight.w700,
                      )),
                ),
              ),
            ),
          ),
        ],
      ),
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12, offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: AppColors.white,
          selectedItemColor: AppColors.green,
          unselectedItemColor: AppColors.textMuted,
          selectedLabelStyle: GoogleFonts.outfit(
            fontSize: 11, fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.outfit(
            fontSize: 11, fontWeight: FontWeight.w400,
          ),
          elevation: 0,
          onTap: (i) {
            final routes = ['/dashboard', '/receiving'];
            Navigator.of(context).pushReplacementNamed(routes[i]);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              activeIcon: Icon(Icons.inventory_2),
              label: 'Receiving',
            ),
          ],
        ),
      ),
    );
  }
}
