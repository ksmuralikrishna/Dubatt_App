import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/widgets.dart';

// ────────────────────────────────────────────────────────────────
// NAV DATA MODEL
// ────────────────────────────────────────────────────────────────

class _NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;

  /// Matches the API "module" field from /auth/me permissions.
  /// Use 'dashboard' for the always-visible root item.
  /// Use null for items that have no API key yet (treated as full_access only).
  final String? permissionKey;

  const _NavItemData({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
    required this.permissionKey,
  });
}

class _NavSection {
  final String? title; // null = no section header (e.g. Dashboard)
  final List<_NavItemData> items;

  const _NavSection({this.title, required this.items});
}

// ── Nav tree ────────────────────────────────────────────────────
const _navSections = [
  _NavSection(
    items: [
      _NavItemData(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard,
        label: 'Dashboard',
        route: '/dashboard',
        permissionKey: 'dashboard', // always visible
      ),
    ],
  ),
  _NavSection(
    title: 'Modules',
    items: [
      _NavItemData(
        icon: Icons.inventory_2_outlined,
        activeIcon: Icons.inventory_2,
        label: 'Receiving',
        route: '/receiving',
        permissionKey: 'receiving',
      ),
      _NavItemData(
        icon: Icons.science_outlined,
        activeIcon: Icons.science,
        label: 'Acid Testing',
        route: '/acid-testing',
        permissionKey: 'acid_testing',
      ),
      _NavItemData(
        icon: Icons.battery_charging_full_outlined,
        activeIcon: Icons.battery_charging_full,
        label: 'BBSU',
        route: '/bbsu',
        permissionKey: 'bbsu', // no API key yet → full_access only
      ),
      _NavItemData(
        icon: Icons.local_fire_department_outlined,
        activeIcon: Icons.local_fire_department,
        label: 'Smelting',
        route: '/smelting',
        permissionKey: 'smelting',
      ),
      _NavItemData(
        icon: Icons.filter_alt_outlined,
        activeIcon: Icons.filter_alt,
        label: 'Refining',
        route: '/refining',
        permissionKey: 'refining',
      ),
    ],
  ),
];

// ── Visible items filtered by the current user's permissions ────
List<_NavItemData> _visibleItems(AuthService auth) {
  return _navSections
      .expand((s) => s.items)
      .where((item) => auth.canViewModule(item.permissionKey ?? ''))
      .toList();
}

// ── Visible sections (drops sections whose items are all hidden) ─
List<_NavSection> _visibleSections(AuthService auth) {
  return _navSections
      .map((section) {
    final visible = section.items
        .where((item) => auth.canViewModule(item.permissionKey ?? ''))
        .toList();
    if (visible.isEmpty) return null;
    return _NavSection(title: section.title, items: visible);
  })
      .whereType<_NavSection>()
      .toList();
}

// ────────────────────────────────────────────────────────────────
// APP SHELL — entry point, picks tablet or mobile layout
// ────────────────────────────────────────────────────────────────

class AppShell extends StatelessWidget {
  final Widget child;
  final String currentRoute;
  final VoidCallback onLogout;
  final ValueChanged<String>? onNavigate;

