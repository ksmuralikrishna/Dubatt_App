import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../widgets/common/app_shell.dart';
import '../../services/auth_service.dart';
import 'package:dubatt_app/services/connectivity_service.dart';
import 'package:dubatt_app/services/sync_service.dart';
import 'package:dubatt_app/services/local_db_service.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const DashboardScreen({super.key, required this.onLogout});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;

  // Stats
  int _receivingToday = 0;
  int _pendingSync    = 0;
  int _submittedToday = 0;
  int _activeLots     = 0;

  // Recent records
  List<Map<String, dynamic>> _recentRecords = [];

  @override
  void initState() {
    super.initState();
    _loadData();

    // ── Auto-sync when coming back online
    // ConnectivityService().onlineStream.listen((online) {
    //   if (online && mounted) {
    //     SyncService().syncAll().then((_) {
    //       if (mounted) _loadData(); // refresh after sync
    //     });
    //   }
    // });

    // ── Rebuild UI on sync state changes (badge update)
    SyncService().onStateChanged = (state) {
      if (mounted) setState(() {});
    };
  }
  Future<void> _downloadMasterData() async {
    if (!ConnectivityService().isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text('You are offline. Cannot download master data.',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
        ]),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        const SizedBox(width: 10),
        Text('Downloading master data…',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
      ]),
      backgroundColor: AppColors.green,
      duration: const Duration(seconds: 60),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      margin: const EdgeInsets.all(16),
    ));

    try {
      await SyncService().downloadMasterData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text('Master data downloaded successfully.',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
        ]),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('Download failed: $e',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13))),
        ]),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ));
    }
  }
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      if (ConnectivityService().isOnline) {
        // Online — load from API
        await Future.wait([_loadStats(), _loadRecentRecords()]);
      } else {
        // Offline — load from local DB
        await _loadLocalData();
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  // ── Online: load stats from API ────────────────────────────────
  Future<void> _loadStats() async {
    try {
      final res = await http.get(
        Uri.parse('${kBaseUrl}/dashboard/stats'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AuthService().token}',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] ?? {};
        // Merge pending count from local queue on top of server stats
        final localPending = await LocalDbService().getPendingCount();
        setState(() {
          _receivingToday = data['receiving_today'] ?? 0;
          _pendingSync    = localPending;              // ✅ use local queue count
          _submittedToday = data['submitted_today'] ?? 0;
          _activeLots     = data['active_lots']     ?? 0;
        });
      }
    } catch (_) {}
  }

  // ── Online: load recent records from API ───────────────────────
  Future<void> _loadRecentRecords() async {
    try {
      final res = await http.get(
        Uri.parse('${kBaseUrl}/receivings?per_page=5&sort=created_at&order=desc'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AuthService().token}',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = body['data']?['data'] ?? body['data'] ?? [];
        setState(() {
          _recentRecords = List<Map<String, dynamic>>.from(list);
        });
      }
    } catch (_) {}
  }

  // ── Offline: load from local SQLite ───────────────────────────
  Future<void> _loadLocalData() async {
    final localRows = await LocalDbService().getLocalReceivings();
    final pending   = await LocalDbService().getPendingCount();

    setState(() {
      _pendingSync   = pending;
      _activeLots    = localRows.length;
      _receivingToday = localRows
          .where((r) {
        final created = r['created_at'] as String? ?? '';
        return created.startsWith(
          DateTime.now().toIso8601String().substring(0, 10),
        );
      })
          .length;
      _submittedToday = 0; // unknown offline

      // Map local DB rows to the same shape as API records
      _recentRecords = localRows.take(5).map((r) => {
        'lot_no':       r['lot_no'],
        'receipt_date': r['receipt_date'],
        'received_qty': r['received_qty'],
        'unit':         r['unit'],
        'status_label': r['status_label'] ?? 'Pending',
        'sync_status':  r['sync_status'],
        // Flatten nested for display
        'material': {'material_name': r['material_name'] ?? '—'},
        'supplier': {'supplier_name': r['supplier_name'] ?? '—'},
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hPad     = Responsive.hPad(context);
    final isTablet = Responsive.isTablet(context);
    final today    = DateFormat('EEEE, dd MMM yyyy').format(DateTime.now());

    return AppShell(
      currentRoute: '/dashboard',
      onLogout: widget.onLogout,
      child: RefreshIndicator(
        color: AppColors.green,
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Offline banner ─────────────────────────────
                StreamBuilder<bool>(
                  stream: ConnectivityService().onlineStream,
                  initialData: ConnectivityService().isOnline,
                  builder: (_, snap) {
                    final online = snap.data ?? true;
                    if (online) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_off,
                              size: 16, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You are offline. Showing locally saved data. '
                                  'Changes will sync when connection restores.',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: const Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // ── Page header ────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Dashboard', style: AppTextStyles.display()),
                          const SizedBox(height: 4),
                          Text(
                            'Welcome back, ${AuthService().userName}. '
                                "Here's today's overview.",
                            style: AppTextStyles.body(),
                          ),
                        ],
                      ),
                    ),
                    if (isTablet) ...[
                      const SizedBox(width: 12),
                      _SyncStatusBadge(),        // ✅ sync status
                      const SizedBox(width: 8),
                      _DownloadMasterDataBtn(onTap: _downloadMasterData),
                      const SizedBox(width: 12),
                      _DateChip(date: today),
                    ],
                  ],
                ),
                if (!isTablet) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _SyncStatusBadge(),        // ✅ sync status
                      const SizedBox(width: 8),
                      const SizedBox(width: 8),
                      _DownloadMasterDataBtn(onTap: _downloadMasterData),
                      _DateChip(date: today),
                    ],
                  ),
                ],
                const SizedBox(height: 28),

                // ── Stats grid ─────────────────────────────────
                _isLoading
                    ? _StatsGridShimmer(isTablet: isTablet)
                    : _StatsGrid(
                  isTablet: isTablet,
                  receivingToday: _receivingToday,
                  pendingSync: _pendingSync,
                  submittedToday: _submittedToday,
                  activeLots: _activeLots,
                ),
                const SizedBox(height: 24),

                // ── Sync errors (shown only if any) ────────────
                if (SyncService().errors.isNotEmpty)
                  _SyncErrorsBanner(errors: SyncService().errors),

                // ── Quick actions ──────────────────────────────
                _SectionTitle(title: 'Quick Actions'),
                const SizedBox(height: 12),
                _QuickActions(
                  isTablet: isTablet,
                  onCreateReceiving: () =>
                      Navigator.of(context).pushNamed('/receiving/create'),
                  onViewReceiving: () =>
                      Navigator.of(context).pushReplacementNamed('/receiving'),
                ),
                const SizedBox(height: 28),

                // ── Recent records ─────────────────────────────
                MesCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 18, 16, 0),
                        child: Row(
                          children: [
                            const Icon(Icons.history,
                                size: 16, color: AppColors.green),
                            const SizedBox(width: 8),
                            Text('Recent Receiving',
                                style: AppTextStyles.subheading()),
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.of(context)
                                  .pushReplacementNamed('/receiving'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.green,
                                textStyle: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: const Text('View All →'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Divider(height: 1, color: AppColors.borderLight),
                      _isLoading
                          ? _TableShimmer()
                          : _recentRecords.isEmpty
                          ? _EmptyState()
                          : _RecentTable(
                        records: _recentRecords,
                        isTablet: isTablet,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Sync status badge
// ─────────────────────────────────────────────
class _DownloadMasterDataBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _DownloadMasterDataBtn({required this.onTap});

  @override
  State<_DownloadMasterDataBtn> createState() => _DownloadMasterDataBtnState();
}

class _DownloadMasterDataBtnState extends State<_DownloadMasterDataBtn> {
  bool _loading = false;

  Future<void> _handle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await Future.microtask(widget.onTap);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF93C5FD)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _loading
                ? const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Color(0xFF1D4ED8),
              ),
            )
                : const Icon(Icons.download_outlined,
                size: 13, color: Color(0xFF1D4ED8)),
            const SizedBox(width: 5),
            Text(
              _loading ? 'Downloading…' : 'Master Data',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1D4ED8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _SyncStatusBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state   = SyncService().state;
    final pending = SyncService().pendingCount;
    final errors  = SyncService().errors;

    if (state == SyncState.syncing) {
      return _chip(Icons.sync, 'Syncing...', const Color(0xFF0891B2));
    }
    if (errors.isNotEmpty) {
      return _chip(
          Icons.error_outline, '${errors.length} sync error(s)', AppColors.error);
    }
    if (pending > 0) {
      return _chip(
          Icons.pending_outlined, '$pending pending', AppColors.warning);
    }
    return _chip(Icons.check_circle_outline, 'All synced', AppColors.green);
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Sync errors banner
// ─────────────────────────────────────────────
class _SyncErrorsBanner extends StatelessWidget {
  final List<String> errors;
  const _SyncErrorsBanner({required this.errors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.error.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline,
                  size: 16, color: AppColors.error),
              const SizedBox(width: 8),
              Text(
                '${errors.length} record(s) failed to sync',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...errors.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '• $e',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: const Color(0xFF991B1B),
              ),
            ),
          )),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => SyncService().syncAll(),
            child: Text(
              'Tap to retry sync →',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Date chip
// ─────────────────────────────────────────────
class _DateChip extends StatelessWidget {
  final String date;
  const _DateChip({required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.greenLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_outlined,
              size: 12, color: AppColors.green),
          const SizedBox(width: 6),
          Text(
            date,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.green,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Section title
// ─────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: AppTextStyles.subheading());
  }
}

// ─────────────────────────────────────────────
// Stats grid
// ─────────────────────────────────────────────
class _StatsGrid extends StatelessWidget {
  final bool isTablet;
  final int receivingToday, pendingSync, submittedToday, activeLots;

  const _StatsGrid({
    required this.isTablet,
    required this.receivingToday,
    required this.pendingSync,
    required this.submittedToday,
    required this.activeLots,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      _StatData(
        label: 'Receiving Today',
        value: '$receivingToday',
        subLabel: 'lots today',
        icon: Icons.inventory_2_outlined,
        accentColor: AppColors.green,
      ),
      _StatData(
        label: 'Pending Sync',
        value: '$pendingSync',
        subLabel: pendingSync > 0 ? 'awaiting sync' : 'all synced',
        icon: Icons.sync_outlined,
        accentColor: pendingSync > 0 ? AppColors.warning : AppColors.green,
      ),
      _StatData(
        label: 'Submitted Today',
        value: '$submittedToday',
        subLabel: 'submitted',
        icon: Icons.check_circle_outline,
        accentColor: const Color(0xFF0891b2),
      ),
      _StatData(
        label: 'Active Lots',
        value: '$activeLots',
        subLabel: 'total active',
        icon: Icons.layers_outlined,
        accentColor: const Color(0xFF7c3aed),
      ),
    ];

    if (isTablet) {
      return Row(
        children: stats
            .map((s) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: s == stats.last ? 0 : 16),
            child: _StatCard(data: s),
          ),
        ))
            .toList(),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 1.5,
      children: stats.map((s) => _StatCard(data: s)).toList(),
    );
  }
}

class _StatData {
  final String label, value, subLabel;
  final IconData icon;
  final Color accentColor;
  const _StatData({
    required this.label,
    required this.value,
    required this.subLabel,
    required this.icon,
    required this.accentColor,
  });
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  const _StatCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        // borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: data.accentColor, width: 3),
          top: const BorderSide(color: AppColors.borderLight),
          right: const BorderSide(color: AppColors.borderLight),
          bottom: const BorderSide(color: AppColors.borderLight),
        ),
        boxShadow: [
          BoxShadow(
            color: data.accentColor.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  data.label.toUpperCase(),
                  style: AppTextStyles.label(),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: data.accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(data.icon, size: 16, color: data.accentColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            data.value,
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(data.subLabel, style: AppTextStyles.caption()),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Stats shimmer
// ─────────────────────────────────────────────
class _StatsGridShimmer extends StatefulWidget {
  final bool isTablet;
  const _StatsGridShimmer({required this.isTablet});

  @override
  State<_StatsGridShimmer> createState() => _StatsGridShimmerState();
}

class _StatsGridShimmerState extends State<_StatsGridShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.9).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final shimmer = Container(
          height: 110,
          decoration: BoxDecoration(
            color: AppColors.borderLight.withOpacity(_anim.value),
            borderRadius: BorderRadius.circular(14),
          ),
        );
        if (widget.isTablet) {
          return Row(
            children: List.generate(
              4,
                  (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? 16 : 0),
                  child: shimmer,
                ),
              ),
            ),
          );
        }
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.5,
          children: List.generate(4, (_) => shimmer),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Quick actions
// ─────────────────────────────────────────────
class _QuickActions extends StatelessWidget {
  final bool isTablet;
  final VoidCallback onCreateReceiving;
  final VoidCallback onViewReceiving;

  const _QuickActions({
    required this.isTablet,
    required this.onCreateReceiving,
    required this.onViewReceiving,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionData(
        icon: Icons.add_box_outlined,
        label: 'New Receiving',
        subLabel: 'Create a new lot',
        onTap: onCreateReceiving,
      ),
      _ActionData(
        icon: Icons.list_alt_outlined,
        label: 'Receiving List',
        subLabel: 'View all records',
        onTap: onViewReceiving,
      ),
    ];

    if (isTablet) {
      return Row(
        children: actions
            .map((a) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: a == actions.last ? 0 : 16),
            child: _QuickActionCard(data: a),
          ),
        ))
            .toList(),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 1.4,
      children: actions.map((a) => _QuickActionCard(data: a)).toList(),
    );
  }
}

class _ActionData {
  final IconData icon;
  final String label, subLabel;
  final VoidCallback onTap;
  const _ActionData({
    required this.icon,
    required this.label,
    required this.subLabel,
    required this.onTap,
  });
}

class _QuickActionCard extends StatefulWidget {
  final _ActionData data;
  const _QuickActionCard({super.key, required this.data});

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.data.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.greenLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.data.icon,
                    size: 22, color: AppColors.green),
              ),
              const SizedBox(height: 12),
              Text(
                widget.data.label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 3),
              Text(
                widget.data.subLabel,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Recent records table
// ─────────────────────────────────────────────
class _RecentTable extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final bool isTablet;

  const _RecentTable({required this.records, required this.isTablet});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 48,
        ),
        child: Table(
          columnWidths: isTablet
              ? const {
            0: FlexColumnWidth(1.4),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1.4),
            3: FlexColumnWidth(0.8),
            4: FlexColumnWidth(1.2),
            5: FlexColumnWidth(0.8),
            6: FlexColumnWidth(0.6), // ✅ sync status column
          }
              : const {
            0: FlexColumnWidth(1.4),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(0.8),
          },
          children: [
            // Header
            TableRow(
              decoration: const BoxDecoration(color: AppColors.greenLight),
              children: (isTablet
                  ? ['Lot No', 'Date', 'Material', 'Qty', 'Supplier', 'Status', '']
                  : ['Lot No', 'Date', 'Status'])
                  .map((h) => _HeaderCell(text: h))
                  .toList(),
            ),
            // Rows
            ...records.asMap().entries.map((e) {
              final r      = e.value;
              final isLast = e.key == records.length - 1;

              final lotNo      = r['lot_no']?.toString() ?? '—';
              final date       = r['receipt_date']?.toString() ?? '—';
              final material   = (r['material'] as Map?)?['material_name']
                  ?.toString() ?? '—';
              final qty        = r['received_qty']?.toString() ?? '—';
              final unit       = r['unit']?.toString() ?? '';
              final supplier   = (r['supplier'] as Map?)?['supplier_name']
                  ?.toString() ?? '—';
              final status     = r['status_label']?.toString() ?? 'Pending';
              final syncStatus = r['sync_status']?.toString() ?? 'synced';

              final cells = isTablet
                  ? [
                _DataCell(text: lotNo, bold: true),
                _DataCell(text: _fmtDate(date)),
                _DataCell(text: material),
                _DataCell(text: '$qty $unit', align: TextAlign.right),
                _DataCell(text: supplier),
                _BadgeCell(status: status),
                _SyncDotCell(syncStatus: syncStatus), // ✅ shows pending dot
              ]
                  : [
                _DataCell(text: lotNo, bold: true),
                _DataCell(text: _fmtDate(date)),
                _BadgeCell(status: status),
              ];

              return TableRow(
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : const Border(
                    bottom: BorderSide(color: AppColors.borderLight),
                  ),
                ),
                children: cells,
              );
            }),
          ],
        ),
      ),
    );
  }

  String _fmtDate(String raw) {
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(raw));
    } catch (_) {
      return raw.length >= 10 ? raw.substring(0, 10) : raw;
    }
  }
}

