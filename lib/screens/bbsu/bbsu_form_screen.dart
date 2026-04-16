// ─────────────────────────────────────────────────────────────────────────────
// bbsu_form_screen.dart
// Full replacement — adds offline QTY modal support via bbsu_acid_summary_cache.
//
// Key changes vs previous version:
//   • _openQtyModal() always calls BbsuService().getAcidSummary()
//     which now returns cached rows when offline.
//   • _QtyModal receives a unified `rows` list — same shape online or offline.
//   • If rows is null (lot was never fetched online before), a single
//     editable fallback row is shown using bbsu_lot_cache receivedQty.
//   • Two notice banners: one for offline-cached, one for no-cache-at-all.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:dubatt_app/services/connectivity_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/local_db_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../widgets/common/app_shell.dart';
import '../../models/bbsu_model.dart';
import '../../services/bbsu_service.dart';

class BbsuFormScreen extends StatefulWidget {
  final String? recordId;
  final VoidCallback onLogout;

  const BbsuFormScreen({
    super.key,
    this.recordId,
    required this.onLogout,
  });

  bool get isCreate => recordId == null;

  @override
  State<BbsuFormScreen> createState() => _BbsuFormScreenState();
}

class _BbsuFormScreenState extends State<BbsuFormScreen> {
  final _docNoCtrl    = TextEditingController();
  final _dateCtrl     = TextEditingController();
  final _startCtrl    = TextEditingController();
  final _endCtrl      = TextEditingController();
  String _category    = 'BBSU';

  final List<_InputRowData> _inputRows = [];
  List<BbsuLotOption> _lots            = [];

  final Map<String, TextEditingController> _outputQtyCtrl   = {};
  final Map<String, TextEditingController> _outputYieldCtrl = {};

  final _powerInitCtrl  = TextEditingController();
  final _powerFinalCtrl = TextEditingController();
  final _powerConsCtrl  = TextEditingController();

  bool _isLoading    = true;
  bool _isSaving     = false;
  bool _isSubmitting = false;
  bool _isSubmitted  = false;
  String? _currentId;
  bool _isPreloadingLots = false;

  double _totalInputQty    = 0;
  double _weightedAvgAcid  = 0;
  double _totalOutputQty   = 0;
  double _totalOutputYield = 0;

  @override
  void initState() {
    super.initState();
    for (final mat in kBbsuOutputMaterials) {
      _outputQtyCtrl[mat.code]   = TextEditingController();
      _outputYieldCtrl[mat.code] = TextEditingController();
    }
    _init();
  }

  @override
  void dispose() {
    _docNoCtrl.dispose();
    _dateCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _powerInitCtrl.dispose();
    _powerFinalCtrl.dispose();
    _powerConsCtrl.dispose();
    for (final c in _outputQtyCtrl.values) c.dispose();
    for (final c in _outputYieldCtrl.values) c.dispose();
    for (final r in _inputRows) r.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    _lots = await BbsuService().getAvailableLots();

    if (widget.isCreate) {
      _dateCtrl.text  = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _docNoCtrl.text = await BbsuService().generateBatchNo();
      _addInputRow();
    } else {
      await _loadRecord();
    }
    setState(() => _isLoading = false);

    // Preload all lot summaries into local cache for offline qty assignment.
    unawaited(_preloadAllLotDataForOffline());
  }

  Future<void> _preloadAllLotDataForOffline() async {
    if (!mounted || _isPreloadingLots) return;
    if (!ConnectivityService().isOnline || _lots.isEmpty) return;

    setState(() => _isPreloadingLots = true);
    try {
      await BbsuService().preloadAcidSummariesForLots(
        _lots.map((l) => l.lotNumber).toList(),
      );
    } finally {
      if (mounted) {
        setState(() => _isPreloadingLots = false);
      } else {
        _isPreloadingLots = false;
      }
    }
  }

  Future<void> _loadRecord() async {
    final record = await BbsuService().getOne(widget.recordId!);
    if (record == null) { _showSnack('Failed to load record.', error: true); return; }

    _currentId   = record.id;
    _isSubmitted = record.isSubmitted;

    _docNoCtrl.text  = record.batchNo;
    _dateCtrl.text   = record.docDate.length >= 10 ? record.docDate.substring(0, 10) : record.docDate;
    _startCtrl.text  = BbsuService.formatForDatetimeLocal(record.startTime);
    _endCtrl.text    = BbsuService.formatForDatetimeLocal(record.endTime);
    _category        = record.category;

    if (record.inputDetails.isNotEmpty) {
      for (final d in record.inputDetails) _addInputRow(detail: d);
    } else {
      _addInputRow();
    }

    for (final mat in kBbsuOutputMaterials) {
      final detail = record.outputMaterials[mat.code];
      _outputQtyCtrl[mat.code]!.text   = detail != null && detail.qty > 0 ? detail.qty.toString() : '';
      _outputYieldCtrl[mat.code]!.text = detail != null && detail.yieldPct > 0 ? detail.yieldPct.toStringAsFixed(2) : '';
    }

    if (record.powerConsumption != null) {
      final p = record.powerConsumption!;
      _powerInitCtrl.text  = p.initialPower > 0 ? p.initialPower.toString() : '';
      _powerFinalCtrl.text = p.finalPower > 0 ? p.finalPower.toString() : '';
      _powerConsCtrl.text  = p.totalPowerConsumption > 0 ? p.totalPowerConsumption.toStringAsFixed(2) : '';
    }

    _recalcInputTotals();
    _recalcOutputTotals();
  }

