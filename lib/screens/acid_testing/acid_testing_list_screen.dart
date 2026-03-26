import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../widgets/common/app_shell.dart';
import '../../models/acid_testing_model.dart';
import '../../services/acid_testing_service.dart';
import 'package:dubatt_app/services/connectivity_service.dart';
import 'acid_testing_form_screen.dart';

class AcidTestingListScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const AcidTestingListScreen({super.key, required this.onLogout});

  @override
  State<AcidTestingListScreen> createState() => _AcidTestingListScreenState();
}

class _AcidTestingListScreenState extends State<AcidTestingListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  StreamSubscription<bool>? _connectivitySub;

  List<AcidTestingSummary> _records = [];
  bool _isLoading  = true;
  String? _errorMsg;
  int _total       = 0;
  int _currentPage = 1;
  static const _perPage = 20;

  String _statusFilter = 'all';
  String _sortBy       = 'test_date';
  String _sortOrder    = 'desc';

  final _statusOptions = const [
    {'value': 'all',      'label': 'All Status'},
    {'value': 'pending',  'label': 'Pending'},
    {'value': 'approved', 'label': 'Approved'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _connectivitySub = ConnectivityService().onlineStream.listen((online) {
      if (online && mounted) _load(reset: true);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _connectivitySub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _currentPage = 1;
    setState(() { _isLoading = true; _errorMsg = null; });

    final result = await AcidTestingService().getList(
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

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(
        const Duration(milliseconds: 350), () => _load(reset: true));
  }

  void _openForm({String? id}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AcidTestingFormScreen(
        recordId: id,
        onLogout: widget.onLogout,
      ),
    ));
    _load(reset: true);
  }

  Future<void> _confirmDelete(AcidTestingSummary record) async {
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
          'Lot "${record.lotNumber}" will be permanently deleted. '
              'This cannot be undone.',
          style: GoogleFonts.outfit(
              fontSize: 14, color: AppColors.textMid),
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
    final error = await AcidTestingService().delete(record.id);
    if (!mounted) return;
    if (error == null) {
      _showSnack('Record deleted successfully.');
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
        Expanded(
            child: Text(msg,
                style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 13))),
      ]),
      backgroundColor: error ? AppColors.error : AppColors.green,
      behavior: SnackBarBehavior.floating,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  int get _totalPages => (_total / _perPage).ceil().clamp(1, 999);

  @override
  Widget build(BuildContext context) {
    final hPad     = Responsive.hPad(context);
    final isTablet = Responsive.isTablet(context);

    return AppShell(
      currentRoute: '/acid-testing',
      onLogout: widget.onLogout,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 24),
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
                            border: Border.all(
                                color: const Color(0xFFF59E0B)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.wifi_off,
                                size: 16, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'You are offline. Showing cached data.',
                                style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: const Color(0xFF92400E)),
                              ),
                            ),
                          ]),
                        );
                      },
                    ),

                    // ── Page header ────────────────────────────────
                    MesPageHeader(
                      title: 'Acid Testing',
                      subtitle:
                      'Manage and track all acid testing records',
                      actions: [
                        MesButton(
                          label: 'Create New',
                          icon: Icons.add,
                          onPressed: () => _openForm(),
                        ),
                      ],
                    ),

                    // ── Search + filter ────────────────────────────
                    MesCard(
                      padding: const EdgeInsets.all(14),
                      child: isTablet
                          ? Row(children: _filterWidgets(isTablet))
                          : Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: _filterWidgets(isTablet),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Count + clear ──────────────────────────────
                    _CountBar(
                      total: _total,
                      hasFilters: _searchCtrl.text.isNotEmpty ||
                          _statusFilter != 'all',
                      onClear: () {
                        _searchCtrl.clear();
                        setState(() => _statusFilter = 'all');
                        _load(reset: true);
                      },
                    ),
                    const SizedBox(height: 10),

                    // ── Table ──────────────────────────────────────
                    MesCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _isLoading
                              ? const _TableShimmer()
                              : _errorMsg != null
                              ? _ErrorState(
                            message: _errorMsg!,
                            onRetry: () => _load(),
                          )
                              : _records.isEmpty
                              ? _EmptyState(
                              onCreate: () => _openForm())
                              : _RecordsTable(
                            records:   _records,
                            isTablet:  isTablet,
                            sortBy:    _sortBy,
                            sortOrder: _sortOrder,
                            onSort: (col) {
                              setState(() {
                                if (_sortBy == col) {
                                  _sortOrder =
                                  _sortOrder == 'asc'
                                      ? 'desc'
                                      : 'asc';
                                } else {
                                  _sortBy    = col;
                                  _sortOrder = 'desc';
                                }
                              });
                              _load();
                            },
                            onEdit: (id) =>
                                _openForm(id: id),
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
          hintText: 'Search by lot no, supplier...',
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
            borderSide:
            const BorderSide(color: AppColors.border, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide:
            const BorderSide(color: AppColors.border, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide:
            const BorderSide(color: AppColors.green, width: 1.5),
          ),
        ),
      ),
    );

    final statusDrop = SizedBox(
      width: isTablet ? 170 : double.infinity,
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
            borderSide:
            const BorderSide(color: AppColors.border, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide:
            const BorderSide(color: AppColors.border, width: 1.5),
          ),
        ),
        items: _statusOptions
            .map((o) => DropdownMenuItem(
          value: o['value'],
          child: Text(o['label']!,
              style: GoogleFonts.outfit(fontSize: 13)),
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
    return Row(children: [
      Text('Showing $total record${total == 1 ? '' : 's'}',
          style: AppTextStyles.caption()),
      const Spacer(),
      if (hasFilters)
        TextButton(
          onPressed: onClear,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.green,
            textStyle: GoogleFonts.outfit(
                fontSize: 12, fontWeight: FontWeight.w600),
            padding: EdgeInsets.zero,
          ),
          child: const Text('Clear filters'),
        ),
    ]);
  }
}

