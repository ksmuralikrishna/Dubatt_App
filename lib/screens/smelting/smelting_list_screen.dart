// ─────────────────────────────────────────────────────────────────────────────
// smelting_list_screen.dart
// Columns: Batch No | Date | Rotary | Start | End | Output Material | Qty | Status | Actions
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../widgets/common/app_shell.dart';
import '../../models/smelting_model.dart';
import '../../services/smelting_service.dart';
import '../../services/connectivity_service.dart';
import 'smelting_form_screen.dart';
import 'package:dubatt_app/services/sync_service.dart';

class SmeltingListScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final bool embedInShell;
  const SmeltingListScreen({
    super.key,
    required this.onLogout,
    this.embedInShell = true,
  });

  @override
  State<SmeltingListScreen> createState() => _SmeltingListScreenState();
}

class _SmeltingListScreenState extends State<SmeltingListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<SyncState>? _syncSub;

  List<SmeltingSummary> _records = [];
  bool _isLoading = true;
  String? _errorMsg;
  int _total       = 0;
  int _currentPage = 1;
  static const _perPage = 20;

  String _statusFilter = 'all';
  String _rotaryFilter = '';

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
    setState(() { _isLoading = true; _errorMsg = null; });

    final result = await SmeltingService().getList(
      page:     _currentPage,
      perPage:  _perPage,
      search:   _searchCtrl.text.trim(),
      status:   _statusFilter,
      rotaryNo: _rotaryFilter,
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
      builder: (_) =>
          SmeltingFormScreen(recordId: id, onLogout: widget.onLogout),
    ));
    _load(reset: true);
  }

  Future<void> _confirmDelete(SmeltingSummary record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: Text('Delete batch?',
            style: GoogleFonts.outfit(
                fontSize: 16, fontWeight: FontWeight.w600,
                color: AppColors.textDark)),
        content: Text('Batch "${record.batchNo}" will be permanently deleted.',
            style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMid)),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: Text('Delete',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final error = await SmeltingService().delete(record.id);
    if (!mounted) return;
    if (error == null) {
      _showSnack('Batch deleted.');
      _load(reset: true);
    } else {
      _showSnack(error, error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 13))),
      ]),
      backgroundColor: error ? AppColors.error : AppColors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  int get _totalPages => (_total / _perPage).ceil().clamp(1, 999);

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
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Offline banner
                    StreamBuilder<bool>(
                      stream: ConnectivityService().onlineStream,
                      initialData: ConnectivityService().isOnline,
                      builder: (_, snap) {
                        if (snap.data ?? true) return const SizedBox.shrink();
                        return _OfflineBanner(
                          'You are offline. Showing cached data. '
                              'New records will sync when connection restores.',
                        );
                      },
                    ),

                    MesPageHeader(
                      title: 'Smelting Batches',
                      subtitle: 'Manage rotary furnace smelting batch records',
                      actions: [
                        MesRefreshButton(onPressed: () => _load(reset: true)),
                        MesButton(
                          label: 'Create New',
                          icon: Icons.add,
                          onPressed: () => _openForm(),
                        ),
                      ],
                    ),

                    // Filter bar
                    MesCard(
                      padding: const EdgeInsets.all(14),
                      child: isTablet
                          ? Row(children: _filters(isTablet))
                          : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _filters(isTablet)),
                    ),
                    const SizedBox(height: 10),

                    // Count bar
                    Row(children: [
                      Text('Showing $_total record${_total == 1 ? '' : 's'}',
                          style: AppTextStyles.caption()),
                      const Spacer(),
                      if (_searchCtrl.text.isNotEmpty ||
                          _statusFilter != 'all' ||
                          _rotaryFilter.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {
                              _statusFilter = 'all';
                              _rotaryFilter = '';
                            });
                            _load(reset: true);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.green,
                            textStyle: GoogleFonts.outfit(
                                fontSize: 12, fontWeight: FontWeight.w600),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text('Clear filters'),
                        ),
                    ]),
                    const SizedBox(height: 10),

                    // Table
                    MesCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        _isLoading
                            ? const _Shimmer()
                            : _errorMsg != null
                            ? _ErrorState(_errorMsg!, _load)
                            : _records.isEmpty
                            ? _EmptyState(() => _openForm())
                            : _Table(
                          records:  _records,
                          isTablet: isTablet,
                          onEdit: (id) => _openForm(id: id),
                          onDelete: _confirmDelete,
                        ),
                        if (!_isLoading && _records.isNotEmpty)
                          _Pagination(
                            currentPage: _currentPage,
                            totalPages:  _totalPages,
                            total:       _total,
                            perPage:     _perPage,
                            onPage: (p) {
                              setState(() => _currentPage = p);
                              _load();
                            },
                          ),
                      ]),
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
      currentRoute: '/smelting',
      onLogout: widget.onLogout,
      child: content,
    );
  }

  InputDecoration _filterDec() => InputDecoration(
    filled: true,
    fillColor: AppColors.greenXLight,
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
  );

  List<Widget> _filters(bool tablet) {
    final search = Expanded(
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        style: GoogleFonts.outfit(fontSize: 13.5, color: AppColors.textDark),
        decoration: InputDecoration(
          hintText: 'Search by batch no…',
          hintStyle: GoogleFonts.outfit(fontSize: 13.5, color: AppColors.textMuted),
          prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
          filled: true,
          fillColor: AppColors.greenXLight,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
        ),
      ),
    );

    final statusDrop = SizedBox(
      width: tablet ? 150 : double.infinity,
      child: DropdownButtonFormField<String>(
        value: _statusFilter,
        style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textDark),
        decoration: _filterDec(),
        items: const [
          DropdownMenuItem(value: 'all',   child: Text('All Status')),
          DropdownMenuItem(value: '0',     child: Text('Draft')),
          DropdownMenuItem(value: '1',     child: Text('Submitted')),
        ],
        onChanged: (v) {
          setState(() => _statusFilter = v ?? 'all');
          _load(reset: true);
        },
      ),
    );

    final rotaryDrop = SizedBox(
      width: tablet ? 140 : double.infinity,
      child: DropdownButtonFormField<String>(
        value: _rotaryFilter,
        style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textDark),
        decoration: _filterDec(),
        items: const [
          DropdownMenuItem(value: '',  child: Text('All Rotary')),
          DropdownMenuItem(value: '1', child: Text('Rotary 1')),
          DropdownMenuItem(value: '2', child: Text('Rotary 2')),
        ],
        onChanged: (v) {
          setState(() => _rotaryFilter = v ?? '');
          _load(reset: true);
        },
      ),
    );

    if (tablet) {
      return [
        search,
        const SizedBox(width: 12),
        statusDrop,
        const SizedBox(width: 12),
        rotaryDrop,
      ];
    }
    return [
      search,
      const SizedBox(height: 10),
      statusDrop,
      const SizedBox(height: 10),
      rotaryDrop,
    ];
  }
}