  void _addInputRow({BbsuInputDetail? detail}) {
    _inputRows.add(_InputRowData(
      lots:    _lots,
      lotNo:   detail?.lotNo ?? '',
      qty:     detail?.quantity ?? 0,
      acidPct: detail?.acidPercentage ?? 0,
      breakdown: detail?.materialBreakdown ?? {},
    ));
    _recalcInputTotals();
    if (!_isLoading) setState(() {});
  }

  void _removeInputRow(int index) {
    if (_inputRows.length <= 1) return;
    setState(() { _inputRows[index].dispose(); _inputRows.removeAt(index); });
    _recalcInputTotals();
  }

  void _recalcInputTotals() {
    double tQty = 0, wNum = 0, wDen = 0;
    for (final r in _inputRows) {
      final qty  = r.assignedQty;
      final acid = double.tryParse(r.acidCtrl.text) ?? 0;
      tQty += qty;
      if (qty > 0 && acid > 0) { wNum += qty * acid; wDen += qty; }
    }
    setState(() {
      _totalInputQty   = tQty;
      _weightedAvgAcid = wDen > 0 ? wNum / wDen : 0;
    });
    _recalcOutputTotals();
  }

  void _recalcOutputTotals() {
    double total = 0;
    for (final mat in kBbsuOutputMaterials) {
      total += double.tryParse(_outputQtyCtrl[mat.code]!.text) ?? 0;
    }
    for (final mat in kBbsuOutputMaterials) {
      final qty = double.tryParse(_outputQtyCtrl[mat.code]!.text) ?? 0;
      _outputYieldCtrl[mat.code]!.text =
      _totalInputQty > 0 ? ((qty / _totalInputQty) * 100).toStringAsFixed(2) : '';
    }
    setState(() {
      _totalOutputQty   = total;
      _totalOutputYield = _totalInputQty > 0 ? (total / _totalInputQty) * 100 : 0;
    });
  }

