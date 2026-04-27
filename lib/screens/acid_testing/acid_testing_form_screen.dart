// ─────────────────────────────────────────────────────────────────────────────
// acid_testing_form_screen.dart
// Form screen for Acid Testing module.
//
// FIXES APPLIED (tablet alignment):
//   1. Shared _PalletCols abstract class — single source of truth for widths
//   2. _PalletTable uses fixed SizedBox(width: _PalletCols.total) instead of
//      ConstrainedBox(minWidth: double.infinity) which broke in scroll views
//   3. _th() padding changed from symmetric(10,10) to fromLTRB(15,10,15,10)
//      to match cell padding(5) + TextField contentPadding(10) = 15 offset
//   4. Footer spacer for avgPF is now _totalCell('', ...) not bare SizedBox
//   5. _PalletRow wraps its Row in IntrinsicHeight + CrossAxisAlignment.stretch
//      so dropdown and textfield rows are always the same height
//   6. _tableInput wraps TextField in SizedBox(width: double.infinity) so
//      the input always fills its parent SizedBox cell correctly
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// FIX #1 — Single source of truth for all column widths.
// Both _PalletTable and _PalletRow reference this class,
// so they can never drift out of sync.
// ─────────────────────────────────────────────────────────────────────────────
abstract class _PalletCols {
  static const double sr      = 40;
  static const double pallet  = 110;
  static const double ulab    = 200;
  static const double gross   = 120;
  static const double avgPF   = 120;
  static const double net     = 120;
  static const double initial = 110;
  static const double drained = 110;
  static const double diff    = 100;
  static const double pct     = 90;
  static const double del     = 44;

  static const double total =
      sr + pallet + ulab + gross + avgPF + net +
          initial + drained + diff + pct + del; // = 1164
}

class AcidTestingFormScreen extends StatefulWidget {
  final String? recordId;
  final VoidCallback onLogout;
  final bool embedInShell;

  const AcidTestingFormScreen({
    super.key,
    this.recordId,
    this.embedInShell = true,
    required this.onLogout,
  });

  bool get isCreate => recordId == null;

  @override
  State<AcidTestingFormScreen> createState() =>
      _AcidTestingFormScreenState();
}