// ─────────────────────────────────────────────
// Sync dot cell — shows orange dot if pending
// ─────────────────────────────────────────────
class _SyncDotCell extends StatelessWidget {
  final String syncStatus;
  const _SyncDotCell({required this.syncStatus});

  @override
  Widget build(BuildContext context) {
    final isPending = syncStatus == 'pending';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Tooltip(
        message: isPending ? 'Pending sync' : 'Synced',
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPending ? AppColors.warning : AppColors.green,
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.outfit(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: AppColors.green,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final bool bold;
  final TextAlign align;
  const _DataCell({
    required this.text,
    this.bold = false,
    this.align = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        text,
        textAlign: align,
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: bold ? AppColors.textDark : AppColors.textMid,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _BadgeCell extends StatelessWidget {
  final String status;
  const _BadgeCell({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (status.toLowerCase()) {
      case 'approved':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        break;
      case 'in progress':
        bg = const Color(0xFFFEF9C3);
        fg = const Color(0xFFCA8A04);
        break;
      case 'pending':
      default:
        bg = const Color(0xFFF1F5F9);
        fg = AppColors.textMuted;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          status,
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Table shimmer
// ─────────────────────────────────────────────
class _TableShimmer extends StatefulWidget {
  @override
  State<_TableShimmer> createState() => _TableShimmerState();
}

class _TableShimmerState extends State<_TableShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.85).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Column(
        children: List.generate(
          5,
              (i) => Container(
            height: 46,
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.borderLight.withOpacity(_anim.value),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.greenLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.inventory_2_outlined,
                  size: 32, color: AppColors.green),
            ),
            const SizedBox(height: 14),
            Text(
              'No receiving records yet',
              style: AppTextStyles.subheading(color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              'Create your first record to get started',
              style: AppTextStyles.caption(),
            ),
          ],
        ),
      ),
    );
  }
}