  void _calcPower() {
    final i = double.tryParse(_powerInitCtrl.text) ?? 0;
    final f = double.tryParse(_powerFinalCtrl.text) ?? 0;
    _powerConsCtrl.text = f >= i ? (f - i).toStringAsFixed(2) : '';
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_dateCtrl.text) ?? DateTime.now();
    final picked  = await showDatePicker(
      context: context, initialDate: initial,
      firstDate: DateTime(2020), lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.green, onPrimary: Colors.white)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked));
  }

  Future<void> _pickDateTime(TextEditingController ctrl) async {
    final current = ctrl.text.isNotEmpty ? DateTime.tryParse(ctrl.text) ?? DateTime.now() : DateTime.now();
    final date = await showDatePicker(
      context: context, initialDate: current,
      firstDate: DateTime(2020), lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.green, onPrimary: Colors.white)),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null) return;
    ctrl.text = DateFormat('yyyy-MM-ddTHH:mm')
        .format(DateTime(date.year, date.month, date.day, time.hour, time.minute));
    setState(() {});
  }

  // ── QTY Modal ─────────────────────────────────────────────────────
  // getAcidSummary() now returns:
  //   • Online  → fresh API rows (cached automatically)
  //   • Offline → cached rows from bbsu_acid_summary_cache (if lot was previously fetched online)
  //   • null    → lot was never fetched online; no cache exists at all
  Future<void> _openQtyModal(int rowIndex) async {
    final row = _inputRows[rowIndex];
    if (row.selectedLotNo.isEmpty) {
      _showSnack('Please select a Lot No first.', error: true);
      return;
    }

    // Brief loading snack while reading API / cache
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        const SizedBox(width: 10),
        Text('Loading lot data…', style: GoogleFonts.outfit(fontSize: 13, color: Colors.white)),
      ]),
      backgroundColor: AppColors.green,
      duration: const Duration(milliseconds: 900),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      margin: const EdgeInsets.all(16),
    ));

    final summaryRows = await BbsuService().getAcidSummary(row.selectedLotNo);

    final lotInfo = _lots.firstWhere(
          (l) => l.lotNumber == row.selectedLotNo,
      orElse: () => const BbsuLotOption(lotNumber: ''),
    );

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QtyModal(
        lotNo:       row.selectedLotNo,
        rows:        summaryRows,
        fallbackQty: lotInfo.receivedQty,
        existingQty: row.assignedQty,
        isOffline:   !ConnectivityService().isOnline,
        onConfirm: (qty, acid, breakdown) {
          setState(() {
            row.assignedQty   = qty;
            row.acidCtrl.text = acid.toStringAsFixed(3);
            row.materialBreakdown  = breakdown;
          });
          _recalcInputTotals();
        },
      ),
    );
  }

  Map<String, dynamic>? _buildPayload() {
    if (_dateCtrl.text.isEmpty)  { _showSnack('Date is required.',       error: true); return null; }
    if (_startCtrl.text.isEmpty) { _showSnack('Start Time is required.', error: true); return null; }
    if (_endCtrl.text.isEmpty)   { _showSnack('End Time is required.',   error: true); return null; }
    if (_category.isEmpty)       { _showSnack('Category is required.',   error: true); return null; }

    final inputDetails = <Map<String, dynamic>>[];
    for (final r in _inputRows) {
      if (r.selectedLotNo.isEmpty) continue;
      inputDetails.add({
        'lot_no':          r.selectedLotNo,
        'quantity':        r.assignedQty,
        'acid_percentage': double.tryParse(r.acidCtrl.text) ?? 0,
        'material_breakdown':   r.materialBreakdown.isNotEmpty ? r.materialBreakdown : null,
      });
    }

    final outputMaterial = <String, dynamic>{};
    for (final mat in kBbsuOutputMaterials) {
      outputMaterial[mat.code] = {
        'qty': double.tryParse(_outputQtyCtrl[mat.code]!.text) ?? 0,
      };
    }

    final init   = double.tryParse(_powerInitCtrl.text) ?? 0;
    final final_ = double.tryParse(_powerFinalCtrl.text) ?? 0;

    return {
      'batch_no':   _docNoCtrl.text.trim(),
      'doc_date':   _dateCtrl.text.trim(),
      'category':   _category,
      'start_time': _startCtrl.text.trim(),
      'end_time':   _endCtrl.text.trim(),
      'input_details':   inputDetails,
      'output_material': outputMaterial,
      'power_consumption': {
        'initial_power': init,
        'final_power':   final_,
        'total_power_consumption': final_ >= init ? final_ - init : 0,
      },
    };
  }

  Future<void> _save() async {
    final payload = _buildPayload();
    if (payload == null) return;
    setState(() => _isSaving = true);
    final result = await BbsuService().save(payload, id: _currentId);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (result.success) {
      _showSnack('Record saved successfully.');
      if (widget.isCreate) { Navigator.of(context).pop(); return; }
      if (result.newId != null) _currentId = result.newId;
    } else {
      _showSnack(result.errorMsg ?? 'Save failed.', error: true);
    }
  }

  Future<void> _submit() async {
    if (!ConnectivityService().isOnline) { _showSnack('You are offline. Please connect to submit.', error: true); return; }
    if (_currentId == null) { _showSnack('Save the record before submitting.', error: true); return; }
    if ((double.tryParse(_powerInitCtrl.text) ?? 0) <= 0) { _showSnack('Initial power reading is required.', error: true); return; }
    if ((double.tryParse(_powerFinalCtrl.text) ?? 0) <= 0) { _showSnack('Final power reading is required.', error: true); return; }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Submit & Lock?',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        content: Text('Once submitted, this batch cannot be edited.',
            style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMid)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: GoogleFonts.outfit(color: AppColors.textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Submit & Lock', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    final error = await BbsuService().submit(_currentId!);
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (error == null) { _showSnack('Batch submitted successfully.'); Navigator.of(context).pop(); }
    else { _showSnack(error, error: true); }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: GoogleFonts.outfit(color: Colors.white, fontSize: 13))),
      ]),
      backgroundColor: error ? AppColors.error : AppColors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.hPad(context);

    return AppShell(
      currentRoute: '/bbsu',
      onLogout: widget.onLogout,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.green))
            : SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              if (_isSubmitted)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.lock_outline, size: 18, color: Color(0xFF92400E)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('This batch has been submitted and is locked for editing.',
                        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF92400E)))),
                  ]),
                ),

              MesPageHeader(
                title: _isSubmitted ? 'BBSU Batch (Submitted)'
                    : (widget.isCreate ? 'Battery Breaking & Separation Unit Log' : 'Edit BBSU Batch'),
                subtitle: 'Record input lots, output materials and power consumption',
                actions: [
                  MesOutlineButton(label: 'Back', icon: Icons.arrow_back, small: true,
                      onPressed: () => Navigator.of(context).pop()),
                ],
              ),

              StreamBuilder<bool>(
                stream: ConnectivityService().onlineStream,
                initialData: ConnectivityService().isOnline,
                builder: (_, snap) {
                  if (snap.data ?? true) return const SizedBox.shrink();
                  return Container(
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
                      Expanded(child: Text(
                        'You are offline. Record will sync when connection restores.',
                        style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF92400E)),
                      )),
                    ]),
                  );
                },
              ),

              if (_isPreloadingLots)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFF93C5FD)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Preloading lot data for offline use...',
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            color: const Color(0xFF1E3A8A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // ── SECTION 1: Primary Details ─────────────────────────
              _SectionCard(
                icon: Icons.calendar_today_outlined,
                title: 'Primary Details',
                child: Column(children: [
                  Row(children: [
                    Expanded(child: MesTextField(label: 'Doc No', controller: _docNoCtrl,
                        readOnly: true, prefixIcon: Icons.description_outlined, badge: 'AUTO')),
                    const SizedBox(width: 16),
                    Expanded(child: GestureDetector(
                      onTap: _isSubmitted ? null : _pickDate,
                      child: AbsorbPointer(absorbing: _isSubmitted,
                          child: MesTextField(label: 'Date *', controller: _dateCtrl,
                              readOnly: true, prefixIcon: Icons.calendar_today_outlined)),
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CATEGORY *', style: AppTextStyles.label()),
                        const SizedBox(height: 5),
                        DropdownButtonFormField<String>(
                          value: _category, isDense: true,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.category_outlined, size: 16),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
                                borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
                                borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
                            filled: true, fillColor: AppColors.greenXLight,
                          ),
                          items: BbsuCategory.values.map((c) => DropdownMenuItem(
                            value: c.value,
                            child: Text(c.label, style: GoogleFonts.outfit(fontSize: 13)),
                          )).toList(),
                          onChanged: _isSubmitted ? null : (v) => setState(() => _category = v ?? 'BBSU'),
                        ),
                      ],
                    )),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: GestureDetector(
                      onTap: _isSubmitted ? null : () => _pickDateTime(_startCtrl),
                      child: AbsorbPointer(absorbing: true,
                          child: MesTextField(label: 'Start Time *', controller: _startCtrl,
                              readOnly: true, prefixIcon: Icons.schedule_outlined)),
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: GestureDetector(
                      onTap: _isSubmitted ? null : () => _pickDateTime(_endCtrl),
                      child: AbsorbPointer(absorbing: true,
                          child: MesTextField(label: 'End Time *', controller: _endCtrl,
                              readOnly: true, prefixIcon: Icons.schedule_outlined)),
                    )),
                    const Expanded(child: SizedBox.shrink()),
                  ]),
                ]),
              ),

              const SizedBox(height: 16),

              // ── SECTION 2: Two-column ──────────────────────────────
              LayoutBuilder(builder: (ctx, constraints) {
                final wide = constraints.maxWidth > 700;
                if (wide) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _InputLotsCard(
                      inputRows: _inputRows, isSubmitted: _isSubmitted, lots: _lots,
                      totalQty: _totalInputQty, avgAcid: _weightedAvgAcid,
                      onAddRow: _isSubmitted ? null : () { _addInputRow(); _recalcInputTotals(); },
                      onRemoveRow: _isSubmitted ? null : _removeInputRow,
                      onQtyTap: _isSubmitted ? null : _openQtyModal,
                      onChanged: _recalcInputTotals,
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _OutputMaterialsCard(
                      qtyControllers: _outputQtyCtrl, yieldControllers: _outputYieldCtrl,
                      isSubmitted: _isSubmitted, totalQty: _totalOutputQty,
                      totalYield: _totalOutputYield, onChanged: _recalcOutputTotals,
                    )),
                  ]);
                }
                return Column(children: [
                  _InputLotsCard(
                    inputRows: _inputRows, isSubmitted: _isSubmitted, lots: _lots,
                    totalQty: _totalInputQty, avgAcid: _weightedAvgAcid,
                    onAddRow: _isSubmitted ? null : () { _addInputRow(); _recalcInputTotals(); },
                    onRemoveRow: _isSubmitted ? null : _removeInputRow,
                    onQtyTap: _isSubmitted ? null : _openQtyModal,
                    onChanged: _recalcInputTotals,
                  ),
                  const SizedBox(height: 16),
                  _OutputMaterialsCard(
                    qtyControllers: _outputQtyCtrl, yieldControllers: _outputYieldCtrl,
                    isSubmitted: _isSubmitted, totalQty: _totalOutputQty,
                    totalYield: _totalOutputYield, onChanged: _recalcOutputTotals,
                  ),
                ]);
              }),

              const SizedBox(height: 16),

              // ── SECTION 3: Power ───────────────────────────────────
              _SectionCard(
                icon: Icons.bolt_outlined,
                title: 'BBSU Power Consumption',
                child: Row(children: [
                  Expanded(child: MesTextField(
                    label: 'Initial Reading *', controller: _powerInitCtrl,
                    readOnly: _isSubmitted,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    prefixIcon: Icons.bolt_outlined,
                    onChanged: (_) { _calcPower(); setState(() {}); },
                  )),
                  const SizedBox(width: 16),
                  Expanded(child: MesTextField(
                    label: 'Final Reading *', controller: _powerFinalCtrl,
                    readOnly: _isSubmitted,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    prefixIcon: Icons.bolt_outlined,
                    onChanged: (_) { _calcPower(); setState(() {}); },
                  )),
                  const SizedBox(width: 16),
                  Expanded(child: MesTextField(
                    label: 'Consumption (kWh)', controller: _powerConsCtrl,
                    readOnly: true, badge: 'CALC', badgeColor: AppColors.green,
                    prefixIcon: Icons.electric_bolt,
                  )),
                ]),
              ),

              const SizedBox(height: 24),

              if (_isSubmitted)
                const SizedBox.shrink()
              else if (!widget.isCreate)
                Row(children: [
                  Expanded(child: MesButton(
                    label: 'Save Draft', icon: Icons.save_outlined,
                    isLoading: _isSaving, onPressed: _isSubmitting ? null : _save,
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _SubmitButton(isLoading: _isSubmitting, onPressed: _isSaving ? null : _submit)),
                ])
              else
                MesButton(label: 'Save', icon: Icons.save_outlined, isLoading: _isSaving, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Input row data holder
// ─────────────────────────────────────────────
class _InputRowData {
  final List<BbsuLotOption> lots;
  String selectedLotNo;
  double assignedQty;
  final TextEditingController acidCtrl;
  Map<String, double> materialBreakdown; // ← add this

  _InputRowData({
    required this.lots,
    required String lotNo,
    required double qty,
    required double acidPct,
    Map<String, double>? breakdown,      // ← add this
  })  : selectedLotNo    = lotNo,
        assignedQty      = qty,
        materialBreakdown = breakdown ?? {},
        acidCtrl         = TextEditingController(
            text: acidPct > 0 ? acidPct.toStringAsFixed(3) : '');

  void dispose() => acidCtrl.dispose();
}

// ─────────────────────────────────────────────
// Input Lots Card
// ─────────────────────────────────────────────
class _InputLotsCard extends StatelessWidget {
  final List<_InputRowData> inputRows;
  final bool isSubmitted;
  final List<BbsuLotOption> lots;
  final double totalQty, avgAcid;
  final VoidCallback? onAddRow;
  final ValueChanged<int>? onRemoveRow;
  final ValueChanged<int>? onQtyTap;
  final VoidCallback onChanged;

  const _InputLotsCard({
    required this.inputRows, required this.isSubmitted, required this.lots,
    required this.totalQty, required this.avgAcid, required this.onAddRow,
    required this.onRemoveRow, required this.onQtyTap, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MesCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.greenLight,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(children: [
            const Icon(Icons.layers_outlined, size: 15, color: AppColors.green),
            const SizedBox(width: 8),
            Text('INPUT LOTS', style: AppTextStyles.label(color: AppColors.green)),
            const Spacer(),
            if (onAddRow != null)
              GestureDetector(
                onTap: onAddRow,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(7)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.add, size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('Add New', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(children: [
            Container(
              decoration: const BoxDecoration(
                color: AppColors.greenLight,
                border: Border(bottom: BorderSide(color: AppColors.border, width: 2)),
              ),
              child: Row(children: [
                _th('#', 44, center: true),
                _th('Lot No', 200),
                _th('QTY (KG)', 140),
                _th('Acid %', 100),
                if (!isSubmitted) const SizedBox(width: 44),
              ]),
            ),
            ...inputRows.asMap().entries.map((e) => _InputTableRow(
              index: e.key, row: e.value, lots: lots, isSubmitted: isSubmitted,
              canDelete: inputRows.length > 1 && !isSubmitted,
              onQtyTap: onQtyTap == null ? null : () => onQtyTap!(e.key),
              onRemove: onRemoveRow == null ? null : () => onRemoveRow!(e.key),
              onChanged: onChanged,
            )),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.greenLight,
                border: Border(top: BorderSide(color: AppColors.border, width: 2)),
              ),
              child: Row(children: [
                SizedBox(width: 44 + 200, child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Align(alignment: Alignment.centerRight,
                      child: Text('TOTAL', style: AppTextStyles.label(color: AppColors.green))),
                )),
                _totalCell(totalQty > 0 ? totalQty.toStringAsFixed(2) : '', 140),
                _totalCell(avgAcid > 0 ? avgAcid.toStringAsFixed(3) : '', 100),
                if (!isSubmitted) const SizedBox(width: 44),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _th(String label, double width, {bool center = false}) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Align(
        alignment: center ? Alignment.center : Alignment.centerLeft,
        child: Text(label.toUpperCase(), style: AppTextStyles.label(color: AppColors.green)),
      ),
    ),
  );

  Widget _totalCell(String value, double width) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(value, style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.green)),
    ),
  );
}

// ─────────────────────────────────────────────
// Input table row
// ─────────────────────────────────────────────
class _InputTableRow extends StatefulWidget {
  final int index;
  final _InputRowData row;
  final List<BbsuLotOption> lots;
  final bool isSubmitted, canDelete;
  final VoidCallback? onQtyTap;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  const _InputTableRow({
    required this.index, required this.row, required this.lots,
    required this.isSubmitted, required this.canDelete,
    required this.onQtyTap, required this.onRemove, required this.onChanged,
  });

  @override
  State<_InputTableRow> createState() => _InputTableRowState();
}

class _InputTableRowState extends State<_InputTableRow> {
  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderLight))),
      child: Row(children: [
        SizedBox(width: 44, child: Center(child: Text('${widget.index + 1}',
            style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.green)))),

        SizedBox(width: 200, child: Padding(padding: const EdgeInsets.all(5),
          child: widget.isSubmitted
              ? _roCell(row.selectedLotNo)
              : SearchableDropdown<String>(
            value: row.selectedLotNo.isNotEmpty ? row.selectedLotNo : null,
            items: widget.lots.map((l) => l.lotNumber).toList(),
            displayString: (item) => item,
            hint: 'Select lot…',
            enabled: !widget.isSubmitted,
            onChanged: (v) {
              setState(() => row.selectedLotNo = v ?? '');
              widget.onChanged();
            },
          ),
        )),

        SizedBox(width: 140, child: Padding(padding: const EdgeInsets.all(5),
          child: GestureDetector(
            onTap: widget.onQtyTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: row.assignedQty > 0 ? const Color(0xFFD1FAE5) : AppColors.greenXLight,
                border: Border.all(color: row.assignedQty > 0 ? AppColors.green : AppColors.border, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                Expanded(child: Text(
                  row.assignedQty > 0 ? '${row.assignedQty.toStringAsFixed(3)} KG'
                      : widget.isSubmitted ? '—' : 'Click to assign…',
                  style: GoogleFonts.outfit(fontSize: 12,
                      color: row.assignedQty > 0 ? AppColors.textDark : AppColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                )),
                if (!widget.isSubmitted)
                  const Icon(Icons.keyboard_arrow_down, size: 14, color: AppColors.textMuted),
              ]),
            ),
          ),
        )),

        SizedBox(width: 100, child: Padding(padding: const EdgeInsets.all(5),
          child: _tableInput(controller: row.acidCtrl, hint: '0.000', numeric: true,
              readOnly: widget.isSubmitted, onChanged: (_) => widget.onChanged()),
        )),

        if (!widget.isSubmitted)
          SizedBox(width: 44, child: Center(child: widget.canDelete
              ? GestureDetector(
            onTap: widget.onRemove,
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(5)),
              child: const Icon(Icons.delete_outline, size: 13, color: AppColors.error),
            ),
          )
              : const SizedBox.shrink())),
      ]),
    );
  }

  Widget _roCell(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: const Color(0xFFF0F4F2),
        border: Border.all(color: AppColors.border, width: 1.5), borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textMuted)),
  );

  InputDecoration _dropDec() => InputDecoration(
    isDense: true, filled: true, fillColor: AppColors.greenXLight,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
  );

  Widget _tableInput({required TextEditingController controller, String hint = '',
    bool readOnly = false, bool numeric = false, ValueChanged<String>? onChanged}) =>
      TextField(
        controller: controller, readOnly: readOnly, onChanged: onChanged,
        keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        inputFormatters: numeric ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
        style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textDark),
        decoration: InputDecoration(
          hintText: hint, hintStyle: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
          isDense: true, filled: true,
          fillColor: readOnly ? const Color(0xFFF0F4F2) : AppColors.greenXLight,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
        ),
      );
}