// ─────────────────────────────────────────────
// Offline banner
// ─────────────────────────────────────────────
class _OfflineBanner extends StatelessWidget {
  final String message;
  const _OfflineBanner(this.message);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF3C7),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xFFF59E0B)),
    ),
    child: Row(children: [
      const Icon(Icons.wifi_off, size: 16, color: Color(0xFFF59E0B)),
      const SizedBox(width: 8),
      Expanded(child: Text(message,
          style: GoogleFonts.outfit(fontSize: 13,
              color: const Color(0xFF92400E)))),
    ]),
  );
}

// ─────────────────────────────────────────────
// Column widths
// ─────────────────────────────────────────────
const double _tBatchNo  = 180.0;
const double _tDate     = 120.0;
const double _tRotary   = 90.0;
const double _tStart    = 80.0;
const double _tEnd      = 80.0;
const double _tOutMat   = 150.0;
const double _tOutQty   = 100.0;
const double _tStatus   = 100.0;
const double _tActions  = 150.0;

const double _mBatchNo  = 130.0;
const double _mDate     = 100.0;
const double _mStatus   = 100.0;
const double _mActions  = 110.0;

// ─────────────────────────────────────────────
// Table
// ─────────────────────────────────────────────
class _Table extends StatelessWidget {
  final List<SmeltingSummary> records;
  final bool isTablet;
  final ValueChanged<String> onEdit;
  final ValueChanged<SmeltingSummary> onDelete;

  const _Table({
    required this.records, required this.isTablet,
    required this.onEdit, required this.onDelete,
  });

  double get _w => isTablet
      ? _tBatchNo + _tDate + _tRotary + _tStart + _tEnd +
      _tOutMat + _tOutQty + _tStatus + _tActions
      : _mBatchNo + _mDate + _mStatus + _mActions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final needs = _w > box.maxWidth;
      Widget content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(isTablet: isTablet, tableWidth: needs ? _w : box.maxWidth),
          ...records.asMap().entries.map((e) => _Row(
            record:     e.value,
            isTablet:   isTablet,
            tableWidth: needs ? _w : box.maxWidth,
            isLast:     e.key == records.length - 1,
            onEdit:     () => onEdit(e.value.id),
            onDelete:   () => onDelete(e.value),
          )),
        ],
      );
      return needs
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: content)
          : content;
    });
  }
}

