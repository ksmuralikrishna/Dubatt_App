import 'package:dubatt_app/services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../widgets/common/app_shell.dart';
import '../../models/acid_testing_model.dart';
import '../../services/acid_testing_service.dart';

class AcidTestingFormScreen extends StatefulWidget {
  final String? recordId;
  final VoidCallback onLogout;

  const AcidTestingFormScreen({
    super.key,
    this.recordId,
    required this.onLogout,
  });

  bool get isCreate => recordId == null;

  @override
  State<AcidTestingFormScreen> createState() =>
      _AcidTestingFormScreenState();
}

class _AcidTestingFormScreenState extends State<AcidTestingFormScreen> {
  // ── Primary detail controllers ────────────────────────────────
  final _dateCtrl              = TextEditingController();
  final _avgPalletCtrl         = TextEditingController();
  final _foreignMaterialCtrl   = TextEditingController();
  final _avgPalletForeignCtrl  = TextEditingController();
  // Auto-filled (read-only)
  final _vehicleCtrl           = TextEditingController();
  final _supplierCtrl          = TextEditingController();
  final _inhouseWeightCtrl     = TextEditingController();

  // ── Lot dropdown ──────────────────────────────────────────────
  List<LotOption> _lots = [];
  LotOption? _selectedLot;

  // ── State ─────────────────────────────────────────────────────
  bool _isLoading    = true;
  bool _isSaving     = false;
  bool _isSubmitting = false;
  bool _isSubmitted  = false;
  Map<String, String> _fieldErrors = {};
  String? _currentId;

  // ── Pallet rows ───────────────────────────────────────────────
  final List<_PalletRow> _rows = [];