// ─────────────────────────────────────────────
// Output Materials Card
// ─────────────────────────────────────────────
class _OutputMaterialsCard extends StatelessWidget {
  final Map<String, TextEditingController> qtyControllers;
  final Map<String, TextEditingController> yieldControllers;
  final bool isSubmitted;
  final double totalQty, totalYield;
  final VoidCallback onChanged;

  const _OutputMaterialsCard({
    required this.qtyControllers, required this.yieldControllers, required this.isSubmitted,
    required this.totalQty, required this.totalYield, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MesCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(color: AppColors.greenLight,
              border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(children: [
            const Icon(Icons.output_outlined, size: 15, color: AppColors.green),
            const SizedBox(width: 8),
            Text('OUTPUT MATERIALS', style: AppTextStyles.label(color: AppColors.green)),
          ]),
        ),
        Container(
          decoration: const BoxDecoration(color: AppColors.greenLight,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 2))),
          child: Row(children: [_th('O/P Material', 160), _th('QTY (KG)', 120), _th('Yield %', 100)]),
        ),
        ...kBbsuOutputMaterials.map((mat) => _OutputTableRow(
          material: mat, qtyCtrl: qtyControllers[mat.code]!,
          yieldCtrl: yieldControllers[mat.code]!, isSubmitted: isSubmitted, onChanged: onChanged,
        )),
        Container(
          decoration: const BoxDecoration(color: AppColors.greenLight,
              border: Border(top: BorderSide(color: AppColors.border, width: 2))),
          child: Row(children: [
            SizedBox(width: 160, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text('TOTAL', style: AppTextStyles.label(color: AppColors.green)))),
            _totalCell(totalQty > 0 ? totalQty.toStringAsFixed(2) : '', 120),
            _totalCell(totalYield > 0 ? '${totalYield.toStringAsFixed(2)}%' : '', 100),
          ]),
        ),
      ]),
    );
  }

  Widget _th(String label, double width) => SizedBox(
    width: width,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(label.toUpperCase(), style: AppTextStyles.label(color: AppColors.green))),
  );

  Widget _totalCell(String value, double width) => SizedBox(
    width: width,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(value, style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.green))),
  );
}

