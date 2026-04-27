// ─────────────────────────────────────────────────────────────────────────────
// bbsu_list_screen.dart
// List screen for the BBSU module.
//
// Columns (from Laravel Blade list):
//   Date | Doc No | Start Time | End Time | Category | Status | Actions
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../widgets/common/app_shell.dart';
import '../../models/bbsu_model.dart';
import '../../services/bbsu_service.dart';
import '../../services/connectivity_service.dart';
import 'bbsu_form_screen.dart';
import 'package:dubatt_app/services/sync_service.dart';

class BbsuListScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final bool embedInShell;
  const BbsuListScreen({
    super.key,
    required this.onLogout,
    this.embedInShell = true,
  });

  @override
  State<BbsuListScreen> createState() => _BbsuListScreenState();
}

class _BbsuListScreenState extends State<BbsuListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<SyncState>? _syncSub;

  List<BbsuSummary> _records = [];
  bool _isLoading = true;
  String? _errorMsg;
  int _total = 0;
  int _currentPage = 1;
  static const _perPage = 20;

  String _statusFilter = 'all';

  final _statusOptions = const [
    {'value': 'all',       'label': 'All Status'},
    {'value': '0',         'label': 'Draft'},
    {'value': '1',         'label': 'Submitted'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
    // _connectivitySub =
    //     ConnectivityService().onlineStream.listen((online) {
    //       if (online && mounted) _load(reset: true);
    //     });
    // ✅ Reload after AppSyncManager finishes syncing offline records
    _syncSub = SyncService().stateStream.listen((state) {
      if ((state == SyncState.done || state == SyncState.idle) && mounted) {
        _load(reset: true);
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _debounce?.cancel();
    _connectivitySub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _currentPage = 1;
    setState(() {
      _isLoading = true;
      _errorMsg  = null;
    });

    final result = await BbsuService().getList(
      page:    _currentPage,
      perPage: _perPage,
      search:  _searchCtrl.text.trim(),
      status:  _statusFilter,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.hasError) {
        _errorMsg = result.errorMsg;
      } else {
        _records = result.records;
        _total   = result.total;
      }
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
        const Duration(milliseconds: 350), () => _load(reset: true));
  }

  void _openForm({String? id}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BbsuFormScreen(
        recordId: id,
        embedInShell: false,
        onLogout: widget.onLogout,
      ),
    ));
    _load(reset: true);
  }

  Future<void> _confirmDelete(BbsuSummary record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: Text('Delete record?',
            style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark)),
        content: Text(
          'Batch "${record.batchNo}" will be permanently deleted.',
          style: GoogleFonts.outfit(
              fontSize: 14, color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: GoogleFonts.outfit(
                    color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: Text('Delete',
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final error = await BbsuService().delete(record.id);
    if (!mounted) return;
    if (error == null) {
      _showSnack('Record deleted.');
      _load(reset: true);
    } else {
      _showSnack(error, error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          error
              ? Icons.error_outline
              : Icons.check_circle_outline,
          color: Colors.white,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Text(msg,
                style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 13))),
      ]),
      backgroundColor: error ? AppColors.error : AppColors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  int get _totalPages =>
      (_total / _perPage).ceil().clamp(1, 999);

  @override
  Widget build(BuildContext context) {
    final hPad     = Responsive.hPad(context);
    final isTablet = Responsive.isTablet(context);

    final content = Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 24),
              child: ConstrainedBox(
                constraints:
                const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Offline banner ─────────────────────
                    StreamBuilder<bool>(
                      stream: ConnectivityService().onlineStream,
                      initialData: ConnectivityService().isOnline,
                      builder: (_, snap) {
                        if (snap.data ?? true) {
                          return const SizedBox.shrink();
                        }
                        return _OfflineBanner(
                          message:
                          'You are offline. Showing cached data. '
                              'New records will sync when connection restores.',
                        );
                      },
                    ),

                    // ── Page header ────────────────────────
                    MesPageHeader(
                      title: 'Battery Breaking & Separation',
                      subtitle:
                      'Manage BBSU batch records and submissions',
                      actions: [
                        MesRefreshButton(onPressed: () => _load(reset: true)),
                        MesButton(
                          label: 'Create New',
                          icon: Icons.add,
                          onPressed: () => _openForm(),
                        ),
                      ],
                    ),

                    // ── Search + filter bar ────────────────
                    MesCard(
                      padding: const EdgeInsets.all(14),
                      child: isTablet
                          ? Row(
                          children:
                          _filterWidgets(isTablet))
                          : Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children:
                        _filterWidgets(isTablet),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Count bar ──────────────────────────
                    _CountBar(
                      total: _total,
                      hasFilters:
                      _searchCtrl.text.isNotEmpty ||
                          _statusFilter != 'all',
                      onClear: () {
                        _searchCtrl.clear();
                        setState(() => _statusFilter = 'all');
                        _load(reset: true);
                      },
                    ),
                    const SizedBox(height: 10),

                    // ── Table card ─────────────────────────
                    MesCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _isLoading
                              ? const _TableShimmer()
                              : _errorMsg != null
                              ? _ErrorState(
                            message: _errorMsg!,
                            onRetry: _load,
                          )
                              : _records.isEmpty
                              ? _EmptyState(
                              onCreate: _openForm)
                              : _RecordsTable(
                            records:   _records,
                            isTablet:  isTablet,
                            onEdit: (id) =>
                                _openForm(id: id),
                            onDelete:
                            _confirmDelete,
                          ),

                          if (!_isLoading &&
                              _records.isNotEmpty)
                            _Pagination(
                              currentPage: _currentPage,
                              totalPages:  _totalPages,
                              total:       _total,
                              perPage:     _perPage,
                              onPage: (p) {
                                setState(
                                        () => _currentPage = p);
                                _load();
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );

    if (!widget.embedInShell) return content;
    return AppShell(
      currentRoute: '/bbsu',
      onLogout: widget.onLogout,
      child: content,
    );
  }

  List<Widget> _filterWidgets(bool isTablet) {
    final search = Expanded(
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        style: GoogleFonts.outfit(
            fontSize: 13.5, color: AppColors.textDark),
        decoration: InputDecoration(
          hintText: 'Search by batch no, category…',
          hintStyle: GoogleFonts.outfit(
              fontSize: 13.5, color: AppColors.textMuted),
          prefixIcon: const Icon(Icons.search,
              size: 18, color: AppColors.textMuted),
          filled: true,
          fillColor: AppColors.greenXLight,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(
                color: AppColors.border, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(
                color: AppColors.border, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(
                color: AppColors.green, width: 1.5),
          ),
        ),
      ),
    );

    final statusDrop = SizedBox(
      width: isTablet ? 160 : double.infinity,
      child: DropdownButtonFormField<String>(
        value: _statusFilter,
        style: GoogleFonts.outfit(
            fontSize: 13, color: AppColors.textDark),
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.greenXLight,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(
                color: AppColors.border, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(
                color: AppColors.border, width: 1.5),
          ),
        ),
        items: _statusOptions
            .map((o) => DropdownMenuItem(
          value: o['value'],
          child: Text(o['label']!,
              style:
              GoogleFonts.outfit(fontSize: 13)),
        ))
            .toList(),
        onChanged: (v) {
          setState(() => _statusFilter = v ?? 'all');
          _load(reset: true);
        },
      ),
    );

    if (isTablet) {
      return [search, const SizedBox(width: 12), statusDrop];
    }
    return [search, const SizedBox(height: 10), statusDrop];
  }
}

// ─────────────────────────────────────────────
// Offline banner
// ─────────────────────────────────────────────
class _OfflineBanner extends StatelessWidget {
  final String message;
  const _OfflineBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            child: Text(message,
                style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: const Color(0xFF92400E))),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Count bar
// ─────────────────────────────────────────────
class _CountBar extends StatelessWidget {
  final int total;
  final bool hasFilters;
  final VoidCallback onClear;

  const _CountBar({
    required this.total,
    required this.hasFilters,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Showing $total record${total == 1 ? '' : 's'}',
            style: AppTextStyles.caption()),
        const Spacer(),
        if (hasFilters)
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.green,
              textStyle: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
              padding: EdgeInsets.zero,
            ),
            child: const Text('Clear filters'),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Column widths
// Date | Doc No | Start | End | Category | Status | Actions
// ─────────────────────────────────────────────
const double _tDate     = 110.0;
const double _tBatchNo  = 200.0;
const double _tStart    = 140.0;
const double _tEnd      = 140.0;
const double _tCategory = 130.0;
const double _tStatus   = 110.0;
const double _tActions  = 150.0;

// Mobile
const double _mDate    = 110.0;
const double _mBatchNo = 140.0;
const double _mStatus  = 110.0;
const double _mActions = 86.0;

// ─────────────────────────────────────────────
// Records table
// ─────────────────────────────────────────────
class _RecordsTable extends StatelessWidget {
  final List<BbsuSummary> records;
  final bool isTablet;
  final ValueChanged<String> onEdit;
  final ValueChanged<BbsuSummary> onDelete;

  const _RecordsTable({
    required this.records,
    required this.isTablet,
    required this.onEdit,
    required this.onDelete,
  });

  double get _tableWidth => isTablet
      ? _tDate + _tBatchNo + _tStart + _tEnd +
      _tCategory + _tStatus + _tActions
      : _mDate + _mBatchNo + _mStatus + _mActions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final available   = constraints.maxWidth;
      final needsScroll = _tableWidth > available;

      Widget content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TableHeader(
            isTablet:   isTablet,
            tableWidth: needsScroll ? _tableWidth : available,
          ),
          ...records.asMap().entries.map((e) => _TableRow(
            record:     e.value,
            isTablet:   isTablet,
            tableWidth: needsScroll ? _tableWidth : available,
            isLast:     e.key == records.length - 1,
            onEdit:     () => onEdit(e.value.id),
            onDelete:   () => onDelete(e.value),
          )),
        ],
      );

      return needsScroll
          ? SingleChildScrollView(
          scrollDirection: Axis.horizontal, child: content)
          : content;
    });
  }
}