// ─────────────────────────────────────────────
// Column width constants
// ─────────────────────────────────────────────
const double _tLotNo    = 130.0;
const double _tDate     = 110.0;
const double _tSupplier = 170.0;
const double _tVehicle  = 120.0;
const double _tRecvQty  = 110.0;
const double _tAvgPF    = 110.0;
const double _tStatus   = 110.0;
const double _tActions  = 96.0;

const double _mLotNo    = 130.0;
const double _mDate     = 110.0;
const double _mStatus   = 110.0;
const double _mActions  = 96.0;

// ─────────────────────────────────────────────
// Records table
// ─────────────────────────────────────────────
class _RecordsTable extends StatelessWidget {
  final List<AcidTestingSummary> records;
  final bool isTablet;
  final String sortBy, sortOrder;
  final ValueChanged<String> onSort;
  final ValueChanged<String> onEdit;
  final ValueChanged<AcidTestingSummary> onDelete;

  const _RecordsTable({
    required this.records,
    required this.isTablet,
    required this.sortBy,
    required this.sortOrder,
    required this.onSort,
    required this.onEdit,
    required this.onDelete,
  });

  double get _tableWidth => isTablet
      ? _tLotNo + _tDate + _tSupplier + _tVehicle +
      _tRecvQty + _tAvgPF + _tStatus + _tActions
      : _mLotNo + _mDate + _mStatus + _mActions;

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
            sortBy:     sortBy,
            sortOrder:  sortOrder,
            onSort:     onSort,
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
  final String sortBy, sortOrder;
  final ValueChanged<String> onSort;

  const _TableHeader({
    required this.isTablet,
    required this.tableWidth,
    required this.sortBy,
    required this.sortOrder,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tableWidth,
      decoration: const BoxDecoration(
        color: AppColors.greenLight,
        border: Border(
            bottom: BorderSide(color: AppColors.border, width: 2)),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
      ),
      child: Row(
        children: isTablet
            ? [
          _hCell('Lot No',   _tLotNo,
              key: 'lot_number', sortable: true),
          _hCell('Date',     _tDate,
              key: 'test_date', sortable: true),
          _hCell('Supplier', _tSupplier),
          _hCell('Vehicle',  _tVehicle),
          _hCell('Recv Qty', _tRecvQty, right: true),
          _hCell('Avg P&F',  _tAvgPF,   right: true),
          _hCell('Status',   _tStatus),
          _hCell('Actions',  _tActions,  center: true),
        ]
            : [
          _hCell('Lot No',  _mLotNo,
              key: 'lot_number', sortable: true),
          _hCell('Date',    _mDate,
              key: 'test_date', sortable: true),
          _hCell('Status',  _mStatus),
          _hCell('Actions', _mActions, center: true),
        ],
      ),
    );
  }