// ─────────────────────────────────────────────
// Output table row
// ─────────────────────────────────────────────
class _OutputTableRow extends StatelessWidget {
  final BbsuOutputMaterial material;
  final TextEditingController qtyCtrl, yieldCtrl;
  final bool isSubmitted;
  final VoidCallback onChanged;

  const _OutputTableRow({required this.material, required this.qtyCtrl,
    required this.yieldCtrl, required this.isSubmitted, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderLight))),
      child: Row(children: [
        SizedBox(width: 160, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(material.name, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)))),
        SizedBox(width: 120, child: Padding(padding: const EdgeInsets.all(5),
            child: _tableInput(controller: qtyCtrl, readOnly: isSubmitted, onChanged: (_) => onChanged()))),
        SizedBox(width: 100, child: Padding(padding: const EdgeInsets.all(5),
            child: _tableInput(controller: yieldCtrl, readOnly: true, calcStyle: true))),
      ]),
    );
  }

  Widget _tableInput({required TextEditingController controller, bool readOnly = false,
    bool calcStyle = false, ValueChanged<String>? onChanged}) =>
      TextField(
        controller: controller, readOnly: readOnly, onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: readOnly ? null : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        textAlign: TextAlign.right,
        style: GoogleFonts.outfit(fontSize: 12.5,
            color: calcStyle ? AppColors.green : AppColors.textDark,
            fontWeight: calcStyle ? FontWeight.w600 : FontWeight.w400),
        decoration: InputDecoration(
          hintText: '0.00', hintStyle: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
          isDense: true, filled: true,
          fillColor: calcStyle ? const Color(0xFFEEF6F1) : readOnly ? const Color(0xFFF0F4F2) : AppColors.greenXLight,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: calcStyle ? const Color(0xFFC8DFD1) : AppColors.border, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: calcStyle ? const Color(0xFFC8DFD1) : AppColors.border, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
        ),
      );
}