  // ── Result banner ──────────────────────────────────────────────
  double? _netAvgAcidPct;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _avgPalletCtrl.dispose();
    _foreignMaterialCtrl.dispose();
    _avgPalletForeignCtrl.dispose();
    _vehicleCtrl.dispose();
    _supplierCtrl.dispose();
    _inhouseWeightCtrl.dispose();
    for (final r in _rows) r.dispose();
    super.dispose();
  }

  // ── Init ───────────────────────────────────────────────────────
  Future<void> _init() async {
    setState(() => _isLoading = true);
    _lots = await AcidTestingService().getAvailableLots();

    if (widget.isCreate) {
      _dateCtrl.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _addRow();
    } else {
      await _loadRecord();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadRecord() async {
    final record = await AcidTestingService().getOne(widget.recordId!);
    if (record == null) {
      _showSnack('Failed to load record.', error: true);
      return;
    }

    _currentId    = record.id;
    _isSubmitted  = record.statusCode >= 1;
    _dateCtrl.text = record.testDate.length >= 10
        ? record.testDate.substring(0, 10)
        : record.testDate;

    // If lot is not in available-lots list (already used), add it manually
    if (!_lots.any((l) => l.lotNo == record.lotNumber)) {
      _lots.insert(0, LotOption(
        lotNo:         record.lotNumber,
        supplierName:  record.supplierName ?? '',
        supplierId:    record.supplierId,
        vehicleNumber: record.vehicleNumber,
        receivedQty:   record.receivedQty,
        invoiceQty:    record.invoiceQty,
      ));
    }
    _selectedLot = _lots.firstWhere((l) => l.lotNo == record.lotNumber);
    _autofillFromLot(_selectedLot!);

    _avgPalletCtrl.text =
        record.avgPalletWeight?.toStringAsFixed(2) ?? '';
    _foreignMaterialCtrl.text =
        record.foreignMaterialWeight?.toStringAsFixed(2) ?? '';
    _avgPalletForeignCtrl.text =
        record.avgPalletAndForeignWeight?.toStringAsFixed(3) ?? '';

    for (final d in record.details) {
      _addRow(detail: d);
    }
    if (_rows.isEmpty) _addRow();

    _recalcAll();
  }

  // ── Lot selection ──────────────────────────────────────────────
  void _autofillFromLot(LotOption lot) {
    _vehicleCtrl.text =
        lot.vehicleNumber ?? '';
    _supplierCtrl.text    = lot.supplierName;
    _inhouseWeightCtrl.text =
        lot.receivedQty?.toStringAsFixed(2) ?? '';
  }

  void _onLotChanged(LotOption? lot) {
    setState(() => _selectedLot = lot);
    if (lot != null) _autofillFromLot(lot);
    _recalcAll();
  }

  // ── Date picker ────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final initial =
        DateTime.tryParse(_dateCtrl.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.green,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AppColors.textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      _dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  // ── Pallet row management ──────────────────────────────────────
  void _addRow({AcidTestingDetail? detail}) {
    final row = _PalletRow(
      palletNo:     detail?.palletNo ?? '',
      ulabType:     detail?.ulabType ?? '1000024',
      grossWeight:  detail?.grossWeight.toStringAsFixed(3) ?? '',
      initialWeight: detail?.initialWeight?.toStringAsFixed(3) ?? '',
      drainedWeight: detail?.drainedWeight?.toStringAsFixed(3) ?? '',
      onChanged: () {
        _recalcAll();
        setState(() {});
      },
    );
    setState(() => _rows.add(row));
    _recalcAll();
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    _rows[index].dispose();
    setState(() => _rows.removeAt(index));
    _recalcAll();
  }

  // ── Calculations ───────────────────────────────────────────────
  void _recalcAll() {
    final avg     = double.tryParse(_avgPalletCtrl.text) ?? 0;
    final foreign = double.tryParse(_foreignMaterialCtrl.text) ?? 0;
    final pallets = _rows.isEmpty ? 1 : _rows.length;
    final avgPF   = avg + (foreign / pallets);

    _avgPalletForeignCtrl.text =
    avgPF > 0 ? avgPF.toStringAsFixed(3) : '';

    for (final row in _rows) {
      row.recalc(avgPF);
    }

    // Net Average Acid %
    double totalInit    = 0;
    double totalDrained = 0;
    for (final row in _rows) {
      if (row.isAcidPresent) {
        totalInit    += row.initialWeightVal;
        totalDrained += row.drainedWeightVal;
      }
    }
    setState(() {
      _netAvgAcidPct = totalInit > 0
          ? (totalDrained / totalInit) * 100
          : null;
    });
  }

  // ── Build payload ──────────────────────────────────────────────
  Map<String, dynamic>? _buildPayload() {
    if (_selectedLot == null) {
      _showSnack('Please select a Lot No.', error: true);
      return null;
    }
    if (_dateCtrl.text.isEmpty) {
      _showSnack('Please select a date.', error: true);
      return null;
    }

    final details = _rows.asMap().entries.map((e) {
      final i   = e.key;
      final row = e.value;
      return {
        'pallet_no':     row.palletNoCtrl.text.trim().isEmpty
            ? '${i + 1}'
            : row.palletNoCtrl.text.trim(),
        'ulab_type':     row.ulabType,
        'gross_weight':  double.tryParse(row.grossCtrl.text) ?? 0,
        'net_weight':    row.netWeightVal,
        'initial_weight': row.isAcidPresent
            ? double.tryParse(row.initialCtrl.text) ?? 0
            : null,
        'drained_weight': row.isAcidPresent
            ? double.tryParse(row.drainedCtrl.text) ?? 0
            : null,
        'remarks': row.ulabType,
      };
    }).toList();

    return {
      'test_date':                    _dateCtrl.text.trim(),
      'lot_number':                   _selectedLot!.lotNo,
      'supplier_id':                  _selectedLot!.supplierId,
      'supplier_name':                _selectedLot!.supplierName,
      'vehicle_number':               _vehicleCtrl.text.trim(),
      'avg_pallet_weight':
      double.tryParse(_avgPalletCtrl.text) ?? 0,
      'foreign_material_weight':
      double.tryParse(_foreignMaterialCtrl.text) ?? 0,
      'avg_pallet_and_foreign_weight':
      double.tryParse(_avgPalletForeignCtrl.text) ?? 0,
      'invoice_qty':   _selectedLot!.invoiceQty ?? 0,
      'received_qty':  _selectedLot!.receivedQty ?? 0,
      'details':       details,
    };
  }

  // ── Save ───────────────────────────────────────────────────────
  Future<void> _save() async {
    final payload = _buildPayload();
    if (payload == null) return;

    setState(() { _isSaving = true; _fieldErrors = {}; });

    final result = await AcidTestingService().save(
      payload,
      id: _currentId,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.success) {
      _showSnack('Record saved successfully.');
      if (widget.isCreate && result.newId != null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => AcidTestingFormScreen(
            recordId: result.newId,
            onLogout: widget.onLogout,
          ),
        ));
      }
    } else if (result.fieldErrors.isNotEmpty) {
      _fieldErrors = result.fieldErrors.map(
            (k, v) => MapEntry(k, (v is List ? v.first : v).toString()),
      );
      _showSnack(result.errorMsg ?? 'Please fix the errors.',
          error: true);
    } else {
      _showSnack(result.errorMsg ?? 'Save failed.', error: true);
    }
  }

  // ── Submit ─────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!ConnectivityService().isOnline) {
      _showSnack('You are offline. Please connect to submit.',
          error: true);
      return;
    }
    if (_currentId == null) {
      _showSnack('Save the record before submitting.', error: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: Text('Submit record?',
            style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark)),
        content: Text(
          'Once submitted, this record cannot be edited.',
          style: GoogleFonts.outfit(
              fontSize: 14, color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style:
                GoogleFonts.outfit(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Submit',
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    final error = await AcidTestingService().submit(_currentId!);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (error == null) {
      _showSnack('Record submitted successfully.');
      Navigator.of(context).pop();
    } else {
      _showSnack(error, error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          error ? Icons.error_outline : Icons.check_circle_outline,
          color: Colors.white, size: 16,
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

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.hPad(context);

    return AppShell(
      currentRoute: '/acid-testing',
      onLogout: widget.onLogout,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: _isLoading
            ? const Center(
            child: CircularProgressIndicator(
                color: AppColors.green))
            : SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 120),
          child: ConstrainedBox(
            constraints:
            const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Page header ────────────────────────
                MesPageHeader(
                  title: widget.isCreate
                      ? 'Create Acid Test'
                      : 'Edit Acid Test',
                  subtitle: widget.isCreate
                      ? 'Fill in the details'
                      : 'Lot: ${_selectedLot?.lotNo ?? ''}',
                  actions: [
                    if (_isSubmitted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius:
                          BorderRadius.circular(20),
                        ),
                        child: Text('● Submitted',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF065F46),
                            )),
                      ),
                    MesOutlineButton(
                      label: 'Back',
                      icon: Icons.arrow_back,
                      small: true,
                      onPressed: () =>
                          Navigator.of(context).pop(),
                    ),
                  ],
                ),

                // ── Offline banner ─────────────────────
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
                            size: 16,
                            color: Color(0xFFF59E0B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You are offline. Record will sync when connection restores.',
                            style: GoogleFonts.outfit(
                                fontSize: 13,
                                color:
                                const Color(0xFF92400E)),
                          ),
                        ),
                      ]),
                    );
                  },
                ),

                // ── Submitted notice ───────────────────
                if (_isSubmitted)
                  Container(
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
                      const Icon(Icons.lock_outline,
                          size: 16,
                          color: Color(0xFFF59E0B)),
                      const SizedBox(width: 8),
                      Text(
                        'This record has been submitted and is locked from editing.',
                        style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF92400E)),
                      ),
                    ]),
                  ),

                const SizedBox(height: 8),

                // ── Card 1: Primary details ────────────
                _buildPrimaryCard(),
                const SizedBox(height: 16),

                // ── Card 2: Pallet rows ────────────────
                _buildPalletCard(),
                const SizedBox(height: 16),

                // ── Result banner ──────────────────────
                _buildResultBanner(),
                const SizedBox(height: 24),

                // ── Action buttons ─────────────────────
                if (!_isSubmitted)
                  _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Primary details card ───────────────────────────────────────
  Widget _buildPrimaryCard() {
    return MesCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.calendar_today_outlined,
              'Primary Details'),
          const SizedBox(height: 16),
          // Row 1: Date + Lot
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 200,
                child: GestureDetector(
                  onTap: _isSubmitted ? null : _pickDate,
                  child: AbsorbPointer(
                    child: MesTextField(
                      label: 'Date',
                      controller: _dateCtrl,
                      readOnly: true,
                      prefixIcon: Icons.calendar_today_outlined,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 260,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lot No',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMid,
                          letterSpacing: 0.5,
                        )),
                    const SizedBox(height: 5),
                    DropdownButtonFormField<LotOption>(
                      value: _selectedLot,
                      isExpanded: true,
                      hint: Text('Select a lot…',
                          style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: AppColors.textMuted)),
                      items: _lots
                          .map((l) => DropdownMenuItem(
                        value: l,
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(l.lotNo,
                                style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight:
                                    FontWeight.w600)),
                            Text(
                              '${l.supplierName} · ${l.receivedQty?.toStringAsFixed(0) ?? '-'} KG',
                              style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ))
                          .toList(),
                      onChanged: _isSubmitted
                          ? null
                          : (v) {
                        _onLotChanged(v);
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.greenXLight,
                        contentPadding:
                        const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 11),
                        border: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(9)),
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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Row 2: Auto-filled fields
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _autoField('Vehicle', _vehicleCtrl,
                  Icons.local_shipping_outlined),
              _autoField('Supplier', _supplierCtrl,
                  Icons.person_outline),
              _autoField('In-House Weight (KG)',
                  _inhouseWeightCtrl, Icons.scale_outlined),
            ],
          ),
          const SizedBox(height: 16),
          // Row 3: User-input fields
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 220,
                child: MesTextField(
                  label: 'Avg Pallet Weight (KG)',
                  controller: _avgPalletCtrl,
                  prefixIcon: Icons.scale_outlined,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  onChanged: (_) => _recalcAll(),
                  readOnly: _isSubmitted,
                ),
              ),
              SizedBox(
                width: 220,
                child: MesTextField(
                  label: 'Foreign Material Weight (KG)',
                  controller: _foreignMaterialCtrl,
                  prefixIcon: Icons.filter_alt_outlined,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  onChanged: (_) => _recalcAll(),
                  readOnly: _isSubmitted,
                ),
              ),
              SizedBox(
                width: 220,
                child: MesTextField(
                  label: 'Avg Pallet & Foreign (KG)',
                  controller: _avgPalletForeignCtrl,
                  prefixIcon: Icons.calculate_outlined,
                  readOnly: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _autoField(
      String label, TextEditingController ctrl, IconData icon) {
    return SizedBox(
      width: 200,
      child: MesTextField(
        label: label,
        controller: ctrl,
        prefixIcon: icon,
        readOnly: true,
      ),
    );
  }

  // ── Pallet rows card ───────────────────────────────────────────
  Widget _buildPalletCard() {
    return MesCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: AppColors.greenLight,
              border: Border(
                  bottom: BorderSide(color: AppColors.border)),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(children: [
              const Icon(Icons.table_rows_outlined,
                  size: 16, color: AppColors.green),
              const SizedBox(width: 8),
              Text('PALLET WEIGHT RECORDS',
                  style: AppTextStyles.label(
                      color: AppColors.green)),
              const Spacer(),
              if (!_isSubmitted)
                MesOutlineButton(
                  label: 'Add Row',
                  icon: Icons.add,
                  small: true,
                  onPressed: () => _addRow(),
                ),
            ]),
          ),

          // Column headers
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildPalletTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildPalletTable() {
    const double cSr      = 40;
    const double cPallet  = 100;
    const double cUlab    = 200;
    const double cGross   = 110;
    const double cAvgPF   = 110;
    const double cNet     = 110;
    const double cInit    = 110;
    const double cDrained = 110;
    const double cDiff    = 100;
    const double cPct     = 90;
    const double cDel     = 44;
    const double totalW   = cSr + cPallet + cUlab + cGross +
        cAvgPF + cNet + cInit + cDrained + cDiff + cPct + cDel;

    Widget hdr(String label, double w,
        {bool right = false, bool center = false}) {
      return SizedBox(
        width: w,
        child: Padding(
          padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Text(label.toUpperCase(),
              textAlign: center
                  ? TextAlign.center
                  : right
                  ? TextAlign.right
                  : TextAlign.left,
              style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                  color: AppColors.green)),
        ),
      );
    }

    return SizedBox(
      width: totalW,
      child: Column(
        children: [
          // Header row
          Container(
            color: AppColors.greenLight,
            child: Row(children: [
              hdr('#',            cSr,     center: true),
              hdr('Pallet No',   cPallet),
              hdr('ULAB Type',   cUlab),
              hdr('Gross (KG)',  cGross,  right: true),
              hdr('Avg P&F',     cAvgPF,  right: true),
              hdr('Net (KG)',    cNet,    right: true),
              hdr('Initial',     cInit,   right: true),
              hdr('Drained',     cDrained, right: true),
              hdr('Wt Diff',     cDiff,   right: true),
              hdr('Acid %',      cPct,    right: true),
              hdr('',            cDel),
            ]),
          ),
          // Data rows
          ..._rows.asMap().entries.map((e) {
            final idx = e.key;
            final row = e.value;
            return _buildPalletRow(
              idx:        idx,
              row:        row,
              widths: (cSr, cPallet, cUlab, cGross, cAvgPF,
              cNet, cInit, cDrained, cDiff, cPct, cDel),
            );
          }),
          // Totals row
          _buildTotalsRow(totalW, cSr, cPallet, cUlab,
              cGross, cAvgPF, cNet, cInit, cDrained, cDiff, cPct, cDel),
        ],
      ),
    );
  }

  Widget _buildPalletRow({
    required int idx,
    required _PalletRow row,
    required (double, double, double, double, double, double,
        double, double, double, double, double) widths,
  }) {
    final (cSr, cPallet, cUlab, cGross, cAvgPF,
    cNet, cInit, cDrained, cDiff, cPct, cDel) = widths;

    Widget numCell(double w, TextEditingController ctrl,
        {bool enabled = true, bool isCalc = false}) {
      return SizedBox(
        width: w,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 6, vertical: 5),
          child: TextField(
            controller: ctrl,
            enabled: enabled && !_isSubmitted,
            readOnly: !enabled || isCalc,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  RegExp(r'[0-9.]'))
            ],
            textAlign: TextAlign.right,
            style: GoogleFonts.outfit(
              fontSize: 12.5,
              color: isCalc ? AppColors.green : AppColors.textDark,
              fontWeight: isCalc
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 7),
              filled: true,
              fillColor: isCalc
                  ? const Color(0xFFEEF6F1)
                  : !enabled
                  ? const Color(0xFFF3F4F6)
                  : AppColors.greenXLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                    color: isCalc
                        ? const Color(0xFFC8DFD1)
                        : AppColors.border,
                    width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                    color: isCalc
                        ? const Color(0xFFC8DFD1)
                        : AppColors.border,
                    width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(
                    color: AppColors.green, width: 1.5),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(
                    color: Color(0xFFE5E7EB), width: 1.5),
              ),
            ),
            onChanged: (_) => _recalcAll(),
          ),
        ),
      );
    }

    final isAcid = row.isAcidPresent;

    return Container(
      decoration: const BoxDecoration(
        border:
        Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(children: [
        // SR
        SizedBox(
          width: cSr,
          child: Center(
            child: Text('${idx + 1}',
                style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green)),
          ),
        ),
        // Pallet No
        SizedBox(
          width: cPallet,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 5),
            child: TextField(
              controller: row.palletNoCtrl,
              enabled: !_isSubmitted,
              style: GoogleFonts.outfit(
                  fontSize: 12.5, color: AppColors.textDark),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 7),
                filled: true,
                fillColor: AppColors.greenXLight,
                hintText: 'WP-${'${idx + 1}'.padLeft(2, '0')}',
                hintStyle: GoogleFonts.outfit(
                    fontSize: 12, color: AppColors.textMuted),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                        color: AppColors.border, width: 1.5)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                        color: AppColors.border, width: 1.5)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                        color: AppColors.green, width: 1.5)),
              ),
            ),
          ),
        ),
        // ULAB Type
        SizedBox(
          width: cUlab,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 5),
            child: DropdownButtonFormField<String>(
              value: row.ulabType,
              isDense: true,
              style: GoogleFonts.outfit(
                  fontSize: 12.5, color: AppColors.textDark),
              items: kUlabOptions
                  .map((u) => DropdownMenuItem(
                value: u.id,
                child: Text(u.name,
                    style: GoogleFonts.outfit(
                        fontSize: 12.5)),
              ))
                  .toList(),
              onChanged: _isSubmitted
                  ? null
                  : (v) {
                if (v != null) {
                  setState(() => row.ulabType = v);
                  _recalcAll();
                }
              },
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 7),
                filled: true,
                fillColor: AppColors.greenXLight,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                        color: AppColors.border, width: 1.5)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                        color: AppColors.border, width: 1.5)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                        color: AppColors.green, width: 1.5)),
              ),
            ),
          ),
        ),
        // Gross
        numCell(cGross, row.grossCtrl),
        // Avg P&F
        numCell(cAvgPF, row.avgPFCtrl, enabled: false, isCalc: true),
        // Net
        numCell(cNet,   row.netCtrl,   enabled: false, isCalc: true),
        // Initial — only if acid present
        numCell(cInit,   row.initialCtrl,
            enabled: isAcid),
        // Drained — only if acid present
        numCell(cDrained, row.drainedCtrl,
            enabled: isAcid),
        // Weight diff
        numCell(cDiff, row.diffCtrl,    enabled: false, isCalc: true),
        // Acid %
        numCell(cPct,  row.acidPctCtrl, enabled: false, isCalc: true),
        // Delete
        SizedBox(
          width: cDel,
          child: _rows.length > 1 && !_isSubmitted
              ? IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 16, color: AppColors.error),
            onPressed: () => _removeRow(idx),
            tooltip: 'Remove row',
          )
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Widget _buildTotalsRow(
      double totalW,
      double cSr, double cPallet, double cUlab,
      double cGross, double cAvgPF, double cNet,
      double cInit, double cDrained, double cDiff,
      double cPct, double cDel) {
    double tGross = 0, tNet = 0, tInit = 0, tDrained = 0;
    for (final r in _rows) {
      tGross   += r.grossWeightVal;
      tNet     += r.netWeightVal;
      tInit    += r.initialWeightVal;
      tDrained += r.drainedWeightVal;
    }

    Widget totalCell(double w, String value) {
      return SizedBox(
        width: w,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 10),
          child: Text(value,
              textAlign: TextAlign.right,
              style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green)),
        ),
      );
    }

    final fmt = NumberFormat('#,##0.000');

    return Container(
      color: AppColors.greenLight,
      child: Row(children: [
        SizedBox(
          width: cSr + cPallet + cUlab,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 10),
            child: Text('TOTAL (KG)',
                textAlign: TextAlign.right,
                style: GoogleFonts.outfit(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: AppColors.textMuted)),
          ),
        ),
        totalCell(cGross,   tGross > 0 ? fmt.format(tGross) : ''),
        SizedBox(width: cAvgPF),
        totalCell(cNet,     tNet > 0 ? fmt.format(tNet) : ''),
        totalCell(cInit,    tInit > 0 ? fmt.format(tInit) : ''),
        totalCell(cDrained, tDrained > 0 ? fmt.format(tDrained) : ''),
        SizedBox(width: cDiff + cPct + cDel),
      ]),
    );
  }

  // ── Result banner ──────────────────────────────────────────────
  Widget _buildResultBanner() {
    final pct = _netAvgAcidPct;

    Color borderColor = AppColors.border;
    Color bgColor     = AppColors.greenXLight;
    Color pillBg      = AppColors.greenLight;
    Color pillFg      = AppColors.green;
    String catLabel   = '—';
    String catRule    = '';

    if (pct != null) {
      if (pct > 30) {
        borderColor = const Color(0xFFF59E0B);
        bgColor     = const Color(0xFFFFFBEB);
        pillBg      = const Color(0xFFFEF3C7);
        pillFg      = const Color(0xFFB45309);
        catLabel    = 'High Acid';
        catRule     = 'Avg Acid % > 30%';
      } else if (pct >= 15) {
        borderColor = AppColors.green;
        bgColor     = const Color(0xFFE8F5ED);
        pillBg      = AppColors.greenLight;
        pillFg      = AppColors.greenDark;
        catLabel    = 'Normal';
        catRule     = '15% ≤ Avg Acid % ≤ 30%';
      } else if (pct >= 5) {
        borderColor = const Color(0xFF3B82F6);
        bgColor     = const Color(0xFFEFF6FF);
        pillBg      = const Color(0xFFDBEAFE);
        pillFg      = const Color(0xFF1D4ED8);
        catLabel    = 'Low Acid';
        catRule     = '5% ≤ Avg Acid % < 15%';
      } else {
        borderColor = const Color(0xFF9CA3AF);
        bgColor     = const Color(0xFFF3F4F6);
        pillBg      = const Color(0xFFE5E7EB);
        pillFg      = const Color(0xFF374151);
        catLabel    = 'Dry / Empty';
        catRule     = 'Avg Acid % < 5%';
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NET AVERAGE ACID %',
                  style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Text(
                pct != null
                    ? '${pct.toStringAsFixed(2)}%'
                    : '—',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 4),
              Text('= Total Drained ÷ Total Initial × 100',
                  style: GoogleFonts.outfit(
                      fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
          const Spacer(),
          if (pct != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: pillFg, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(catLabel,
                        style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: pillFg)),
                  ]),
                ),
                const SizedBox(height: 6),
                Text(catRule,
                    style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppColors.textMuted)),
              ],
            ),
        ],
      ),
    );
  }

  // ── Action buttons ─────────────────────────────────────────────
  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: MesButton(
            label: widget.isCreate ? 'Create Record' : 'Save',
            icon: Icons.save_outlined,
            isLoading: _isSaving,
            onPressed: _isSubmitting ? null : _save,
          ),
        ),
        if (!widget.isCreate) ...[
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white),
                )
                    : const Icon(Icons.check_circle_outline,
                    size: 18, color: Colors.white),
                label: Text(
                  _isSubmitting ? 'Submitting…' : 'Submit',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0891B2),
                  disabledBackgroundColor:
                  const Color(0xFF0891B2).withOpacity(0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _cardHeader(IconData icon, String title) {
    return Row(children: [
      Icon(icon, size: 16, color: AppColors.green),
      const SizedBox(width: 8),
      Text(title.toUpperCase(),
          style: AppTextStyles.label(color: AppColors.green)),
    ]);
  }
}