class _Header extends StatelessWidget {
  final bool isTablet;
  final double tableWidth;
  const _Header({required this.isTablet, required this.tableWidth});

  @override
  Widget build(BuildContext context) => Container(
    width: tableWidth,
    decoration: const BoxDecoration(
      color: AppColors.greenLight,
      border: Border(bottom: BorderSide(color: AppColors.border, width: 2)),
      borderRadius: BorderRadius.only(
          topLeft: Radius.circular(14), topRight: Radius.circular(14)),
    ),
    child: Row(children: isTablet
        ? [
      _h('Batch No',   _tBatchNo),
      _h('Date',       _tDate),
      _h('Rotary',     _tRotary,  center: true),
      _h('Start',      _tStart),
      _h('End',        _tEnd),
      _h('Output Mat', _tOutMat),
      _h('Qty (KG)',   _tOutQty,  right: true),
      _h('Status',     _tStatus),
      _h('Actions',    _tActions, center: true),
    ]
        : [
      _h('Batch No', _mBatchNo),
      _h('Date',     _mDate),
      _h('Status',   _mStatus),
      _h('Actions',  _mActions, center: true),
    ]),
  );

  Widget _h(String label, double w,
      {bool center = false, bool right = false}) =>
      SizedBox(
        width: w,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Align(
            alignment: center
                ? Alignment.center
                : right
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Text(label.toUpperCase(),
                style: AppTextStyles.label(color: AppColors.green)),
          ),
        ),
      );
}

class _Row extends StatefulWidget {
  final SmeltingSummary record;
  final bool isTablet, isLast;
  final double tableWidth;
  final VoidCallback onEdit, onDelete;

  const _Row({
    required this.record, required this.isTablet, required this.isLast,
    required this.tableWidth, required this.onEdit, required this.onDelete,
  });

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hov = false;

  String _fmtDate(String raw) {
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(raw)); }
    catch (_) { return raw.length >= 10 ? raw.substring(0, 10) : raw; }
  }

  String _fmtTime(String? raw) => SmeltingService.toHHmm(raw) ?? '—';

  Widget _statusBadge(String label) {
    final sub = label.toLowerCase() == 'submitted';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: sub ? const Color(0xFFDCFCE7) : const Color(0xFFE0E7FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600,
              color: sub ? const Color(0xFF16A34A) : const Color(0xFF3730A3))),
    );
  }

  Widget _rotaryBadge(String no) {
    final one = no == '1';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: one ? const Color(0xFFFEF3C7) : const Color(0xFFEDE9FE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('Rotary $no',
          style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700,
              color: one ? const Color(0xFF92400E) : const Color(0xFF5B21B6))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r          = widget.record;
    final fmt        = NumberFormat('#,##0.000');
    final canDelete  = r.statusCode == 0;

    Widget cell(double w, Widget child,
        {bool right = false, bool center = false}) =>
        SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: center
                ? Center(child: child)
                : right
                ? Align(alignment: Alignment.centerRight, child: child)
                : child,
          ),
        );

    Widget txt(String t, {bool bold = false, bool muted = false}) =>
        Text(t, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              color: bold ? AppColors.textDark : muted ? AppColors.textMuted : AppColors.textMid,
            ));

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: widget.tableWidth,
        decoration: BoxDecoration(
          color: _hov ? AppColors.greenXLight : AppColors.white,
          border: widget.isLast
              ? null
              : const Border(bottom: BorderSide(color: AppColors.borderLight)),
        ),
        child: Row(children: widget.isTablet
            ? [
          cell(_tBatchNo, _batchWidget(r)),
          cell(_tDate,    txt(_fmtDate(r.date), muted: true)),
          cell(_tRotary,  _rotaryBadge(r.rotaryNo), center: true),
          cell(_tStart,   txt(_fmtTime(r.startTime), muted: true)),
          cell(_tEnd,     txt(_fmtTime(r.endTime), muted: true)),
          cell(_tOutMat,  txt(r.outputMaterialName ?? '—')),
          cell(_tOutQty,  txt(r.outputQty != null ? fmt.format(r.outputQty) : '—'),
              right: true),
          cell(_tStatus,  _statusBadge(r.statusLabel)),
          cell(_tActions, _actions(canDelete), center: true),
        ]
            : [
          cell(_mBatchNo, _batchWidget(r)),
          cell(_mDate,    txt(_fmtDate(r.date), muted: true)),
          cell(_mStatus,  _statusBadge(r.statusLabel)),
          cell(_mActions, _actions(canDelete), center: true),
        ]),
      ),
    );
  }

  Widget _batchWidget(SmeltingSummary r) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (r.syncStatus == 'pending')
        Tooltip(
          message: 'Not yet synced to server',
          child: Container(
            width: 8, height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: const BoxDecoration(
                color: AppColors.warning, shape: BoxShape.circle),
          ),
        ),
      Flexible(
        child: Text(r.batchNo,
            style: GoogleFonts.outfit(fontSize: 13,
                fontWeight: FontWeight.w600, color: AppColors.textDark),
            overflow: TextOverflow.ellipsis),
      ),
    ],
  );

  Widget _actions(bool canDelete) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _Btn(icon: Icons.edit_outlined, bg: AppColors.greenLight,
          fg: AppColors.green, onTap: widget.onEdit, tip: 'Edit'),
      if (canDelete) ...[
        const SizedBox(width: 6),
        _Btn(icon: Icons.delete_outline, bg: const Color(0xFFFEE2E2),
            fg: AppColors.error, onTap: widget.onDelete, tip: 'Delete'),
      ],
    ],
  );
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final Color bg, fg;
  final VoidCallback onTap;
  final String tip;
  const _Btn({required this.icon, required this.bg, required this.fg,
    required this.onTap, required this.tip});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50, height: 50,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
        child: Icon(icon, size: 30, color: fg),
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
  const _Pagination({required this.currentPage, required this.totalPages,
    required this.total, required this.perPage, required this.onPage});

  @override
  Widget build(BuildContext context) {
    final start = ((currentPage - 1) * perPage) + 1;
    final end   = (currentPage * perPage).clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
      ),
      child: Row(children: [
        Text('Showing $start–$end of $total', style: AppTextStyles.caption()),
        const Spacer(),
        Row(children: [
          _PBtn(icon: Icons.chevron_left, enabled: currentPage > 1,
              onTap: () => onPage(currentPage - 1)),
          const SizedBox(width: 4),
          ...List.generate(totalPages.clamp(0, 5), (i) {
            final p = i + 1;
            return Padding(padding: const EdgeInsets.only(right: 4),
                child: _PBtn(label: '$p', active: p == currentPage,
                    onTap: () => onPage(p)));
          }),
          _PBtn(icon: Icons.chevron_right, enabled: currentPage < totalPages,
              onTap: () => onPage(currentPage + 1)),
        ]),
      ]),
    );
  }
}