  Widget _hCell(String label, double width,
      {String key = '',
        bool sortable = false,
        bool right = false,
        bool center = false}) {
    return GestureDetector(
      onTap: sortable ? () => onSort(key) : null,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 11),
          child: Row(
            mainAxisAlignment: center
                ? MainAxisAlignment.center
                : right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  style: AppTextStyles.label(color: AppColors.green)),
              if (sortable) ...[
                const SizedBox(width: 4),
                Icon(
                  sortBy == key
                      ? sortOrder == 'asc'
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down
                      : Icons.unfold_more,
                  size: 14,
                  color: sortBy == key
                      ? AppColors.green
                      : AppColors.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Table row
// ─────────────────────────────────────────────
class _TableRow extends StatefulWidget {
  final AcidTestingSummary record;
  final bool isTablet, isLast;
  final double tableWidth;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(raw));
    } catch (_) {
      return raw.length >= 10 ? raw.substring(0, 10) : raw;
    }
  }

  Widget _statusBadge(String label) {
    Color bg, fg;
    switch (label.toLowerCase()) {
      case 'approved':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        break;
      case 'pending':
      default:
        bg = const Color(0xFFF1F5F9);
        fg = AppColors.textMuted;
    }
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration:
      BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r         = widget.record;
    final fmt       = NumberFormat('#,##0.00');
    final canDelete = r.statusCode == 0;

    Widget cell(double width, Widget child,
        {bool right = false, bool center = false}) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          child: center
              ? Center(child: child)
              : right
              ? Align(
              alignment: Alignment.centerRight, child: child)
              : child,
        ),
      );
    }

    Widget txt(String text,
        {bool bold = false, bool muted = false}) =>
        Text(text,
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
            ));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: widget.tableWidth,
        decoration: BoxDecoration(
          color:
          _hovered ? AppColors.greenXLight : AppColors.white,
          border: widget.isLast
              ? null
              : const Border(
              bottom:
              BorderSide(color: AppColors.borderLight)),
        ),
        child: Row(
          children: widget.isTablet
              ? [
            cell(_tLotNo,    _lotNoWidget(r)),
            cell(_tDate,
                txt(_fmtDate(r.testDate), muted: true)),
            cell(_tSupplier, txt(r.supplierName)),
            cell(_tVehicle,  txt(r.vehicleNumber)),
            cell(_tRecvQty,
                txt(fmt.format(r.receivedQty)), right: true),
            cell(_tAvgPF,
                txt(fmt.format(r.avgPalletAndForeignWeight)),
                right: true),
            cell(_tStatus,   _statusBadge(r.statusLabel)),
            cell(_tActions,  _actionsCell(canDelete),
                center: true),
          ]
              : [
            cell(_mLotNo,   _lotNoWidget(r)),
            cell(_mDate,
                txt(_fmtDate(r.testDate), muted: true)),
            cell(_mStatus,  _statusBadge(r.statusLabel)),
            cell(_mActions, _actionsCell(canDelete),
                center: true),
          ],
        ),
      ),
    );
  }

  Widget _lotNoWidget(AcidTestingSummary r) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (r.syncStatus == 'pending')
          Tooltip(
            message: 'Not yet synced to server',
            child: Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(
                  color: AppColors.warning, shape: BoxShape.circle),
            ),
          ),
        Flexible(
          child: Text(r.lotNumber,
              style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark),
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
          icon: Icons.edit_outlined,
          bg: AppColors.greenLight,
          iconColor: AppColors.green,
          onTap: widget.onEdit,
          tooltip: 'Edit',
        ),
        if (canDelete) ...[
          const SizedBox(width: 6),
          _ActionBtn(
            icon: Icons.delete_outline,
            bg: const Color(0xFFFEE2E2),
            iconColor: AppColors.error,
            onTap: widget.onDelete,
            tooltip: 'Delete',
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
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, size: 15, color: iconColor),
        ),
      ),
    );
  }
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
        borderRadius: BorderRadius.only(
          bottomLeft:  Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Row(children: [
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
            final p      = i + 1;
            final active = p == currentPage;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _PageBtn(
                  label: '$p', active: active, onTap: () => onPage(p)),
            );
          }),
          _PageBtn(
              icon: Icons.chevron_right,
              enabled: currentPage < totalPages,
              onTap: () => onPage(currentPage + 1)),
        ]),
      ]),
    );
  }
}

class _PageBtn extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool active, enabled;
  final VoidCallback onTap;

  const _PageBtn({
    this.label,
    this.icon,
    this.active  = false,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
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
}

// ─────────────────────────────────────────────
// States: empty / error / shimmer
// ─────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
                color: AppColors.greenLight,
                borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.science_outlined,
                size: 32, color: AppColors.green),
          ),
          const SizedBox(height: 14),
          Text('No records found',
              style: AppTextStyles.subheading(
                  color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text('Create your first acid testing record to get started',
              style: AppTextStyles.caption()),
          const SizedBox(height: 20),
          MesButton(
              label: '+ Create First Record',
              onPressed: onCreate),
        ]),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(children: [
          const Icon(Icons.wifi_off_outlined,
              size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, style: AppTextStyles.body()),
          const SizedBox(height: 14),
          MesOutlineButton(
              label: 'Retry',
              icon: Icons.refresh,
              onPressed: onRetry),
        ]),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Column(
        children: List.generate(
          8,
              (i) => Container(
            height: 46,
            margin: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 6),
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