// ─────────────────────────────────────────────
// Pallet row state holder
// ─────────────────────────────────────────────
class _PalletRow {
  final TextEditingController palletNoCtrl;
  final TextEditingController grossCtrl;
  final TextEditingController avgPFCtrl;
  final TextEditingController netCtrl;
  final TextEditingController initialCtrl;
  final TextEditingController drainedCtrl;
  final TextEditingController diffCtrl;
  final TextEditingController acidPctCtrl;

  String ulabType;
  final VoidCallback onChanged;

  _PalletRow({
    String palletNo     = '',
    String ulabType     = '1000024',
    String grossWeight  = '',
    String initialWeight = '',
    String drainedWeight = '',
    required this.onChanged,
  })  : ulabType      = ulabType,
        palletNoCtrl  = TextEditingController(text: palletNo),
        grossCtrl     = TextEditingController(text: grossWeight),
        avgPFCtrl     = TextEditingController(),
        netCtrl       = TextEditingController(),
        initialCtrl   = TextEditingController(text: initialWeight),
        drainedCtrl   = TextEditingController(text: drainedWeight),
        diffCtrl      = TextEditingController(),
        acidPctCtrl   = TextEditingController();

  bool get isAcidPresent => ulabType == '5';

  double get grossWeightVal =>
      double.tryParse(grossCtrl.text) ?? 0;
  double get netWeightVal =>
      double.tryParse(netCtrl.text) ?? 0;
  double get initialWeightVal =>
      isAcidPresent ? (double.tryParse(initialCtrl.text) ?? 0) : 0;
  double get drainedWeightVal =>
      isAcidPresent ? (double.tryParse(drainedCtrl.text) ?? 0) : 0;