class _PBtn extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool active, enabled;
  final VoidCallback onTap;
  const _PBtn({this.label, this.icon, this.active = false,
    this.enabled = true, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: active ? AppColors.green : AppColors.white,
        borderRadius: BorderRadius.circular(7),
        border: active ? null : Border.all(color: AppColors.borderLight),
      ),
      child: Center(
        child: label != null
            ? Text(label!,
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600,
                color: active ? Colors.white : enabled ? AppColors.textMid : AppColors.textMuted))
            : Icon(icon, size: 18,
            color: enabled ? AppColors.textMid : AppColors.textMuted),
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// Empty / Error / Shimmer
// ─────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState(this.onCreate);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 60),
    child: Center(child: Column(children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(color: AppColors.greenLight,
            borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.local_fire_department_outlined,
            size: 32, color: AppColors.green),
      ),
      const SizedBox(height: 14),
      Text('No batches found',
          style: AppTextStyles.subheading(color: AppColors.textMuted)),
      const SizedBox(height: 4),
      Text('Create your first smelting batch to get started',
          style: AppTextStyles.caption()),
      const SizedBox(height: 20),
      MesButton(label: '+ Create First Batch', onPressed: onCreate),
    ])),
  );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState(this.message, this.onRetry);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(child: Column(children: [
      const Icon(Icons.wifi_off_outlined, size: 40, color: AppColors.textMuted),
      const SizedBox(height: 12),
      Text(message, style: AppTextStyles.body()),
      const SizedBox(height: 14),
      MesOutlineButton(label: 'Retry', icon: Icons.refresh, onPressed: onRetry),
    ])),
  );
}

class _Shimmer extends StatefulWidget {
  const _Shimmer();
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _a = Tween<double>(begin: 0.4, end: 0.85).animate(_c);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (_, __) => Column(
      children: List.generate(8, (i) => Container(
        height: 46,
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.borderLight.withOpacity(_a.value),
          borderRadius: BorderRadius.circular(8),
        ),
      )),
    ),
  );
}