// ─────────────────────────────────────────────
// QTY Assignment Modal
//
// `rows`        → List from getAcidSummary() — same shape online or offline.
//                 null = lot was never fetched while online (no cache).
// `fallbackQty` → from bbsu_lot_cache — used only when rows is null.
// `isOffline`   → drives the notice banner colour/message.
// ─────────────────────────────────────────────
class _QtyModal extends StatefulWidget {
  final String lotNo;
  final List<Map<String, dynamic>>? rows;
  final double? fallbackQty;
  final double existingQty;
  final bool isOffline;
  final void Function(double qty, double acid, Map<String, double> breakdown) onConfirm;

  const _QtyModal({
    required this.lotNo, required this.rows, required this.fallbackQty,
    required this.existingQty, required this.isOffline, required this.onConfirm,
  });

  @override
  State<_QtyModal> createState() => _QtyModalState();
}

class _QtyModalState extends State<_QtyModal> {
  late final List<TextEditingController> _assignCtrl;
  late final List<double> _available;
  late final List<double> _acidPcts;
  late final List<String> _materialDescs;
  late final List<String> _ulabTypes;
  late final bool _usingFallback;


  @override
  void initState() {
    super.initState();
    _assignCtrl    = [];
    _available     = [];
    _acidPcts      = [];
    _materialDescs = [];
    _ulabTypes = [];

    if (widget.rows != null && widget.rows!.isNotEmpty) {
      // ── Real rows (fresh API or offline cache) ────────────────────
      _usingFallback = false;
      for (int i = 0; i < widget.rows!.length; i++) {
        final row   = widget.rows![i];
        // final avail = _toDouble(row['available_qty']) ?? 0;
        // final avail = (_toDouble(row['available_qty']) ?? 0) - (_toDouble(row['used_qty']) ?? 0);
        final avail = (_toDouble(row['available_qty']) ?? 0);
        final acid  = _toDouble(row['avg_acid_pct']) ?? 0;
        final desc  = row['material_description']?.toString() ?? '—';
        _available.add(avail);
        _acidPcts.add(acid);
        _materialDescs.add(desc);
        _ulabTypes.add(row['ulab_type']?.toString() ?? '');
        // Pre-fill existing qty only when there is exactly 1 row
        final pre = widget.rows!.length == 1 && widget.existingQty > 0
            ? widget.existingQty.toStringAsFixed(3)
            : '';
        _assignCtrl.add(TextEditingController(text: pre));
      }
    } else {
      // ── Fallback: lot never fetched online, no acid cache ─────────
      _usingFallback = true;
      _available.add(widget.fallbackQty ?? 0);
      _acidPcts.add(0);
      _materialDescs.add('—');
      _ulabTypes.add('');
      _assignCtrl.add(TextEditingController(
          text: widget.existingQty > 0 ? widget.existingQty.toStringAsFixed(3) : ''));
    }
  }