  const AppShell({
    super.key,
    required this.child,
    required this.currentRoute,
    required this.onLogout,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Responsive.isTablet(context)
        ? _TabletShell(
      currentRoute: currentRoute,
      onLogout: onLogout,
      onNavigate: onNavigate,
      child: child,
    )
        : _MobileShell(
      currentRoute: currentRoute,
      onLogout: onLogout,
      onNavigate: onNavigate,
      child: child,
    );
  }
}

// ────────────────────────────────────────────────────────────────
// LOGOUT CONFIRMATION — shared by both shells
// ────────────────────────────────────────────────────────────────

Future<void> _confirmLogout(
    BuildContext context, VoidCallback onLogout) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        'Log out?',
        style: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
      ),
      content: Text(
        'Are you sure you want to log out?',
        style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMid),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Cancel',
              style: GoogleFonts.outfit(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(
            'Log out',
            style: GoogleFonts.outfit(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  if (confirmed == true) onLogout();
}

// ────────────────────────────────────────────────────────────────
// TABLET SHELL — collapsible sidebar
// ────────────────────────────────────────────────────────────────

class _TabletShell extends StatefulWidget {
  final Widget child;
  final String currentRoute;
  final VoidCallback onLogout;
  final ValueChanged<String>? onNavigate;

  const _TabletShell({
    required this.child,
    required this.currentRoute,
    required this.onLogout,
    this.onNavigate,
  });

  @override
  State<_TabletShell> createState() => _TabletShellState();
}

class _TabletShellState extends State<_TabletShell> {
  bool _collapsed = false;

  static const double _expandedWidth = 220.0;
  static const double _collapsedWidth = 60.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            width: _collapsed ? _collapsedWidth : _expandedWidth,
            child: _Sidebar(
              currentRoute: widget.currentRoute,
              collapsed: _collapsed,
              onNavigate: widget.onNavigate,
              onToggle: () => setState(() => _collapsed = !_collapsed),
              onLogout: () => _confirmLogout(context, widget.onLogout),
            ),
          ),
          Expanded(
            child: Container(
              color: AppColors.bg,
              child: widget.child,
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
  final bool collapsed;
  final ValueChanged<String>? onNavigate;
  final VoidCallback onToggle;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.currentRoute,
    required this.collapsed,
    this.onNavigate,
    required this.onToggle,
    required this.onLogout,
  });

  bool _isActive(_NavItemData item) => currentRoute.startsWith(item.route);

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final sections = _visibleSections(auth); // ← permission-filtered

    return Container(
      color: AppColors.greenDark,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: hamburger + logo ─────────────────────────
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onToggle,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.menu,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(Icons.factory_outlined,
                          color: Colors.white, size: 15),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Dubatt Nexus',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              )),
                          Text('Manufacturing',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 10,
                              )),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Divider(color: Colors.white.withOpacity(0.1), height: 1),

            // ── Nav sections (permission-filtered) ───────────────
            Expanded(
              child: SingleChildScrollView(
                padding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: sections.map((section) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (section.title != null && !collapsed)
                          Padding(
                            padding:
                            const EdgeInsets.fromLTRB(10, 14, 10, 6),
                            child: Text(
                              section.title!.toUpperCase(),
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                          )
                        else if (section.title != null && collapsed)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 10),
                            child: Divider(
                              color: Colors.white.withOpacity(0.15),
                              height: 1,
                            ),
                          ),
                        ...section.items.map((item) => _NavItem(
                          data: item,
                          isActive: _isActive(item),
                          collapsed: collapsed,
                          onTap: () {
                            if (!currentRoute.startsWith(item.route)) {
                              if (onNavigate != null) {
                                onNavigate!(item.route);
                              } else {
                                Navigator.of(context)
                                    .pushReplacementNamed(item.route);
                              }
                            }
                          },
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),

            // ── Connection status ────────────────────────────────
            if (!collapsed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
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

            Divider(color: Colors.white.withOpacity(0.1), height: 1),

            // ── User row + logout ────────────────────────────────
            Padding(
              padding: EdgeInsets.all(collapsed ? 10 : 14),
              child: collapsed
                  ? Tooltip(
                message: 'Log out',
                child: GestureDetector(
                  onTap: onLogout,
                  child: _avatar(auth, size: 36),
                ),
              )
                  : Row(
                children: [
                  _avatar(auth, size: 32),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.userName,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
                  GestureDetector(
                    onTap: onLogout,
                    child: Tooltip(
                      message: 'Log out',
                      child: Icon(
                        Icons.logout,
                        size: 17,
                        color: Colors.white.withOpacity(0.65),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(AuthService auth, {required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Center(
        child: Text(
          auth.userInitials,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: size * 0.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// NAV ITEM — flat, no children
// ────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final _NavItemData data;
  final bool isActive;
  final bool collapsed;
  final VoidCallback onTap;

  const _NavItem({
    required this.data,
    required this.isActive,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? data.label : '',
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : 12,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: collapsed
              ? Center(
            child: Icon(
              isActive ? data.activeIcon : data.icon,
              size: 18,
              color: isActive
                  ? AppColors.greenDark
                  : Colors.white.withOpacity(0.7),
            ),
          )
              : Row(
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
                  fontWeight: isActive
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: isActive
                      ? AppColors.greenDark
                      : Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// MOBILE SHELL — AppBar + bottom nav + drawer for all modules
// ────────────────────────────────────────────────────────────────

class _MobileShell extends StatelessWidget {
  final Widget child;
  final String currentRoute;
  final VoidCallback onLogout;
  final ValueChanged<String>? onNavigate;

  const _MobileShell({
    required this.child,
    required this.currentRoute,
    required this.onLogout,
    this.onNavigate,
  });

  int _bottomIndex(List<_NavItemData> items) {
    if (currentRoute == '/dashboard') return 0;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final sections = _visibleSections(auth); // ← permission-filtered
    final allVisible = _visibleItems(auth);

    // Find active module for bottom nav label
    final activeModule = allVisible.firstWhere(
          (item) =>
      item.route != '/dashboard' && currentRoute.startsWith(item.route),
      orElse: () => allVisible.firstWhere(
            (item) => item.route != '/dashboard',
        orElse: () => allVisible.first,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.greenDark,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => GestureDetector(
            onTap: () => Scaffold.of(ctx).openDrawer(),
            child: const Icon(Icons.menu, color: Colors.white, size: 22),
          ),
        ),
        title: Text(
          'MES Portal',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => _confirmLogout(context, onLogout),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    auth.userInitials,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      // ── Drawer — permission-filtered sections ──────────────────
      drawer: Drawer(
        backgroundColor: AppColors.greenDark,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(Icons.factory_outlined,
                          color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Text('MES Portal',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        )),
                  ],
                ),
              ),
              Divider(color: Colors.white.withOpacity(0.1), height: 1),
              const SizedBox(height: 8),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: sections.map((section) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (section.title != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  8, 14, 8, 6),
                              child: Text(
                                section.title!.toUpperCase(),
                                style: GoogleFonts.outfit(
                                  color: Colors.white.withOpacity(0.35),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                          ...section.items.map((item) {
                            final isActive =
                            currentRoute.startsWith(item.route);
                            return GestureDetector(
                              onTap: () {
                                Navigator.of(context).pop();
                                if (!currentRoute
                                    .startsWith(item.route)) {
                                  if (onNavigate != null) {
                                    onNavigate!(item.route);
                                  } else {
                                    Navigator.of(context)
                                        .pushReplacementNamed(item.route);
                                  }
                                }
                              },
                              child: AnimatedContainer(
                                duration:
                                const Duration(milliseconds: 140),
                                margin: const EdgeInsets.only(bottom: 2),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 11),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isActive
                                          ? item.activeIcon
                                          : item.icon,
                                      size: 17,
                                      color: isActive
                                          ? AppColors.greenDark
                                          : Colors.white.withOpacity(0.7),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      item.label,
                                      style: GoogleFonts.outfit(
                                        fontSize: 13.5,
                                        fontWeight: isActive
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: isActive
                                            ? AppColors.greenDark
                                            : Colors.white
                                            .withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),

              Divider(color: Colors.white.withOpacity(0.1), height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          auth.userInitials,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
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
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
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
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        _confirmLogout(context, onLogout);
                      },
                      child: Tooltip(
                        message: 'Log out',
                        child: Icon(Icons.logout,
                            size: 17,
                            color: Colors.white.withOpacity(0.65)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      body: child,

      // ── Bottom nav: Dashboard + active visible module ──────────
      bottomNavigationBar: allVisible.length <= 1
          ? null // only Dashboard visible — no point showing bottom nav
          : Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _bottomIndex(allVisible),
          backgroundColor: AppColors.white,
          selectedItemColor: AppColors.green,
          unselectedItemColor: AppColors.textMuted,
          selectedLabelStyle: GoogleFonts.outfit(
              fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.outfit(
              fontSize: 11, fontWeight: FontWeight.w400),
          elevation: 0,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(activeModule.icon),
              activeIcon: Icon(activeModule.activeIcon),
              label: activeModule.label,
            ),
          ],
          onTap: (i) {
            if (i == 0) {
              if (onNavigate != null) {
                onNavigate!('/dashboard');
              } else {
                Navigator.of(context)
                    .pushReplacementNamed('/dashboard');
              }
            }
          },
        ),
      ),
    );
  }
}