class _AcidTestingFormScreenState
    extends State<AcidTestingFormScreen> {
  // ── Header controllers ───────────────────────────────────────────
  final _dateCtrl            = TextEditingController();
  final _vehicleCtrl         = TextEditingController();
  final _supplierCtrl        = TextEditingController();
  final _inhouseCtrl         = TextEditingController();
  final _avgPalletCtrl       = TextEditingController();
  final _foreignCtrl         = TextEditingController();
  final _avgPalletForeignCtrl = TextEditingController();

  // ── Lot dropdown state ───────────────────────────────────────────
  List<LotOption> _lots         = [];
  LotOption? _selectedLot;
  String? _lotSearchQuery;
  String? _supplierId;
  String? _invoiceQty;

  // ── Pallet row state ─────────────────────────────────────────────
  final List<_PalletRowData> _rows = [];

  // ── UI state ─────────────────────────────────────────────────────
  bool _isLoading    = true;
  bool _isSaving     = false;
  bool _isSubmitting = false;
  bool _isSubmitted  = false;
  String? _currentId;
  String? _initError;

  // ── Totals ───────────────────────────────────────────────────────
  double _totalGross   = 0;
  double _totalNet     = 0;
  double _totalInitial = 0;
  double _totalDrained = 0;
  double? _netAvgAcidPct;

  @override
  void initState() {
    super.initState();
    print('✅ AcidTestingFormScreen initState called');
    print('📝 widget.isCreate: ${widget.isCreate}');
    print('📝 widget.recordId: ${widget.recordId}');
    _init();
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _vehicleCtrl.dispose();
    _supplierCtrl.dispose();
    _inhouseCtrl.dispose();
    _avgPalletCtrl.dispose();
    _foreignCtrl.dispose();
    _avgPalletForeignCtrl.dispose();
    for (final r in _rows) r.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    print('🔄 _init() started');
    if (mounted) {
      setState(() {
        _isLoading = true;
        _initError = null;
      });
    }

    try {
      try {
        _lots = await AcidTestingService().getAvailableLots();
        print('✅ getAvailableLots() returned ${_lots.length} lots');
      } catch (e, stacktrace) {
        print('❌ Error in getAvailableLots: $e');
        print('📚 Stacktrace: $stacktrace');
        _lots = [];
        _initError = 'Failed to load available lots. Please check network/API and try again.';
      }

      if (widget.isCreate) {
        _dateCtrl.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
        _addRow();
      } else {
        try {
          await _loadRecord();
        } catch (e, stacktrace) {
          print('❌ Error in _loadRecord: $e');
          print('📚 Stacktrace: $stacktrace');
          _initError ??= 'Failed to load record. Please try again.';
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      } else {
        _isLoading = false;
      }
    }
  }

  Future<void> _loadRecord() async {
    final record =
    await AcidTestingService().getOne(widget.recordId!);
    if (record == null) {
      _showSnack('Failed to load record.', error: true);
      return;
    }

    _currentId = record.id;
    _isSubmitted = record.isSubmitted;

    _dateCtrl.text      = record.testDate.length >= 10
        ? record.testDate.substring(0, 10)
        : record.testDate;
    _vehicleCtrl.text   = record.vehicleNumber ?? '';
    _supplierCtrl.text  = record.supplierName ?? '';
    _inhouseCtrl.text   = record.receivedQty?.toString() ?? '';
    _avgPalletCtrl.text = record.avgPalletWeight.toString();
    _foreignCtrl.text   = record.foreignMaterialWeight.toString();
    _avgPalletForeignCtrl.text =
        record.avgPalletAndForeignWeight.toString();
    _supplierId = record.supplierId;
    _invoiceQty = record.invoiceQty?.toString();

    final existingLot = _lots.firstWhere(
          (l) => l.lotNo == record.lotNumber,
      orElse: () => LotOption(
        lotNo:         record.lotNumber,
        supplierName:  record.supplierName ?? '',
        supplierId:    record.supplierId,
        vehicleNumber: record.vehicleNumber,
        receivedQty:   record.receivedQty,
        invoiceQty:    record.invoiceQty,
      ),
    );
    if (!_lots.any((l) => l.lotNo == record.lotNumber)) {
      _lots.insert(0, existingLot);
    }
    _selectedLot = existingLot;

    if (record.details.isNotEmpty) {
      for (final detail in record.details) {
        _addRow(data: detail);
      }
    } else {
      _addRow();
    }

    _recalcAvgPalletForeign();
  }

  // ── Date picker ───────────────────────────────────────────────────
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
      _dateCtrl.text =
          DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  // ── Lot selection ─────────────────────────────────────────────────
  void _onLotSelected(LotOption? lot) {
    setState(() {
      _selectedLot = lot;
      if (lot == null) {
        _vehicleCtrl.text  = '';
        _supplierCtrl.text = '';
        _inhouseCtrl.text  = '';
        _supplierId = null;
        _invoiceQty = null;
      } else {
        _vehicleCtrl.text  = lot.vehicleNumber ?? '';
        _supplierCtrl.text = lot.supplierName;
        _inhouseCtrl.text  = lot.receivedQty?.toString() ?? '';
        _supplierId = lot.supplierId;
        _invoiceQty = lot.invoiceQty?.toString();
      }
    });
    _recalcAvgPalletForeign();
  }

  // ── Avg Pallet & Foreign calculation ─────────────────────────────
  void _recalcAvgPalletForeign() {
    final avg     = double.tryParse(_avgPalletCtrl.text) ?? 0;
    final foreign = double.tryParse(_foreignCtrl.text) ?? 0;
    final pallets = _rows.isNotEmpty ? _rows.length : 1;
    final result  = avg + (foreign / pallets);
    _avgPalletForeignCtrl.text =
    result > 0 ? result.toStringAsFixed(3) : '';
    for (final r in _rows) _calcRow(r);
    _recalcTotals();
  }

  // ── Per-row calculation ───────────────────────────────────────────
  void _calcRow(_PalletRowData row) {
    final avgPF   = double.tryParse(_avgPalletForeignCtrl.text) ?? 0;
    final gross   = double.tryParse(row.grossCtrl.text) ?? 0;
    final net     = gross > 0 ? (gross - avgPF).clamp(0, double.infinity) : 0;
    row.netCtrl.text   = gross > 0 ? net.toStringAsFixed(3) : '';
    row.avgPFCtrl.text = avgPF.toStringAsFixed(3);

    if (row.isAcidPresent) {
      final init    = double.tryParse(row.initialCtrl.text) ?? 0;
      final drained = double.tryParse(row.drainedCtrl.text) ?? 0;
      final diff    = init > 0 ? (init - drained).clamp(0, double.infinity) : 0;
      final pct     = init > 0 ? (diff / init) * 100 : 0;
      row.diffCtrl.text    = init > 0 ? diff.toStringAsFixed(3) : '';
      row.acidPctCtrl.text = init > 0 ? pct.toStringAsFixed(2) : '';
    } else {
      row.diffCtrl.text    = '';
      row.acidPctCtrl.text = '';
    }
  }

  // ── Totals recalc ─────────────────────────────────────────────────
  void _recalcTotals() {
    double tGross = 0, tNet = 0, tInit = 0, tDrained = 0;
    for (final r in _rows) {
      tGross   += double.tryParse(r.grossCtrl.text) ?? 0;
      tNet     += double.tryParse(r.netCtrl.text) ?? 0;
      tInit    += double.tryParse(r.initialCtrl.text) ?? 0;
      tDrained += double.tryParse(r.drainedCtrl.text) ?? 0;
    }
    final pct = tInit > 0 ? ((tInit - tDrained) / tInit) * 100 : null;
    setState(() {
      _totalGross    = tGross;
      _totalNet      = tNet;
      _totalInitial  = tInit;
      _totalDrained  = tDrained;
      _netAvgAcidPct = pct;
    });
  }

  // ── Row management ────────────────────────────────────────────────
  void _addRow({AcidTestingDetail? data}) {
    final avgPFVal = double.tryParse(_avgPalletForeignCtrl.text) ?? 0;
    final row = _PalletRowData(
      palletNo: data?.palletNo ?? '',
      ulabType: data?.ulabType ?? 1000024,
      avgPFVal: avgPFVal,
    );
    if (data != null) {
      row.grossCtrl.text   =
      data.grossWeight > 0 ? data.grossWeight.toString() : '';
      row.initialCtrl.text = data.initialWeight?.toString() ?? '';
      row.drainedCtrl.text = data.drainedWeight?.toString() ?? '';
    }
    _rows.add(row);
    _calcRow(row);
    _recalcTotals();
    if (!_isLoading) setState(() {});
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
    _recalcAvgPalletForeign();
  }

  void _onUlabChanged(_PalletRowData row) {
    if (!row.isAcidPresent) {
      row.initialCtrl.text  = '';
      row.drainedCtrl.text  = '';
      row.diffCtrl.text     = '';
      row.acidPctCtrl.text  = '';
    }
    _calcRow(row);
    _recalcTotals();
    setState(() {});
  }

  // ── Build payload ─────────────────────────────────────────────────
  Map<String, dynamic>? _buildPayload() {
    if (_selectedLot == null) {
      _showSnack('Please select a Lot No before saving.', error: true);
      return null;
    }


    final details = <Map<String, dynamic>>[];
    final errs    = <String>[];

    for (int i = 0; i < _rows.length; i++) {
      final r     = _rows[i];
      final pNo   = r.palletNoCtrl.text.trim();
      final gross = double.tryParse(r.grossCtrl.text) ?? 0;
      final net   = double.tryParse(r.netCtrl.text) ?? 0;

      if (pNo.isEmpty) errs.add('Row ${i + 1}: Pallet No required.');
      if (gross <= 0) errs.add('Row ${i + 1}: Gross Weight must be > 0.');

      details.add({
        'pallet_no':      pNo.isEmpty ? '${i + 1}' : pNo,
        'ulab_type':      r.ulabType.toString(),
        'gross_weight':   gross,
        'net_weight':     net,
        'initial_weight': r.isAcidPresent
            ? (double.tryParse(r.initialCtrl.text) ?? 0)
            : null,
        'drained_weight': r.isAcidPresent
            ? (double.tryParse(r.drainedCtrl.text) ?? 0)
            : null,
        'remarks': r.ulabType.toString(),
      });
    }

    // ── Top-level required fields ──────────────────────────────────
    final avgPallet = double.tryParse(_avgPalletCtrl.text);
    final foreignMaterial = double.tryParse(_foreignCtrl.text);

    if (avgPallet == null || avgPallet <= 0) {
      errs.add('Avg Pallet Weight is required and must be > 0.');
    }
    if (foreignMaterial == null || foreignMaterial < 0) {
      errs.add('Foreign Material Weight is required.');
    }

    if (errs.isNotEmpty) {
      _showSnack(errs.first, error: true);
      return null;
    }

    return {
      'test_date':                    _dateCtrl.text.trim(),
      'lot_number':                   _selectedLot!.lotNo,
      'supplier_id':                  _supplierId,
      'vehicle_number':               _vehicleCtrl.text.trim(),
      'avg_pallet_weight':            avgPallet!,
      'foreign_material_weight':      foreignMaterial!,
      'avg_pallet_and_foreign_weight':
      double.tryParse(_avgPalletForeignCtrl.text) ?? 0,
      'received_qty':
      double.tryParse(_inhouseCtrl.text) ?? 0,
      'invoice_qty':
      double.tryParse(_invoiceQty ?? '0') ?? 0,
      'details': details,
    };
  }

  // ── Save ──────────────────────────────────────────────────────────
  Future<void> _save() async {
    final payload = _buildPayload();
    if (payload == null) return;

    setState(() => _isSaving = true);

    final result = await AcidTestingService().save(
      payload,
      id:           _currentId,
      supplierName: _supplierCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.success) {
      _showSnack('Record saved successfully.');
      if (widget.isCreate && result.newId != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AcidTestingFormScreen(
              recordId: result.newId,
              onLogout: widget.onLogout,
            ),
          ),
        );
      }
    } else {
      _showSnack(result.errorMsg ?? 'Save failed.', error: true);
    }
  }

  // ── Submit ────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!ConnectivityService().isOnline) {
      _showSnack('You are offline. Please connect to submit.', error: true);
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
        title: Text(
          'Submit record?',
          style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark),
        ),
        content: Text(
          'Once submitted, this record cannot be edited.',
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
              backgroundColor: AppColors.green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Submit',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w600)),
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
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      backgroundColor: error ? AppColors.error : AppColors.green,
      behavior: SnackBarBehavior.floating,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  // ─────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.hPad(context);

    final content = Scaffold(
      backgroundColor: AppColors.bg,
        body: _isLoading
            ? const Center(
            child: CircularProgressIndicator(color: AppColors.green))
            : _initError != null
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: MesCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text('Unable to open Acid Testing',
                        style: AppTextStyles.subheading()),
                    const SizedBox(height: 8),
                    Text(_initError!,
                        style: AppTextStyles.body()),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        MesOutlineButton(
                          label: 'Back',
                          icon: Icons.arrow_back,
                          onPressed: () =>
                              Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 10),
                        MesButton(
                          label: 'Retry',
                          icon: Icons.refresh,
                          onPressed: _init,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
            : SingleChildScrollView(
          padding:
          EdgeInsets.fromLTRB(hPad, 28, hPad, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Page header ──────────────────────────
              MesPageHeader(
                title: _isSubmitted
                    ? 'Acid Test Record'
                    : (widget.isCreate
                    ? 'Create Acid Test'
                    : 'Edit Acid Test'),
                subtitle: _isSubmitted
                    ? 'This record has been submitted and cannot be edited'
                    : (widget.isCreate
                    ? 'Record new acid testing log'
                    : 'Lot: ${_selectedLot?.lotNo ?? ''}'),
                actions: [
                  MesOutlineButton(
                    label: 'Back',
                    icon: Icons.arrow_back,
                    small: true,
                    onPressed: () =>
                        Navigator.of(context).pop(),
                  ),
                ],
              ),

              // ── Offline banner ───────────────────────
              StreamBuilder<bool>(
                stream: ConnectivityService().onlineStream,
                initialData: ConnectivityService().isOnline,
                builder: (_, snap) {
                  if (snap.data ?? true) {
                    return const SizedBox.shrink();
                  }
                  return Container(
                    margin:
                    const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius:
                      BorderRadius.circular(9),
                      border: Border.all(
                          color: const Color(0xFFF59E0B)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_off,
                            size: 16,
                            color: Color(0xFFF59E0B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You are offline. Record will sync when connection restores.',
                            style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: const Color(
                                    0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 8),

              // ════════════════════════════════════════
              // CARD 1 — Primary Details
              // ════════════════════════════════════════
              _SectionCard(
                icon: Icons.calendar_today_outlined,
                title: 'Primary Details',
                child: Column(
                  children: [
                    // Row 1: Date | Lot No
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _isSubmitted
                                ? null
                                : _pickDate,
                            child: AbsorbPointer(
                              absorbing: _isSubmitted,
                              child: MesTextField(
                                label: 'Date *',
                                controller: _dateCtrl,
                                readOnly: true,
                                prefixIcon: Icons
                                    .calendar_today_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('LOT NO *', style: AppTextStyles.label()),
                              const SizedBox(height: 5),
                              SearchableDropdown<LotOption>(
                                value: _selectedLot,
                                items: _lots,
                                displayString: (lot) => lot.lotNo,
                                hint: 'Select a lot…',
                                enabled: !_isSubmitted,
                                onChanged: (lot) => _onLotSelected(lot),
                              ),
                              if (_selectedLot != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${_selectedLot!.supplierName}'
                                      '${_selectedLot!.receivedQty != null ? ' · ${_selectedLot!.receivedQty!.toStringAsFixed(0)} KG' : ''}',
                                  style: AppTextStyles.caption(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row 2: Vehicle | Supplier
                    Row(
                      children: [
                        Expanded(
                          child: MesTextField(
                            label: 'Vehicle',
                            controller: _vehicleCtrl,
                            readOnly: true,
                            prefixIcon:
                            Icons.local_shipping_outlined,
                            badge: 'AUTO',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: MesTextField(
                            label: 'Supplier',
                            controller: _supplierCtrl,
                            readOnly: true,
                            prefixIcon: Icons.person_outline,
                            badge: 'AUTO',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row 3: Avg Pallet Wt | In-House Wt
                    Row(
                      children: [
                        Expanded(
                          child: MesTextField(
                            label: 'Avg Pallet Weight (KG) *',
                            controller: _avgPalletCtrl,
                            readOnly: _isSubmitted,
                            keyboardType:
                            const TextInputType
                                .numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter
                                  .allow(RegExp(r'[0-9.]')),
                            ],
                            onChanged: (_) {
                              _recalcAvgPalletForeign();
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: MesTextField(
                            label:
                            'In-House Weigh Bridge (KG)',
                            controller: _inhouseCtrl,
                            readOnly: true,
                            prefixIcon: Icons.scale_outlined,
                            badge: 'AUTO',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row 4: Foreign Material Wt | Avg P&F (calc)
                    Row(
                      children: [
                        Expanded(
                          child: MesTextField(
                            label:
                            'Foreign Material Weight (KG) *',
                            controller: _foreignCtrl,
                            readOnly: _isSubmitted,
                            keyboardType:
                            const TextInputType
                                .numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter
                                  .allow(RegExp(r'[0-9.]')),
                            ],
                            onChanged: (_) {
                              _recalcAvgPalletForeign();
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              MesTextField(
                                label:
                                'Avg Pallet & Foreign (KG)',
                                controller:
                                _avgPalletForeignCtrl,
                                readOnly: true,
                                badge: 'CALC',
                                badgeColor: AppColors.green,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '= (Avg × Pallets + Foreign) ÷ Pallets',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ════════════════════════════════════════
              // CARD 2 — Pallet Weight Records
              // ════════════════════════════════════════
              MesCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [

                    // Card header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        color: AppColors.greenLight,
                        border: Border(
                            bottom: BorderSide(
                                color: AppColors.border)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                              Icons.inventory_2_outlined,
                              size: 16,
                              color: AppColors.green),
                          const SizedBox(width: 8),
                          Text(
                            'PALLET WEIGHT RECORDS',
                            style: AppTextStyles.label(
                                color: AppColors.green),
                          ),
                          const Spacer(),
                          if (!_isSubmitted)
                            _AddRowButton(
                              onTap: () {
                                _addRow();
                                _recalcAvgPalletForeign();
                              },
                            ),
                        ],
                      ),
                    ),

                    // Pallet table
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _PalletTable(
                        rows:        _rows,
                        isSubmitted: _isSubmitted,
                        onCalcRow: (row) {
                          _calcRow(row);
                          _recalcTotals();
                          setState(() {});
                        },
                        onUlabChanged: _onUlabChanged,
                        onRemove:      _removeRow,
                        totalGross:    _totalGross,
                        totalNet:      _totalNet,
                        totalInitial:  _totalInitial,
                        totalDrained:  _totalDrained,
                      ),
                    ),

                    // Category rules legend
                    _CategoryRules(),

                    // Net Avg Acid % result banner
                    _ResultBanner(pct: _netAvgAcidPct),

                    const SizedBox(height: 20),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Action buttons ───────────────────────
              if (_isSubmitted)
                const SizedBox.shrink()
              else if (!widget.isCreate)
                Row(
                  children: [
                    Expanded(
                      child: MesButton(
                        label: 'Save',
                        icon: Icons.save_outlined,
                        isLoading: _isSaving,
                        onPressed:
                        _isSubmitting ? null : _save,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SubmitButton(
                        isLoading: _isSubmitting,
                        onPressed:
                        _isSaving ? null : _submit,
                      ),
                    ),
                  ],
                )
              else
                MesButton(
                  label: 'Create Record',
                  icon: Icons.save_outlined,
                  isLoading: _isSaving,
                  onPressed: _save,
                ),
            ],
          ),
        ),
      );

    if (!widget.embedInShell) return content;
    return AppShell(
      currentRoute: '/acid-testing',
      onLogout: widget.onLogout,
      child: content,
    );
  }
}

// ─────────────────────────────────────────────
// Section card with green header
// ─────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return MesCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.greenLight,
              border: Border(
                  bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.green),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: AppTextStyles.label(color: AppColors.green),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Lot searchable dropdown
// ─────────────────────────────────────────────
class _LotDropdown extends StatefulWidget {
  final List<LotOption> lots;
  final LotOption? selected;
  final bool readOnly;
  final ValueChanged<LotOption?> onSelected;
  final String? searchQuery;
  final ValueChanged<String> onSearch;

  const _LotDropdown({
    required this.lots,
    required this.selected,
    required this.readOnly,
    required this.onSelected,
    required this.onSearch,
    this.searchQuery,
  });

  @override
  State<_LotDropdown> createState() => _LotDropdownState();
}

class _LotDropdownState extends State<_LotDropdown> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openSheet() {
    if (widget.readOnly) return;
    _searchCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LotPickerSheet(
        lots:       widget.lots,
        selected:   widget.selected,
        onSelected: (lot) {
          Navigator.of(ctx).pop();
          widget.onSelected(lot);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label  = widget.selected?.lotNo ?? '';
    final hasSel = widget.selected != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LOT NO *', style: AppTextStyles.label()),
        const SizedBox(height: 5),
        GestureDetector(
          onTap: _openSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: widget.readOnly
                  ? AppColors.greenLight
                  : AppColors.greenXLight,
              border: Border.all(
                color: hasSel ? AppColors.green : AppColors.border,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: 16,
                  color: hasSel
                      ? AppColors.green
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasSel ? label : 'Select a lot…',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: hasSel
                          ? AppColors.textDark
                          : AppColors.textMuted,
                      fontWeight: hasSel
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasSel && !widget.readOnly)
                  GestureDetector(
                    onTap: () => widget.onSelected(null),
                    child: const Icon(Icons.close,
                        size: 16, color: AppColors.textMuted),
                  )
                else
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: widget.readOnly
                        ? AppColors.textMuted
                        : AppColors.green,
                  ),
              ],
            ),
          ),
        ),
        if (widget.selected != null) ...[
          const SizedBox(height: 4),
          Text(
            '${widget.selected!.supplierName}'
                '${widget.selected!.receivedQty != null ? ' · ${widget.selected!.receivedQty!.toStringAsFixed(0)} KG' : ''}',
            style: AppTextStyles.caption(),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Lot picker bottom sheet
// ─────────────────────────────────────────────
class _LotPickerSheet extends StatefulWidget {
  final List<LotOption> lots;
  final LotOption? selected;
  final ValueChanged<LotOption> onSelected;

  const _LotPickerSheet({
    required this.lots,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_LotPickerSheet> createState() => _LotPickerSheetState();
}

class _LotPickerSheetState extends State<_LotPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<LotOption> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.lots;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.lots;
      } else {
        final lower = q.toLowerCase();
        _filtered = widget.lots.where((l) {
          return l.lotNo.toLowerCase().contains(lower) ||
              l.supplierName.toLowerCase().contains(lower);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding:
                const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Text('Select Lot',
                        style: AppTextStyles.subheading()),
                    const Spacer(),
                    Text('${_filtered.length} available',
                        style: AppTextStyles.caption()),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearch,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search lots…',
                    prefixIcon: const Icon(Icons.search,
                        size: 18, color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.greenXLight,
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                  child: Text('No lots available',
                      style: AppTextStyles.caption()),
                )
                    : ListView.separated(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) =>
                  const Divider(
                      color: AppColors.borderLight,
                      height: 1),
                  itemBuilder: (_, i) {
                    final lot = _filtered[i];
                    final isSelected =
                        widget.selected?.lotNo == lot.lotNo;
                    return ListTile(
                      contentPadding:
                      const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      selected: isSelected,
                      selectedTileColor: AppColors.greenLight,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(8)),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.green
                              : AppColors.greenLight,
                          borderRadius:
                          BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.layers_outlined,
                          size: 16,
                          color: isSelected
                              ? Colors.white
                              : AppColors.green,
                        ),
                      ),
                      title: Text(
                        lot.lotNo,
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      subtitle: Text(
                        '${lot.supplierName}'
                            '${lot.receiptDate != null ? ' · ${lot.receiptDate}' : ''}'
                            '${lot.receivedQty != null ? ' · ${lot.receivedQty!.toStringAsFixed(0)} KG' : ''}',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle,
                          color: AppColors.green, size: 18)
                          : null,
                      onTap: () => widget.onSelected(lot),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Add row button
// ─────────────────────────────────────────────
class _AddRowButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddRowButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text('Add Row',
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Pallet row data holder (controllers)
// ─────────────────────────────────────────────
class _PalletRowData {
  final TextEditingController palletNoCtrl;
  final TextEditingController grossCtrl;
  final TextEditingController avgPFCtrl;
  final TextEditingController netCtrl;
  final TextEditingController initialCtrl;
  final TextEditingController drainedCtrl;
  final TextEditingController diffCtrl;
  final TextEditingController acidPctCtrl;

  int _ulabType;
  int get ulabType => _ulabType;
  set ulabType(int v) => _ulabType = v;

  bool get isAcidPresent => _ulabType == 5;

  _PalletRowData({
    required String palletNo,
    required int ulabType,
    required double avgPFVal,
  })  : palletNoCtrl = TextEditingController(text: palletNo),
        grossCtrl    = TextEditingController(),
        avgPFCtrl    = TextEditingController(
            text: avgPFVal.toStringAsFixed(3)),
        netCtrl      = TextEditingController(),
        initialCtrl  = TextEditingController(),
        drainedCtrl  = TextEditingController(),
        diffCtrl     = TextEditingController(),
        acidPctCtrl  = TextEditingController(),
        _ulabType    = ulabType;

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

// ─────────────────────────────────────────────
// Pallet table widget
//
// FIX #2: Uses SizedBox(width: _PalletCols.total) instead of
//   ConstrainedBox(minWidth: double.infinity) — the latter breaks
//   layout inside a horizontal SingleChildScrollView on tablet.
// ─────────────────────────────────────────────
class _PalletTable extends StatelessWidget {
  final List<_PalletRowData> rows;
  final bool isSubmitted;
  final ValueChanged<_PalletRowData> onCalcRow;
  final ValueChanged<_PalletRowData> onUlabChanged;
  final ValueChanged<int> onRemove;
  final double totalGross, totalNet, totalInitial, totalDrained;

  const _PalletTable({
    required this.rows,
    required this.isSubmitted,
    required this.onCalcRow,
    required this.onUlabChanged,
    required this.onRemove,
    required this.totalGross,
    required this.totalNet,
    required this.totalInitial,
    required this.totalDrained,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.000');

    // FIX #2 — explicit total width so the table never collapses or
    // overflows unpredictably inside the horizontal scroll view.
    return SizedBox(
      width: _PalletCols.total,
      child: Column(
        children: [

          // ── Header ──────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: AppColors.greenLight,
              border: Border(
                  bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                // FIX #3 — padding changed to fromLTRB(15,10,15,10) so the
                // header label aligns with the text inside each cell.
                // Cell layout: SizedBox > Padding(all:5) > TextField(contentPadding h:10)
                // = 5 + 10 = 15 horizontal offset → header must match.
                _th('#',            _PalletCols.sr,      center: true),
                _th('Pallet No',    _PalletCols.pallet),
                _th('ULAB Type',    _PalletCols.ulab),
                _th('Gross (KG)',   _PalletCols.gross,   right: true),
                _th('Avg P&F',      _PalletCols.avgPF,   right: true),
                _th('Net (KG)',     _PalletCols.net,     right: true),
                _th('Initial (KG)', _PalletCols.initial, right: true),
                _th('Drained (KG)', _PalletCols.drained, right: true),
                _th('Diff (KG)',    _PalletCols.diff,    right: true),
                _th('Acid %',       _PalletCols.pct,     right: true),
                SizedBox(width: _PalletCols.del),
              ],
            ),
          ),

          // ── Rows ────────────────────────────────────────────────
          ...rows.asMap().entries.map((e) => _PalletRow(
            index:        e.key,
            row:          e.value,
            isSubmitted:  isSubmitted,
            canDelete:    rows.length > 1 && !isSubmitted,
            onCalcRow:    onCalcRow,
            onUlabChanged: onUlabChanged,
            onRemove:     onRemove,
          )),

          // ── Footer totals ────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: AppColors.greenLight,
              border: Border(
                  top: BorderSide(
                      color: AppColors.border, width: 2)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: _PalletCols.sr +
                      _PalletCols.pallet +
                      _PalletCols.ulab,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Text('TOTAL (KG)',
                        style: AppTextStyles.label(
                            color: AppColors.green)),
                  ),
                ),
                _totalCell(
                  totalGross > 0 ? fmt.format(totalGross) : '',
                  _PalletCols.gross,
                ),
                // FIX #4 — use _totalCell with empty string instead of a bare
                // SizedBox so the avgPF column spacer has consistent width and
                // doesn't push subsequent cells out of alignment on tablet.
                _totalCell('', _PalletCols.avgPF),
                _totalCell(
                  totalNet > 0 ? fmt.format(totalNet) : '',
                  _PalletCols.net,
                ),
                _totalCell(
                  totalInitial > 0 ? fmt.format(totalInitial) : '',
                  _PalletCols.initial,
                ),
                _totalCell(
                  totalDrained > 0 ? fmt.format(totalDrained) : '',
                  _PalletCols.drained,
                ),
                SizedBox(
                    width: _PalletCols.diff +
                        _PalletCols.pct +
                        _PalletCols.del),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // FIX #3 — fromLTRB(15, 10, 15, 10) matches the 5px cell padding
  // + 10px TextField contentPadding = 15px total horizontal offset.
  Widget _th(String label, double width,
      {bool center = false, bool right = false}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
        child: Align(
          alignment: center
              ? Alignment.center
              : right
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Text(
            label.toUpperCase(),
            style: AppTextStyles.label(color: AppColors.green),
          ),
        ),
      ),
    );
  }

  Widget _totalCell(String value, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 15, vertical: 10),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(value,
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.green,
              )),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Individual pallet row
//
// FIX #5 — IntrinsicHeight + CrossAxisAlignment.stretch ensures the
//   DropdownButtonFormField (ULAB) and TextFields are always the same
//   height, preventing uneven rows on tablet.
// ─────────────────────────────────────────────
class _PalletRow extends StatefulWidget {
  final int index;
  final _PalletRowData row;
  final bool isSubmitted, canDelete;
  final ValueChanged<_PalletRowData> onCalcRow;
  final ValueChanged<_PalletRowData> onUlabChanged;
  final ValueChanged<int> onRemove;

  const _PalletRow({
    required this.index,
    required this.row,
    required this.isSubmitted,
    required this.canDelete,
    required this.onCalcRow,
    required this.onUlabChanged,
    required this.onRemove,
  });

  @override
  State<_PalletRow> createState() => _PalletRowState();
}

class _PalletRowState extends State<_PalletRow> {
  @override
  Widget build(BuildContext context) {
    final row    = widget.row;
    final isAcid = row.isAcidPresent;
    final ro     = widget.isSubmitted;

    return Container(
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppColors.borderLight)),
      ),
      // FIX #5 — IntrinsicHeight makes all cells in the row adopt
      // the height of the tallest child (the ULAB dropdown), so
      // textfield cells don't appear shorter and misaligned on tablet.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // SR
            SizedBox(
              width: _PalletCols.sr,
              child: Center(
                child: Text(
                  '${widget.index + 1}',
                  style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.green),
                ),
              ),
            ),

            // Pallet No
            SizedBox(
              width: _PalletCols.pallet,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: _tableInput(
                  controller: row.palletNoCtrl,
                  hint: 'WP-${(widget.index + 1).toString().padLeft(2, '0')}',
                  readOnly: ro,
                ),
              ),
            ),

            // ULAB Type
            SizedBox(
              width: _PalletCols.ulab,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: ro
                    ? _tableInput(
                  controller: TextEditingController(
                    text: kUlabOptions
                        .firstWhere(
                          (u) => u.id == row.ulabType,
                      orElse: () => kUlabOptions.first,
                    )
                        .name,
                  ),
                  readOnly: true,
                )
                    : DropdownButtonFormField<int>(
                  value: row.ulabType,
                  isDense: true,
                  isExpanded: true, // prevents overflow inside fixed SizedBox
                  style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      color: AppColors.textDark),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.greenXLight,
                    contentPadding:
                    const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius:
                      BorderRadius.circular(6),
                      borderSide: const BorderSide(
                          color: AppColors.border,
                          width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                      BorderRadius.circular(6),
                      borderSide: const BorderSide(
                          color: AppColors.border,
                          width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                      BorderRadius.circular(6),
                      borderSide: const BorderSide(
                          color: AppColors.green,
                          width: 1.5),
                    ),
                  ),
                  items: kUlabOptions
                      .map((u) => DropdownMenuItem(
                    value: u.id,
                    child: Text(u.name,
                        style: GoogleFonts.outfit(
                            fontSize: 12)),
                  ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => row.ulabType = v);
                    widget.onUlabChanged(row);
                  },
                ),
              ),
            ),

            // Gross Wt
            SizedBox(
              width: _PalletCols.gross,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: _tableInput(
                  controller: row.grossCtrl,
                  hint:      '0.000',
                  numeric:   true,
                  readOnly:  ro,
                  onChanged: (_) => widget.onCalcRow(row),
                  textAlign: TextAlign.right,
                ),
              ),
            ),

            // Avg P&F (auto)
            SizedBox(
              width: _PalletCols.avgPF,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: _tableInput(
                  controller: row.avgPFCtrl,
                  readOnly:   true,
                  calcStyle:  true,
                  textAlign:  TextAlign.right,
                ),
              ),
            ),

            // Net Wt (auto)
            SizedBox(
              width: _PalletCols.net,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: _tableInput(
                  controller: row.netCtrl,
                  readOnly:   true,
                  calcStyle:  true,
                  textAlign:  TextAlign.right,
                ),
              ),
            ),

            // Initial Wt (acid only)
            SizedBox(
              width: _PalletCols.initial,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: _tableInput(
                  controller: row.initialCtrl,
                  hint:      '0.000',
                  numeric:   true,
                  readOnly:  ro || !isAcid,
                  disabled:  !isAcid,
                  onChanged: (_) => widget.onCalcRow(row),
                  textAlign: TextAlign.right,
                ),
              ),
            ),

            // Drained Wt (acid only)
            SizedBox(
              width: _PalletCols.drained,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: _tableInput(
                  controller: row.drainedCtrl,
                  hint:      '0.000',
                  numeric:   true,
                  readOnly:  ro || !isAcid,
                  disabled:  !isAcid,
                  onChanged: (_) => widget.onCalcRow(row),
                  textAlign: TextAlign.right,
                ),
              ),
            ),

            // Wt Diff (auto)
            SizedBox(
              width: _PalletCols.diff,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: _tableInput(
                  controller: row.diffCtrl,
                  readOnly:   true,
                  calcStyle:  isAcid,
                  disabled:   !isAcid,
                  textAlign:  TextAlign.right,
                ),
              ),
            ),

            // Acid % (auto)
            SizedBox(
              width: _PalletCols.pct,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: _tableInput(
                  controller: row.acidPctCtrl,
                  readOnly:   true,
                  calcStyle:  isAcid,
                  disabled:   !isAcid,
                  textAlign:  TextAlign.right,
                ),
              ),
            ),

            // Delete
            SizedBox(
              width: _PalletCols.del,
              child: Center(
                child: widget.canDelete
                    ? GestureDetector(
                  onTap: () =>
                      widget.onRemove(widget.index),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius:
                      BorderRadius.circular(5),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      size: 13,
                      color: AppColors.error,
                    ),
                  ),
                )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // FIX #6 — SizedBox(width: double.infinity) wrapper forces the TextField
  // to fill its parent SizedBox cell correctly on tablet.
  // Without this, TextField inside a Row inside a horizontal scroll view
  // can collapse to its minimum intrinsic width.
  Widget _tableInput({
    required TextEditingController controller,
    String hint = '',
    bool readOnly = false,
    bool numeric = false,
    bool calcStyle = false,
    bool disabled = false,
    ValueChanged<String>? onChanged,
    TextAlign textAlign = TextAlign.left,
  }) {
    return SizedBox(
      width: double.infinity, // fills the parent SizedBox cell
      child: TextField(
        controller:     controller,
        readOnly:       readOnly || disabled,
        onChanged:      onChanged,
        textAlign:      textAlign,
        keyboardType:   numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: numeric
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : null,
        style: GoogleFonts.outfit(
          fontSize: 12.5,
          color: disabled
              ? AppColors.textMuted
              : calcStyle
              ? AppColors.green
              : AppColors.textDark,
          fontWeight:
          calcStyle ? FontWeight.w600 : FontWeight.w400,
        ),
        decoration: InputDecoration(
          hintText:  hint,
          hintStyle: GoogleFonts.outfit(
              fontSize: 12, color: AppColors.textMuted),
          isDense:   true,
          filled:    true,
          fillColor: disabled
              ? const Color(0xFFF3F4F6)
              : calcStyle
              ? const Color(0xFFEEF6F1)
              : AppColors.greenXLight,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: disabled
                  ? const Color(0xFFE5E7EB)
                  : calcStyle
                  ? const Color(0xFFC8DFD1)
                  : AppColors.border,
              width: 1.5,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: disabled
                  ? const Color(0xFFE5E7EB)
                  : calcStyle
                  ? const Color(0xFFC8DFD1)
                  : AppColors.border,
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: disabled
                  ? const Color(0xFFE5E7EB)
                  : AppColors.green,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Category rules legend
// ─────────────────────────────────────────────
class _CategoryRules extends StatelessWidget {
  const _CategoryRules();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _crule('⚡ High Acid', 'Avg Acid % > 30%',
              const Color(0xFFFFFBEB), const Color(0xFFFDE68A),
              const Color(0xFF92400E)),
          const SizedBox(width: 8),
          _crule('✓ Normal', '15% – 30%',
              const Color(0xFFF2FAF5), AppColors.border,
              AppColors.greenDark),
          const SizedBox(width: 8),
          _crule('↓ Low Acid', '5% – 15%',
              const Color(0xFFEFF6FF), const Color(0xFFBFDBFE),
              const Color(0xFF1E3A8A)),
          const SizedBox(width: 8),
          _crule('○ Dry / Empty', '< 5%',
              const Color(0xFFF9FAFB), const Color(0xFFE5E7EB),
              const Color(0xFF374151)),
        ],
      ),
    );
  }

  Widget _crule(String title, String sub,
      Color bg, Color border, Color fg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.outfit(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: fg)),
            const SizedBox(height: 2),
            Text(sub,
                style: GoogleFonts.outfit(
                    fontSize: 9.5,
                    color: fg.withOpacity(0.75))),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Net Avg Acid % result banner
// ─────────────────────────────────────────────
class _ResultBanner extends StatelessWidget {
  final double? pct;
  const _ResultBanner({this.pct});

  @override
  Widget build(BuildContext context) {
    final category = acidCategoryFromPct(pct);
    final hasData  = pct != null;

    Color borderColor, bgColor, pillBg, pillFg, dotColor;
    switch (category) {
      case AcidCategory.high:
        borderColor = const Color(0xFFF59E0B);
        bgColor     = const Color(0xFFFFFBEB);
        pillBg      = const Color(0xFFFEF3C7);
        pillFg      = const Color(0xFFB45309);
        dotColor    = const Color(0xFFF59E0B);
        break;
      case AcidCategory.normal:
        borderColor = AppColors.green;
        bgColor     = const Color(0xFFE8F5ED);
        pillBg      = AppColors.greenLight;
        pillFg      = AppColors.greenDark;
        dotColor    = AppColors.green;
        break;
      case AcidCategory.low:
        borderColor = const Color(0xFF3B82F6);
        bgColor     = const Color(0xFFEFF6FF);
        pillBg      = const Color(0xFFEFF6FF);
        pillFg      = const Color(0xFF1D4ED8);
        dotColor    = const Color(0xFF3B82F6);
        break;
      case AcidCategory.dry:
      case AcidCategory.none:
        borderColor = AppColors.border;
        bgColor     = AppColors.greenXLight;
        pillBg      = AppColors.borderLight;
        pillFg      = AppColors.textMid;
        dotColor    = AppColors.textMuted;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding:
      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NET AVERAGE ACID %',
                style: AppTextStyles.label(
                    color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                hasData ? '${pct!.toStringAsFixed(2)}%' : '—',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: hasData
                      ? borderColor
                      : AppColors.textMuted,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '(WEIGHT DIFFERENCE / INITIAL WEIGHT) × 100',
                style: AppTextStyles.caption(),
              ),
            ],
          ),
          const Spacer(),
          if (hasData && category != AcidCategory.none)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: pillBg,
                    border:
                    Border.all(color: borderColor, width: 1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        category.label.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: pillFg,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(category.rule,
                    style: AppTextStyles.caption()),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Submit button
// ─────────────────────────────────────────────
class _SubmitButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const _SubmitButton({
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white),
        )
            : const Icon(Icons.check_circle_outline,
            size: 18, color: Colors.white),
        label: Text(
          isLoading ? 'Submitting…' : 'Submit',
          style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white),
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
    );
  }
}