  @override
  void dispose() {
    for (final c in _assignCtrl) c.dispose();
    super.dispose();
  }

  void _confirm() {
    double totalQty = 0, wNum = 0, wDen = 0;
    final breakdown = <String, double>{};

    for (int i = 0; i < _assignCtrl.length; i++) {
      final qty  = double.tryParse(_assignCtrl[i].text) ?? 0;
      final acid = _acidPcts[i];
      if (qty > 0) {
        totalQty += qty;
        wNum += qty * acid;
        wDen += qty;
        // Use material description as key (mirrors web's ulab_type keying)
        // final key = _materialDescs[i].isNotEmpty ? _materialDescs[i] : 'row_$i';
        final key = _ulabTypes[i].isNotEmpty ? _ulabTypes[i] : 'row_$i';
        breakdown[key] = qty;
      }
    }

    widget.onConfirm(totalQty, wDen > 0 ? wNum / wDen : 0.0, breakdown);
    Navigator.of(context).pop();
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65, maxChildSize: 0.9, minChildSize: 0.4,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(children: [

          // Handle
          Center(child: Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          )),

          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: const BoxDecoration(color: AppColors.greenLight,
                border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              const Icon(Icons.layers_outlined, size: 16, color: AppColors.green),
              const SizedBox(width: 8),
              Text('Assign Quantity from Lot', style: AppTextStyles.subheading(color: AppColors.green)),
              const Spacer(),
              GestureDetector(onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, size: 18, color: AppColors.textMuted)),
            ]),
          ),

          // ── Notice: offline with cached data ──────────────────────
          if (widget.isOffline && !_usingFallback)
            _NoticeBanner(
              icon: Icons.wifi_off, color: const Color(0xFFF59E0B),
              bgColor: const Color(0xFFFEF3C7), borderColor: const Color(0xFFF59E0B),
              textColor: const Color(0xFF92400E),
              message: 'You are offline. Showing cached stock data for this lot.',
            ),

          // ── Notice: no cache at all (fallback mode) ───────────────
          if (_usingFallback)
            _NoticeBanner(
              icon: Icons.info_outline, color: const Color(0xFF1D4ED8),
              bgColor: const Color(0xFFEFF6FF), borderColor: const Color(0xFF93C5FD),
              textColor: const Color(0xFF1E3A8A),
              message: 'No stock data cached for this lot${widget.isOffline ? ' (offline)' : ''}. '
                  'Received qty shown as reference only. Acid % will be 0.',
            ),

          // Sub-label
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Row(children: [
              Text('Lot: ', style: AppTextStyles.caption()),
              Text(widget.lotNo, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              const SizedBox(width: 8),
              Text('·  Enter the qty to assign.', style: AppTextStyles.caption()),
            ]),
          ),

          // Table
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(children: [

                // Table header
                Container(
                  decoration: const BoxDecoration(color: AppColors.greenLight,
                      border: Border(bottom: BorderSide(color: AppColors.border, width: 2))),
                  child: Row(children: [
                    _mth('Lot No', 110), _mth('Material', 150),
                    _mth('Acid %', 80), _mth('Available (KG)', 130),
                    _mth('Assign Qty (KG)', 130),
                  ]),
                ),

                // Rows
                ...List.generate(_assignCtrl.length, (i) {
                  final avail  = _available[i];
                  final acid   = _acidPcts[i];
                  final desc   = _materialDescs[i];
                  final isZero = avail <= 0 && !_usingFallback;

                  return Container(
                    decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.borderLight))),
                    child: Row(children: [

                      // Lot No
                      SizedBox(width: 110, child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Text(widget.lotNo,
                            style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textDark),
                            overflow: TextOverflow.ellipsis),
                      )),

                      // Material description
                      SizedBox(width: 150, child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        child: Text(desc, style: AppTextStyles.body(), overflow: TextOverflow.ellipsis),
                      )),

                      // Acid %
                      SizedBox(width: 80, child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        child: Text('${acid.toStringAsFixed(2)}%', style: AppTextStyles.body()),
                      )),

                      // Available badge
                      SizedBox(width: 130, child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: isZero ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            avail > 0 ? '${avail.toStringAsFixed(3)} KG'
                                : _usingFallback ? 'Ref only' : '0.000 KG',
                            style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600,
                                color: isZero ? const Color(0xFF991B1B) : const Color(0xFF065F46)),
                          ),
                        ),
                      )),

                      // Assign qty input
                      SizedBox(width: 130, child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: TextField(
                          controller: _assignCtrl[i],
                          enabled: !isZero,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          onChanged: (v) {
                            // Cap to available when using real stock rows
                            if (!_usingFallback && avail > 0) {
                              final val = double.tryParse(v) ?? 0;
                              if (val > avail) {
                                _assignCtrl[i].text = avail.toStringAsFixed(3);
                                _assignCtrl[i].selection = TextSelection.fromPosition(
                                    TextPosition(offset: _assignCtrl[i].text.length));
                              }
                            }
                            setState(() {});
                          },
                          style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textDark),
                          decoration: InputDecoration(
                            hintText: '0.000',
                            hintStyle: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
                            isDense: true, filled: true,
                            fillColor: isZero ? const Color(0xFFF3F4F6) : AppColors.greenXLight,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
                          ),
                        ),
                      )),
                    ]),
                  );
                }),
              ]),
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderLight))),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              MesOutlineButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: 12),
              MesButton(label: 'Confirm Assignment', icon: Icons.check, onPressed: _confirm),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _mth(String label, double width) => SizedBox(
    width: width,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(label.toUpperCase(), style: AppTextStyles.label(color: AppColors.green))),
  );
}