// ─────────────────────────────────────────────
// Table header
// ─────────────────────────────────────────────
class _TableHeader extends StatelessWidget {
  final bool isTablet;
  final double tableWidth;

  const _TableHeader(
      {required this.isTablet, required this.tableWidth});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tableWidth,
      decoration: const BoxDecoration(
        color: AppColors.greenLight,
        border: Border(
            bottom: BorderSide(color: AppColors.border, width: 2)),
        borderRadius: BorderRadius.only(
          topLeft:  Radius.circular(14),
          topRight: Radius.circular(14),
        ),
      ),
      child: Row(
        children: isTablet
            ? [
          _hCell('Date',     _tDate),
          _hCell('Doc No',   _tBatchNo),
          _hCell('Start',    _tStart),
          _hCell('End',      _tEnd),
          _hCell('Category', _tCategory),
          _hCell('Status',   _tStatus),
          _hCell('Actions',  _tActions, center: true),
        ]
            : [
          _hCell('Date',    _mDate),
          _hCell('Doc No',  _mBatchNo),
          _hCell('Status',  _mStatus),
          _hCell('Actions', _mActions, center: true),
        ],
      ),
    );
  }

  Widget _hCell(String label, double width,
      {bool center = false}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 11),
        child: Align(
          alignment:
          center ? Alignment.center : Alignment.centerLeft,
          child: Text(label.toUpperCase(),
              style: AppTextStyles.label(
                  color: AppColors.green)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Table row
// ─────────────────────────────────────────────
class _TableRow extends StatefulWidget {
  final BbsuSummary record;
  final bool isTablet, isLast;
  final double tableWidth;
  final VoidCallback onEdit, onDelete;

  const _TableRow({
    required this.record,
    required this.isTablet,
    required this.isLast,
    required this.tableWidth,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_TableRow> createState() => _TableRowState();
}

class _TableRowState extends State<_TableRow> {
  bool _hovered = false;

  String _fmtDate(String raw) {
    try {
      return DateFormat('dd/MM/yyyy')
          .format(DateTime.parse(raw));
    } catch (_) {
      return raw.length >= 10 ? raw.substring(0, 10) : raw;
    }
  }

  String _fmtDateTime(String raw) {
    try {
      final d = DateTime.parse(raw).toLocal();
      return DateFormat('dd/MM/yy HH:mm').format(d);
    } catch (_) {
      return raw.length >= 16 ? raw.substring(0, 16) : raw;
    }
  }

  Widget _statusBadge(String label) {
    final isSubmitted = label.toLowerCase() == 'submitted';
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isSubmitted
            ? const Color(0xFFDCFCE7)
            : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isSubmitted
              ? const Color(0xFF16A34A)
              : const Color(0xFF92400E),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r          = widget.record;
    final canDelete  = r.statusCode == 0;

    Widget cell(double width, Widget child,
        {bool center = false}) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          child: center ? Center(child: child) : child,
        ),
      );
    }

    Widget txt(String text,
        {bool bold = false, bool muted = false}) =>
        Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight:
            bold ? FontWeight.w600 : FontWeight.w400,
            color: bold
                ? AppColors.textDark
                : muted
                ? AppColors.textMuted
                : AppColors.textMid,
          ),
        );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: widget.tableWidth,
        decoration: BoxDecoration(
          color: _hovered
              ? AppColors.greenXLight
              : AppColors.white,
          border: widget.isLast
              ? null
              : const Border(
              bottom: BorderSide(
                  color: AppColors.borderLight)),
        ),
        child: Row(
          children: widget.isTablet
              ? [
            cell(_tDate,
                txt(_fmtDate(r.docDate), muted: true)),
            cell(_tBatchNo, _batchNoWidget(r)),
            cell(_tStart,
                txt(_fmtDateTime(r.startTime),
                    muted: true)),
            cell(_tEnd,
                txt(_fmtDateTime(r.endTime),
                    muted: true)),
            cell(_tCategory, txt(r.category)),
            cell(_tStatus,
                _statusBadge(r.statusLabel)),
            cell(_tActions,
                _actionsCell(canDelete),
                center: true),
          ]
              : [
            cell(_mDate,
                txt(_fmtDate(r.docDate), muted: true)),
            cell(_mBatchNo, _batchNoWidget(r)),
            cell(_mStatus,
                _statusBadge(r.statusLabel)),
            cell(_mActions,
                _actionsCell(canDelete),
                center: true),
          ],
        ),
      ),
    );
  }

  Widget _batchNoWidget(BbsuSummary r) {
    final isPending = r.syncStatus == 'pending';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isPending)
          Tooltip(
            message: 'Not yet synced to server',
            child: Container(
              width: 8, height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(
                  color: AppColors.warning,
                  shape: BoxShape.circle),
            ),
          ),
        Flexible(
          child: Text(r.batchNo,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _actionsCell(bool canDelete) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ActionBtn(
          icon:      Icons.edit_outlined,
          bg:        AppColors.greenLight,
          iconColor: AppColors.green,
          onTap:     widget.onEdit,
          tooltip:   'Edit',
        ),
        if (canDelete) ...[
          const SizedBox(width: 6),
          _ActionBtn(
            icon:      Icons.delete_outline,
            bg:        const Color(0xFFFEE2E2),
            iconColor: AppColors.error,
            onTap:     widget.onDelete,
            tooltip:   'Delete',
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Action button
// ─────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color bg, iconColor;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionBtn({
    required this.icon,
    required this.bg,
    required this.iconColor,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7)),
        child: Icon(icon, size: 30, color: iconColor),
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// Pagination
// ─────────────────────────────────────────────
class _Pagination extends StatelessWidget {
  final int currentPage, totalPages, total, perPage;
  final ValueChanged<int> onPage;

  const _Pagination({
    required this.currentPage,
    required this.totalPages,
    required this.total,
    required this.perPage,
    required this.onPage,
  });

  @override
  Widget build(BuildContext context) {
    final start = ((currentPage - 1) * perPage) + 1;
    final end   = (currentPage * perPage).clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 20, vertical: 13),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border:
        Border(top: BorderSide(color: AppColors.borderLight)),
        borderRadius: BorderRadius.only(
          bottomLeft:  Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Row(
        children: [
          Text('Showing $start–$end of $total',
              style: AppTextStyles.caption()),
          const Spacer(),
          Row(children: [
            _PageBtn(
                icon: Icons.chevron_left,
                enabled: currentPage > 1,
                onTap: () => onPage(currentPage - 1)),
            const SizedBox(width: 4),
            ...List.generate(totalPages.clamp(0, 5), (i) {
              final p = i + 1;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _PageBtn(
                    label: '$p',
                    active: p == currentPage,
                    onTap: () => onPage(p)),
              );
            }),
            _PageBtn(
                icon: Icons.chevron_right,
                enabled: currentPage < totalPages,
                onTap: () => onPage(currentPage + 1)),
          ]),
        ],
      ),
    );
  }
}