  void recalc(double avgPF) {
    final gross = grossWeightVal;
    final net   = gross > 0 ? (gross - avgPF).clamp(0.0, double.maxFinite) : 0.0;

    avgPFCtrl.text = avgPF > 0 ? avgPF.toStringAsFixed(3) : '';
    netCtrl.text   = gross > 0 ? net.toStringAsFixed(3) : '';

    if (isAcidPresent) {
      final init    = double.tryParse(initialCtrl.text) ?? 0;
      final drained = double.tryParse(drainedCtrl.text) ?? 0;
      final diff    = init > 0
          ? (init - drained).clamp(0.0, double.maxFinite)
          : 0.0;
      final pct     = init > 0 ? (drained / init) * 100 : 0.0;
      diffCtrl.text    = init > 0 ? diff.toStringAsFixed(3) : '';
      acidPctCtrl.text = init > 0 ? pct.toStringAsFixed(2) : '';
    } else {
      initialCtrl.text = '';
      drainedCtrl.text = '';
      diffCtrl.text    = '';
      acidPctCtrl.text = '';
    }
  }

  void dispose() {
    palletNoCtrl.dispose();
    grossCtrl.dispose();
    avgPFCtrl.dispose();
    netCtrl.dispose();
    initialCtrl.dispose();
    drainedCtrl.dispose();
    diffCtrl.dispose();
    acidPctCtrl.dispose();
  }
}