// ─────────────────────────────────────────────
// Reusable notice banner
// ─────────────────────────────────────────────
class _NoticeBanner extends StatelessWidget {
  final IconData icon;
  final Color color, bgColor, borderColor, textColor;
  final String message;

  const _NoticeBanner({
    required this.icon, required this.color, required this.bgColor,
    required this.borderColor, required this.textColor, required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor)),
    child: Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: GoogleFonts.outfit(fontSize: 11.5, color: textColor))),
    ]),
  );
}

// ─────────────────────────────────────────────
// Section card (green header)
// ─────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SectionCard({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => MesCard(
    padding: EdgeInsets.zero,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(color: AppColors.greenLight,
            border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Icon(icon, size: 15, color: AppColors.green),
          const SizedBox(width: 8),
          Text(title.toUpperCase(), style: AppTextStyles.label(color: AppColors.green)),
        ]),
      ),
      Padding(padding: const EdgeInsets.all(20), child: child),
    ]),
  );
}

// ─────────────────────────────────────────────
// Submit button (blue)
// ─────────────────────────────────────────────
class _SubmitButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const _SubmitButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: isLoading
          ? const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.lock_outline, size: 16, color: Colors.white),
      label: Text(isLoading ? 'Submitting…' : 'Submit & Lock',
          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1D4ED8),
        disabledBackgroundColor: const Color(0xFF1D4ED8).withOpacity(0.5),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}