class _PageBtn extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool active, enabled;
  final VoidCallback onTap;

  const _PageBtn(
      {this.label,
        this.icon,
        this.active = false,
        this.enabled = true,
        required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: active ? AppColors.green : AppColors.white,
        borderRadius: BorderRadius.circular(7),
        border:
        active ? null : Border.all(color: AppColors.borderLight),
      ),
      child: Center(
        child: label != null
            ? Text(label!,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active
                  ? Colors.white
                  : enabled
                  ? AppColors.textMid
                  : AppColors.textMuted,
            ))
            : Icon(icon,
            size: 18,
            color: enabled
                ? AppColors.textMid
                : AppColors.textMuted),
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// Empty / Error / Shimmer
// ─────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 60),
    child: Center(
      child: Column(
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
                color: AppColors.greenLight,
                borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.precision_manufacturing_outlined,
                size: 32, color: AppColors.green),
          ),
          const SizedBox(height: 14),
          Text('No records found',
              style: AppTextStyles.subheading(
                  color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text('Create your first BBSU batch to get started',
              style: AppTextStyles.caption()),
          const SizedBox(height: 20),
          MesButton(
              label: '+ Create First Record',
              onPressed: onCreate),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState(
      {required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: Column(
        children: [
          const Icon(Icons.wifi_off_outlined,
              size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, style: AppTextStyles.body()),
          const SizedBox(height: 14),
          MesOutlineButton(
              label: 'Retry',
              icon: Icons.refresh,
              onPressed: onRetry),
        ],
      ),
    ),
  );
}

class _TableShimmer extends StatefulWidget {
  const _TableShimmer();
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
        duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.85).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Column(
      children: List.generate(
          8,
              (i) => Container(
            height: 46,
            margin: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.borderLight
                  .withOpacity(_anim.value),
              borderRadius: BorderRadius.circular(8),
            ),
          )),
    ),
  );
}