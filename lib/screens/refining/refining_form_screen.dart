// ─────────────────────────────────────────────────────────────────────────────
// refining_form_screen.dart
//
// SECTION 1 — Refining Log Sheet header
//   batch_no (auto) | pot_no | material (searchable dropdown) | date
//
// SECTION 2 — Input (two-column)
//   Left:  Lead Raw Material (dynamic rows)
//          material SDD | qty (tap → Smelting Lot Modal) | delete
//   Right: Chemicals and Metals (dynamic rows)
//          material SDD | qty (tap → Smelting Lot Modal) | delete
//
// SECTION 3 — Consumption (table layout with 3 col groups)
//   LPG:         lpg_initial | lpg_final → lpg_consumption (auto)
//   Electricity: electricity_initial | electricity_final → electricity_consumption (auto)
//   Liquid O2:   oxygen_flow_nm3 (manual) | oxygen_flow_kg = nm3×1.429 (auto)
//                oxygen_flow_time (manual hr) | oxygen_consumption = time×flow_kg (auto)
//
// SECTION 4 — Process Details (dynamic rows)
//   process name (searchable, from API) | start+END btn | end+END btn | total time | delete
//
// SECTION 5 — Output (two-column)
//   Left:  Finished Goods (dynamic rows) — material SDD | qty (→ block modal) | delete
//   Right: Drosses (dynamic rows)        — material SDD | qty (→ block modal) | delete
// ─────────────────────────────────────────────────────────────────────────────

import 'package:dubatt_app/services/connectivity_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../widgets/common/app_shell.dart';
import '../../models/refining_model.dart';
import '../../services/refining_service.dart';

class RefiningFormScreen extends StatefulWidget {
  final String? recordId;
  final VoidCallback onLogout;

  const RefiningFormScreen({
    super.key,
    this.recordId,
    required this.onLogout,
  });

  bool get isCreate => recordId == null;

  @override
  State<RefiningFormScreen> createState() => _RefiningFormScreenState();
}

class _RefiningFormScreenState extends State<RefiningFormScreen> {
  // ── Section 1 ──────────────────────────────────────────────────────────────
  final _batchNoCtrl = TextEditingController();
  final _potNoCtrl   = TextEditingController();
  final _dateCtrl    = TextEditingController();
  String? _materialId;   // selected from searchable dropdown

  // ── Materials / process names ───────────────────────────────────────────────
  List<RefiningMaterialOption> _materials    = [];
  List<String>                 _processNames = [];

  // ── Section 2 — Input rows ─────────────────────────────────────────────────
  final List<_RawRow>  _rawRows  = [];
  final List<_ChemRow> _chemRows = [];
  double _rawTotal  = 0;
  double _chemTotal = 0;

  // ── Section 3 — Consumption ─────────────────────────────────────────────────
  final _lpgInitCtrl   = TextEditingController();
  final _lpgFinalCtrl  = TextEditingController();
  final _elecInitCtrl  = TextEditingController();
  final _elecFinalCtrl = TextEditingController();
  final _o2Nm3Ctrl     = TextEditingController();
  final _o2TimeCtrl    = TextEditingController();
  // Auto-calculated (read-only display)
  String _lpgConsumed  = '—';
  String _elecConsumed = '—';
  double? _o2FlowKg;
  double? _o2Consumption;

  // ── Section 4 — Process rows (dynamic) ─────────────────────────────────────
  final List<_ProcRow> _procRows = [];
  int _totalProcMins = 0;

  // ── Section 5 — Output rows ─────────────────────────────────────────────────
  final List<_OutputRow> _fgRows    = [];
  final List<_OutputRow> _drossRows = [];
  double _fgTotal    = 0;
  double _drossTotal = 0;

  // ── UI state ────────────────────────────────────────────────────────────────
  bool _isLoading    = true;
  bool _isSaving     = false;
  bool _isSubmitting = false;
  bool _isSubmitted  = false;
  String? _currentId;
  bool _isPreloadingStock = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _batchNoCtrl.dispose(); _potNoCtrl.dispose(); _dateCtrl.dispose();
    _lpgInitCtrl.dispose(); _lpgFinalCtrl.dispose();
    _elecInitCtrl.dispose(); _elecFinalCtrl.dispose();
    _o2Nm3Ctrl.dispose(); _o2TimeCtrl.dispose();
    for (final r in _rawRows)   r.dispose();
    for (final c in _chemRows)  c.dispose();
    for (final p in _procRows)  p.dispose();
    for (final f in _fgRows)    f.dispose();
    for (final d in _drossRows) d.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    _materials    = await RefiningService().getMaterials();
    _processNames = await RefiningService().getProcessNames();

    if (widget.isCreate) {
      _dateCtrl.text    = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _batchNoCtrl.text = await RefiningService().generateBatchNo();
      _addRawRow(); _addChemRow(); _addProcRow(); _addFGRow(); _addDrossRow();
    } else {
      await _loadRecord();
    }
    setState(() => _isLoading = false);

    // Preload smelting stock for all materials to support full offline use.
    unawaited(_preloadAllStockForOffline());
  }

  Future<void> _preloadAllStockForOffline() async {
    if (!mounted || _isPreloadingStock) return;
    if (!ConnectivityService().isOnline || _materials.isEmpty) return;

    setState(() => _isPreloadingStock = true);
    try {
      await RefiningService().preloadSmeltingLotsForMaterials(
        _materials.map((m) => m.id).toList(),
      );
    } finally {
      if (mounted) {
        setState(() => _isPreloadingStock = false);
      } else {
        _isPreloadingStock = false;
      }
    }
  }

  Future<void> _loadRecord() async {
    final r = await RefiningService().getOne(widget.recordId!);
    if (r == null) { _showSnack('Failed to load record.', error: true); return; }

    _currentId   = r.id;
    _isSubmitted = r.isSubmitted;

    _batchNoCtrl.text = r.batchNo;
    _potNoCtrl.text   = r.potNo ?? '';
    _dateCtrl.text    = r.date.length >= 10 ? r.date.substring(0, 10) : r.date;
    _materialId       = r.materialId;

    _lpgInitCtrl.text   = r.lpgInitial?.toString() ?? '';
    _lpgFinalCtrl.text  = r.lpgFinal?.toString() ?? '';
    _elecInitCtrl.text  = r.electricityInitial?.toString() ?? '';
    _elecFinalCtrl.text = r.electricityFinal?.toString() ?? '';
    _o2Nm3Ctrl.text     = r.oxygenFlowNm3?.toString() ?? '';
    _o2TimeCtrl.text    = r.oxygenFlowTime?.toString() ?? '';
    _calcLpg(); _calcElec(); _calcO2();

    for (final rm in r.rawMaterials) _addRawRow(data: rm);
    if (r.rawMaterials.isEmpty) _addRawRow();

    for (final c in r.chemicals) _addChemRow(data: c);
    if (r.chemicals.isEmpty) _addChemRow();

    for (final p in r.processDetails) _addProcRow(data: p);
    if (r.processDetails.isEmpty) _addProcRow();

    for (final fg in r.finishedGoodsSummary) _addFGRow(data: fg);
    if (r.finishedGoodsSummary.isEmpty) _addFGRow();

    for (final dr in r.drossSummary) _addDrossRow(data: dr);
    if (r.drossSummary.isEmpty) _addDrossRow();

    _recalcRawTotal(); _recalcChemTotal();
    _recalcFGTotal(); _recalcDrossTotal();
    _recalcTotalProcTime();
  }

  // ── Row management ─────────────────────────────────────────────────────────
  void _addRawRow({RefiningRawMaterial? data}) {
    _rawRows.add(_RawRow(
      materials: _materials, materialId: data?.rawMaterialId ?? '',
      smtSelections: data?.smeltingSelections ?? [],
      qty: data?.qty ?? 0,
    ));
    _recalcRawTotal();
    if (!_isLoading) setState(() {});
  }

  void _removeRawRow(int i) {
    if (_rawRows.length <= 1) return;
    setState(() { _rawRows[i].dispose(); _rawRows.removeAt(i); });
    _recalcRawTotal();
  }

  void _recalcRawTotal() {
    double t = 0;
    for (final r in _rawRows) t += double.tryParse(r.qtyCtrl.text) ?? 0;
    setState(() => _rawTotal = t);
  }

  void _addChemRow({RefiningChemical? data}) {
    _chemRows.add(_ChemRow(
      materials: _materials, materialId: data?.chemicalId ?? '',
      smtSelections: data?.smeltingSelections ?? [],
      qty: data?.qty ?? 0,
    ));
    _recalcChemTotal();
    if (!_isLoading) setState(() {});
  }

  void _removeChemRow(int i) {
    if (_chemRows.length <= 1) return;
    setState(() { _chemRows[i].dispose(); _chemRows.removeAt(i); });
    _recalcChemTotal();
  }

  void _recalcChemTotal() {
    double t = 0;
    for (final c in _chemRows) t += double.tryParse(c.qtyCtrl.text) ?? 0;
    setState(() => _chemTotal = t);
  }

  void _addProcRow({RefiningProcessDetail? data}) {
    _procRows.add(_ProcRow(
      processNames: _processNames,
      processName:  data?.refiningProcess ?? '',
      startTime:    RefiningService.toHHmm(data?.startTime) ?? '',
      endTime:      RefiningService.toHHmm(data?.endTime) ?? '',
    ));
    if (data != null) _calcProcTime(_procRows.length - 1);
    if (!_isLoading) setState(() {});
  }

  void _removeProcRow(int i) {
    if (_procRows.length <= 1) return;
    setState(() { _procRows[i].dispose(); _procRows.removeAt(i); });
    _recalcTotalProcTime();
  }

  void _calcProcTime(int i) {
    final r = _procRows[i];
    final s = r.startCtrl.text;
    final e = r.endCtrl.text;
    if (s.isNotEmpty && e.isNotEmpty) {
      try {
        final sp = s.split(':').map(int.parse).toList();
        final ep = e.split(':').map(int.parse).toList();
        int m = (ep[0] * 60 + ep[1]) - (sp[0] * 60 + sp[1]);
        if (m < 0) m += 1440;
        r.totalMins = m;
        r.totalCtrl.text = '${m} min';
      } catch (_) {}
    } else {
      r.totalMins = 0;
      r.totalCtrl.text = '';
    }
    _recalcTotalProcTime();
    setState(() {});
  }

  void _recalcTotalProcTime() {
    final total = _procRows.fold<int>(0, (s, r) => s + r.totalMins);
    setState(() => _totalProcMins = total);
  }

  void _addFGRow({RefiningFinishedGood? data}) {
    _fgRows.add(_OutputRow(
      materials:    _materials,
      materialId:   data?.materialId ?? '',
      totalQty:     data?.totalQty ?? 0,
      outputBlocks: data?.outputBlocks
          .map((b) => b.blockWeight)
          .toList() ?? [],
    ));
    _recalcFGTotal();
    if (!_isLoading) setState(() {});
  }

  void _removeFGRow(int i) {
    if (_fgRows.length <= 1) return;
    setState(() { _fgRows[i].dispose(); _fgRows.removeAt(i); });
    _recalcFGTotal();
  }

  void _recalcFGTotal() {
    double t = 0;
    for (final f in _fgRows) t += double.tryParse(f.qtyCtrl.text) ?? 0;
    setState(() => _fgTotal = t);
  }

  void _addDrossRow({RefiningDross? data}) {
    _drossRows.add(_OutputRow(
      materials:    _materials,
      materialId:   data?.materialId ?? '',
      totalQty:     data?.totalQty ?? 0,
      outputBlocks: data?.outputBlocks
          .map((b) => b.blockWeight)
          .toList() ?? [],
    ));
    _recalcDrossTotal();
    if (!_isLoading) setState(() {});
  }

  void _removeDrossRow(int i) {
    if (_drossRows.length <= 1) return;
    setState(() { _drossRows[i].dispose(); _drossRows.removeAt(i); });
    _recalcDrossTotal();
  }

  void _recalcDrossTotal() {
    double t = 0;
    for (final d in _drossRows) t += double.tryParse(d.qtyCtrl.text) ?? 0;
    setState(() => _drossTotal = t);
  }

  // ── Consumption calcs ───────────────────────────────────────────────────────
  void _calcLpg() {
    final i = double.tryParse(_lpgInitCtrl.text);
    final f = double.tryParse(_lpgFinalCtrl.text);
    setState(() => _lpgConsumed = (i != null && f != null && f >= i)
        ? '${(f - i).toStringAsFixed(3)} m³' : '—');
  }

  void _calcElec() {
    final i = double.tryParse(_elecInitCtrl.text);
    final f = double.tryParse(_elecFinalCtrl.text);
    setState(() => _elecConsumed = (i != null && f != null && f >= i)
        ? '${(f - i).toStringAsFixed(3)} kWh' : '—');
  }

  void _calcO2() {
    final nm3  = double.tryParse(_o2Nm3Ctrl.text);
    final time = double.tryParse(_o2TimeCtrl.text);
    final kg   = nm3 != null ? nm3 * 1.429 : null;
    final cons = (kg != null && time != null) ? time * kg : null;
    setState(() { _o2FlowKg = kg; _o2Consumption = cons; });
  }

  // ── Pickers ─────────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final i = DateTime.tryParse(_dateCtrl.text) ?? DateTime.now();
    final p = await showDatePicker(
      context: context, initialDate: i,
      firstDate: DateTime(2020), lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(
            primary: AppColors.green, onPrimary: Colors.white)),
        child: child!,
      ),
    );
    if (p != null) setState(() => _dateCtrl.text = DateFormat('yyyy-MM-dd').format(p));
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    TimeOfDay current = TimeOfDay.now();
    if (ctrl.text.isNotEmpty) {
      try {
        final parts = ctrl.text.split(':');
        current = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {}
    }
    final p = await showTimePicker(context: context, initialTime: current);
    if (p != null) {
      setState(() => ctrl.text =
      '${p.hour.toString().padLeft(2,'0')}:${p.minute.toString().padLeft(2,'0')}');
    }
  }

  // ── Smelting lot modal ──────────────────────────────────────────────────────
  Future<void> _openSmtModal({
    required String materialId,
    required String materialName,
    required bool isRaw,
    required int rowIndex,
  }) async {
    if (materialId.isEmpty) {
      _showSnack('Please select a material first.', error: true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        const SizedBox(width: 10),
        Text('Loading smelting batches…',
            style: GoogleFonts.outfit(fontSize: 13, color: Colors.white)),
      ]),
      backgroundColor: AppColors.green,
      duration: const Duration(milliseconds: 900),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      margin: const EdgeInsets.all(16),
    ));

    final lots = await RefiningService().getSmeltingLots(
      materialId,
      excludeRefiningId: _currentId,
    );

    if (!mounted) return;

    final existing = isRaw
        ? _rawRows[rowIndex].smtSelections
        : _chemRows[rowIndex].smtSelections;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SmeltingLotModal(
        materialName:      materialName,
        lots:              lots,
        isOffline:         !ConnectivityService().isOnline,
        existingSelections: existing,
        onConfirm: (selections) {
          final totalQty = selections.fold<double>(0, (s, r) => s + r.qty);
          setState(() {
            if (isRaw) {
              _rawRows[rowIndex].smtSelections  = selections;
              _rawRows[rowIndex].qtyCtrl.text   = totalQty.toStringAsFixed(3);
              _recalcRawTotal();
            } else {
              _chemRows[rowIndex].smtSelections = selections;
              _chemRows[rowIndex].qtyCtrl.text  = totalQty.toStringAsFixed(3);
              _recalcChemTotal();
            }
          });
        },
      ),
    );
  }

  // ── Output block modal ──────────────────────────────────────────────────────
  Future<void> _openOutputModal({
    required bool isFG,
    required int rowIndex,
  }) async {
    final rows    = isFG ? _fgRows : _drossRows;
    final row     = rows[rowIndex];
    if (row.materialId.isEmpty) {
      _showSnack('Please select a material first.', error: true);
      return;
    }
    final matName = _materials.firstWhere(
            (m) => m.id == row.materialId,
        orElse: () => RefiningMaterialOption(id: '', name: '—')).name;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OutputBlockModal(
        title:       isFG ? 'Finished Goods QTY Window' : 'Dross QTY Window',
        materialName: matName,
        blocks:      List<double>.from(row.outputBlocks),
        onConfirm: (blocks) {
          final total = blocks.fold<double>(0, (s, v) => s + (v > 0 ? v : 0));
          setState(() {
            rows[rowIndex].outputBlocks = blocks;
            rows[rowIndex].qtyCtrl.text = total > 0 ? total.toStringAsFixed(3) : '';
          });
          if (isFG) _recalcFGTotal(); else _recalcDrossTotal();
        },
      ),
    );
  }

  // ── Build payload ────────────────────────────────────────────────────────────
  Map<String, dynamic>? _buildPayload() {
    if (_dateCtrl.text.isEmpty) {
      _showSnack('Date is required.', error: true); return null;
    }
    final date = _dateCtrl.text.trim();

    final rawMats = <Map<String, dynamic>>[];
    for (final r in _rawRows) {
      if (r.materialId.isEmpty) continue;
      rawMats.add({
        'raw_material_id':    r.materialId,
        'qty':                double.tryParse(r.qtyCtrl.text) ?? 0,
        'smelting_batch_id':  r.smtSelections.isNotEmpty
            ? r.smtSelections.first.smtId : null,
        'smelting_batch_no':  r.smtSelections.isNotEmpty
            ? r.smtSelections.first.smtNo : null,
        'smelting_selections': r.smtSelections.map((s) => s.toJson()).toList(),
      });
    }

    final chems = <Map<String, dynamic>>[];
    for (final c in _chemRows) {
      if (c.materialId.isEmpty) continue;
      chems.add({
        'chemical_id':        c.materialId,
        'qty':                double.tryParse(c.qtyCtrl.text) ?? 0,
        'smelting_batch_id':  c.smtSelections.isNotEmpty
            ? c.smtSelections.first.smtId : null,
        'smelting_batch_no':  c.smtSelections.isNotEmpty
            ? c.smtSelections.first.smtNo : null,
        'smelting_selections': c.smtSelections.map((s) => s.toJson()).toList(),
      });
    }

    final procDetails = <Map<String, dynamic>>[];
    for (final p in _procRows) {
      if (p.processName.isEmpty) continue;
      procDetails.add({
        'refining_process': p.processName,
        'start_time':       p.startCtrl.text.isNotEmpty
            ? RefiningService.toIsoDateTime(date, p.startCtrl.text) : null,
        'end_time':         p.endCtrl.text.isNotEmpty
            ? RefiningService.toIsoDateTime(date, p.endCtrl.text) : null,
      });
    }

    final fgSummary = <Map<String, dynamic>>[];
    final fgBlocks  = <Map<String, dynamic>>[];
    for (final f in _fgRows) {
      if (f.materialId.isEmpty) continue;
      final total = f.outputBlocks.fold<double>(0, (s, v) => s + (v > 0 ? v : 0));
      if (total > 0) fgSummary.add({'material_id': f.materialId, 'total_qty': total});
      for (int i = 0; i < f.outputBlocks.length; i++) {
        if (f.outputBlocks[i] > 0) {
          fgBlocks.add({'material_id': f.materialId,
            'block_sl_no': i + 1, 'block_weight': f.outputBlocks[i]});
        }
      }
    }

    final drossSummary = <Map<String, dynamic>>[];
    final drossBlocks  = <Map<String, dynamic>>[];
    for (final d in _drossRows) {
      if (d.materialId.isEmpty) continue;
      final total = d.outputBlocks.fold<double>(0, (s, v) => s + (v > 0 ? v : 0));
      if (total > 0) drossSummary.add({'material_id': d.materialId, 'total_qty': total});
      for (int i = 0; i < d.outputBlocks.length; i++) {
        if (d.outputBlocks[i] > 0) {
          drossBlocks.add({'material_id': d.materialId,
            'block_sl_no': i + 1, 'block_weight': d.outputBlocks[i]});
        }
      }
    }

    final lpgInit   = double.tryParse(_lpgInitCtrl.text);
    final lpgFin    = double.tryParse(_lpgFinalCtrl.text);
    final elecInit  = double.tryParse(_elecInitCtrl.text);
    final elecFin   = double.tryParse(_elecFinalCtrl.text);

    return {
      'batch_no':    _batchNoCtrl.text.trim(),
      'pot_no':      _potNoCtrl.text.trim().isNotEmpty
          ? _potNoCtrl.text.trim() : null,
      'material_id': _materialId,
      'date':        date,
      'lpg_initial':             lpgInit,
      'lpg_final':               lpgFin,
      'lpg_consumption':         (lpgInit != null && lpgFin != null && lpgFin >= lpgInit)
          ? lpgFin - lpgInit : null,
      'electricity_initial':     elecInit,
      'electricity_final':       elecFin,
      'electricity_consumption': (elecInit != null && elecFin != null && elecFin >= elecInit)
          ? elecFin - elecInit : null,
      'oxygen_flow_nm3':   double.tryParse(_o2Nm3Ctrl.text),
      'oxygen_flow_kg':    _o2FlowKg,
      'oxygen_flow_time':  double.tryParse(_o2TimeCtrl.text),
      'oxygen_consumption': _o2Consumption,
      'total_process_time': _totalProcMins,
      'raw_materials':          rawMats,
      'chemicals':              chems,
      'process_details':        procDetails,
      'finished_goods_summary': fgSummary,
      'finished_goods_blocks':  fgBlocks,
      'dross_summary':          drossSummary,
      'dross_blocks':           drossBlocks,
    };
  }

  // ── Save ─────────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final payload = _buildPayload();
    if (payload == null) return;
    setState(() => _isSaving = true);
    final result = await RefiningService().save(payload, id: _currentId);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (result.success) {
      _showSnack('Record saved successfully.');
      if (widget.isCreate) {
        if (result.newId != null) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => RefiningFormScreen(
                recordId: result.newId, onLogout: widget.onLogout),
          ));
        } else {
          Navigator.of(context).pop();
        }
      } else if (result.newId != null) {
        _currentId = result.newId;
      }
    } else {
      _showSnack(result.errorMsg ?? 'Save failed.', error: true);
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────────
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Submit & Lock?',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600,
                color: AppColors.textDark)),
        content: Text('Once submitted, this batch cannot be edited.',
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
              backgroundColor: const Color(0xFF1D4ED8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Submit & Lock',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isSubmitting = true);
    final error = await RefiningService().submit(_currentId!);
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (error == null) { _showSnack('Batch submitted successfully.'); Navigator.of(context).pop(); }
    else { _showSnack(error, error: true); }
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

  // ── BUILD ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.hPad(context);

    return AppShell(
      currentRoute: '/refining',
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

              // Locked banner
              if (_isSubmitted) _LockedBanner(),

              MesPageHeader(
                title: _isSubmitted
                    ? 'Refining Batch (Submitted)'
                    : (widget.isCreate ? 'Create Refining Batch' : 'Edit Refining Batch'),
                subtitle: 'Refining log sheet — finished goods & dross tracking',
                actions: [
                  MesOutlineButton(label: 'Back', icon: Icons.arrow_back,
                      small: true, onPressed: () => Navigator.of(context).pop()),
                ],
              ),

              // Offline banner
              StreamBuilder<bool>(
                stream: ConnectivityService().onlineStream,
                initialData: ConnectivityService().isOnline,
                builder: (_, snap) {
                  if (snap.data ?? true) return const SizedBox.shrink();
                  return _OfflineBanner();
                },
              ),

              if (_isPreloadingStock)
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
                          'Preloading stock for offline use...',
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

              // ══ SECTION 1 ════════════════════════════════════════════
              _SectionCard(
                icon: Icons.description_outlined,
                title: 'Refining Log Sheet',
                child: LayoutBuilder(builder: (_, box) {
                  final wide = box.maxWidth > 600;
                  final fields = [
                    MesTextField(label: 'Batch No',
                        controller: _batchNoCtrl, readOnly: true,
                        prefixIcon: Icons.description_outlined, badge: 'AUTO'),
                    MesTextField(label: 'Pot No',
                        controller: _potNoCtrl, readOnly: _isSubmitted,
                        prefixIcon: Icons.radio_button_unchecked_outlined),
                    _SearchableDropField(
                      label: 'Material',
                      value: _materialId,
                      items: _materials,
                      enabled: !_isSubmitted,
                      onChanged: (v) => setState(() => _materialId = v),
                    ),
                    GestureDetector(
                      onTap: _isSubmitted ? null : _pickDate,
                      child: AbsorbPointer(absorbing: _isSubmitted,
                          child: MesTextField(label: 'Date *',
                              controller: _dateCtrl, readOnly: true,
                              prefixIcon: Icons.calendar_today_outlined)),
                    ),
                  ];
                  if (wide) {
                    return Row(
                      children: fields
                          .expand((f) => [Expanded(child: f), const SizedBox(width: 14)])
                          .toList()
                        ..removeLast(),
                    );
                  }
                  return Column(
                    children: fields
                        .expand((f) => [f, const SizedBox(height: 12)])
                        .toList()
                      ..removeLast(),
                  );
                }),
              ),

              const SizedBox(height: 16),

              // ══ SECTION 2 — Input ════════════════════════════════════
              LayoutBuilder(builder: (_, box) {
                final wide = box.maxWidth > 700;
                final raw = _InputTable(
                  title:       'Lead Raw Material',
                  icon:        Icons.layers_outlined,
                  rows:        _rawRows,
                  total:       _rawTotal,
                  isSubmitted: _isSubmitted,
                  onAdd: _isSubmitted ? null : _addRawRow,
                  onRemove: _isSubmitted ? null : _removeRawRow,
                  onQtyTap: _isSubmitted ? null : (i) async {
                    final r = _rawRows[i];
                    await _openSmtModal(materialId: r.materialId,
                        materialName: r.materialName,
                        isRaw: true, rowIndex: i);
                  },
                  onRecalc: _recalcRawTotal,
                );
                final chem = _InputTable(
                  title:       'Chemicals and Metals',
                  icon:        Icons.science_outlined,
                  rows:        _chemRows,
                  total:       _chemTotal,
                  isSubmitted: _isSubmitted,
                  onAdd: _isSubmitted ? null : _addChemRow,
                  onRemove: _isSubmitted ? null : _removeChemRow,
                  onQtyTap: _isSubmitted ? null : (i) async {
                    final c = _chemRows[i];
                    await _openSmtModal(materialId: c.materialId,
                        materialName: c.materialName,
                        isRaw: false, rowIndex: i);
                  },
                  onRecalc: _recalcChemTotal,
                );
                if (wide) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: raw),
                    const SizedBox(width: 16),
                    Expanded(child: chem),
                  ]);
                }
                return Column(children: [raw, const SizedBox(height: 16), chem]);
              }),

              const SizedBox(height: 16),

              // ══ SECTION 3 — Consumption ══════════════════════════════
              _ConsumptionSection(
                lpgInitCtrl: _lpgInitCtrl, lpgFinalCtrl: _lpgFinalCtrl,
                lpgConsumed: _lpgConsumed,
                elecInitCtrl: _elecInitCtrl, elecFinalCtrl: _elecFinalCtrl,
                elecConsumed: _elecConsumed,
                o2Nm3Ctrl: _o2Nm3Ctrl, o2FlowKg: _o2FlowKg,
                o2TimeCtrl: _o2TimeCtrl, o2Consumption: _o2Consumption,
                isSubmitted: _isSubmitted,
                onLpgChanged: (_) { _calcLpg(); },
                onElecChanged: (_) { _calcElec(); },
                onO2Changed: (_) { _calcO2(); },
              ),

              const SizedBox(height: 16),

              // ══ SECTION 4 — Process Details ══════════════════════════
              _ProcessTable(
                rows:           _procRows,
                totalProcMins:  _totalProcMins,
                isSubmitted:    _isSubmitted,
                processNames:   _processNames,
                onAdd: _isSubmitted ? null : _addProcRow,
                onRemove: _isSubmitted ? null : _removeProcRow,
                onCalcTime: _calcProcTime,
                onSetNow: _isSubmitted ? null : (i, which) {
                  final now = TimeOfDay.now();
                  final hhmm = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
                  setState(() {
                    if (which == 'start') _procRows[i].startCtrl.text = hhmm;
                    else                  _procRows[i].endCtrl.text   = hhmm;
                    _calcProcTime(i);
                  });
                },
                onPickTime: _isSubmitted ? null : (i, which) async {
                  final ctrl = which == 'start'
                      ? _procRows[i].startCtrl
                      : _procRows[i].endCtrl;
                  await _pickTime(ctrl);
                  _calcProcTime(i);
                },
              ),

              const SizedBox(height: 16),

              // ══ SECTION 5 — Output ═══════════════════════════════════
              LayoutBuilder(builder: (_, box) {
                final wide = box.maxWidth > 700;
                final fg = _OutputTable(
                  title: 'Finished Goods',
                  icon:  Icons.star_outline,
                  rows:  _fgRows,
                  total: _fgTotal,
                  isSubmitted: _isSubmitted,
                  onAdd: _isSubmitted ? null : _addFGRow,
                  onRemove: _isSubmitted ? null : _removeFGRow,
                  onQtyTap: _isSubmitted ? null : (i) => _openOutputModal(isFG: true, rowIndex: i),
                  onRecalc: _recalcFGTotal,
                );
                final dross = _OutputTable(
                  title: 'Drosses',
                  icon:  Icons.filter_alt_outlined,
                  rows:  _drossRows,
                  total: _drossTotal,
                  isSubmitted: _isSubmitted,
                  onAdd: _isSubmitted ? null : _addDrossRow,
                  onRemove: _isSubmitted ? null : _removeDrossRow,
                  onQtyTap: _isSubmitted ? null : (i) => _openOutputModal(isFG: false, rowIndex: i),
                  onRecalc: _recalcDrossTotal,
                );
                if (wide) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: fg),
                    const SizedBox(width: 16),
                    Expanded(child: dross),
                  ]);
                }
                return Column(children: [fg, const SizedBox(height: 16), dross]);
              }),

              const SizedBox(height: 24),

              // Action buttons
              if (_isSubmitted)
                const SizedBox.shrink()
              else if (!widget.isCreate)
                Row(children: [
                  Expanded(child: MesButton(
                    label: 'Save Draft', icon: Icons.save_outlined,
                    isLoading: _isSaving, onPressed: _isSubmitting ? null : _save,
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _SubmitBtn(
                    isLoading: _isSubmitting, onPressed: _isSaving ? null : _submit,
                  )),
                ])
              else
                MesButton(label: 'Create Batch', icon: Icons.save_outlined,
                    isLoading: _isSaving, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Data holders
// ─────────────────────────────────────────────
class _RawRow {
  final List<RefiningMaterialOption> materials;
  String materialId;
  List<SmeltingSelection> smtSelections;
  final TextEditingController qtyCtrl;

  _RawRow({required this.materials, required String materialId,
    required this.smtSelections, required double qty})
      : materialId = materialId,
        qtyCtrl    = TextEditingController(text: qty > 0 ? qty.toStringAsFixed(3) : '');

  String get materialName => materials.firstWhere((m) => m.id == materialId,
      orElse: () => RefiningMaterialOption(id: '', name: '—')).name;

  void dispose() => qtyCtrl.dispose();
}

class _ChemRow {
  final List<RefiningMaterialOption> materials;
  String materialId;
  List<SmeltingSelection> smtSelections;
  final TextEditingController qtyCtrl;

  _ChemRow({required this.materials, required String materialId,
    required this.smtSelections, required double qty})
      : materialId = materialId,
        qtyCtrl    = TextEditingController(text: qty > 0 ? qty.toStringAsFixed(3) : '');

  String get materialName => materials.firstWhere((m) => m.id == materialId,
      orElse: () => RefiningMaterialOption(id: '', name: '—')).name;

  void dispose() => qtyCtrl.dispose();
}

class _ProcRow {
  final List<String> processNames;
  String processName;
  final TextEditingController startCtrl, endCtrl, totalCtrl;
  int totalMins = 0;

  _ProcRow({required this.processNames, required this.processName,
    required String startTime, required String endTime})
      : startCtrl = TextEditingController(text: startTime),
        endCtrl   = TextEditingController(text: endTime),
        totalCtrl = TextEditingController();

  void dispose() { startCtrl.dispose(); endCtrl.dispose(); totalCtrl.dispose(); }
}

class _OutputRow {
  final List<RefiningMaterialOption> materials;
  String materialId;
  List<double> outputBlocks;
  final TextEditingController qtyCtrl;

  _OutputRow({required this.materials, required String materialId,
    required double totalQty, required List<double> outputBlocks})
      : materialId   = materialId,
        outputBlocks = outputBlocks,
        qtyCtrl      = TextEditingController(
            text: totalQty > 0 ? totalQty.toStringAsFixed(3) : '');

  void dispose() => qtyCtrl.dispose();
}

// ─────────────────────────────────────────────
// Searchable dropdown for header material
// ─────────────────────────────────────────────
// Replace the entire _SearchableDropField class with this:
class _SearchableDropField extends StatelessWidget {
  final String label;
  final String? value;
  final List<RefiningMaterialOption> items;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _SearchableDropField({
    required this.label,
    required this.value,
    required this.items,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTextStyles.label()),
        const SizedBox(height: 5),
        SearchableDropdown<String>(
          value: value?.isNotEmpty == true ? value : null,
          items: items.map((m) => m.id).toList(),
          displayString: (id) => items.firstWhere(
                (m) => m.id == id,
            orElse: () => RefiningMaterialOption(id: '', name: '—'),
          ).name,
          hint: 'Select material…',
          enabled: enabled,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Input table (shared for raw + chem)
// ─────────────────────────────────────────────
class _InputTable extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<dynamic> rows; // _RawRow | _ChemRow both have materialId/qtyCtrl
  final double total;
  final bool isSubmitted;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemove;
  final ValueChanged<int>? onQtyTap;
  final VoidCallback onRecalc;

  const _InputTable({
    required this.title, required this.icon, required this.rows,
    required this.total, required this.isSubmitted,
    required this.onAdd, required this.onRemove,
    required this.onQtyTap, required this.onRecalc,
  });

  @override
  Widget build(BuildContext context) {
    return MesCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHead(title, icon, onAdd),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(children: [
            _tblHeader(['#', 'Material', 'QTY (KG)', ''], [36, 180, 130, 36]),
            ...rows.asMap().entries.map((e) => _InputTblRow(
              index:       e.key,
              row:         e.value,
              isSubmitted: isSubmitted,
              canDelete:   rows.length > 1 && !isSubmitted,
              onQtyTap:    onQtyTap == null ? null : () => onQtyTap!(e.key),
              onRemove:    onRemove == null ? null : () => onRemove!(e.key),
              onRecalc:    onRecalc,
            )),
            _tblFooter([
              (36 + 180.0, 'TOTAL', true),
              (130.0, total > 0 ? total.toStringAsFixed(3) : '', false),
              (36.0, '', false),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Input table row
// ─────────────────────────────────────────────
class _InputTblRow extends StatefulWidget {
  final int index;
  final dynamic row; // _RawRow | _ChemRow
  final bool isSubmitted, canDelete;
  final VoidCallback? onQtyTap, onRemove;
  final VoidCallback onRecalc;

  const _InputTblRow({
    required this.index, required this.row, required this.isSubmitted,
    required this.canDelete, required this.onQtyTap, required this.onRemove,
    required this.onRecalc,
  });

  @override
  State<_InputTblRow> createState() => _InputTblRowState();
}

class _InputTblRowState extends State<_InputTblRow> {
  List<RefiningMaterialOption> get _mats => (widget.row as dynamic).materials as List<RefiningMaterialOption>;
  String get _matId => (widget.row as dynamic).materialId as String;
  set _matId(String v) => (widget.row as dynamic).materialId = v;
  TextEditingController get _qtyCtrl => (widget.row as dynamic).qtyCtrl as TextEditingController;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderLight))),
      child: Row(children: [
        SizedBox(width: 36, child: Center(child: Text('${widget.index + 1}',
            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700,
                color: AppColors.green)))),
        SizedBox(width: 180, child: Padding(padding: const EdgeInsets.all(5),
          child: widget.isSubmitted
              ? _roCell(_mats.firstWhere((m) => m.id == _matId,
              orElse: () => RefiningMaterialOption(id: '', name: '—')).name, 170)
              : SearchableDropdown<String>(
            value: _matId.isNotEmpty ? _matId : null,
            items: _mats.map((m) => m.id).toList(),
            displayString: (id) => _mats.firstWhere(
                  (m) => m.id == id,
              orElse: () => RefiningMaterialOption(id: '', name: '—'),
            ).name,
            hint: 'Select…',
            onChanged: (v) {
              setState(() => _matId = v ?? '');
              widget.onRecalc();
            },
          ),
        )),
        SizedBox(width: 130, child: Padding(padding: const EdgeInsets.all(5),
          child: GestureDetector(
            onTap: widget.onQtyTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _qtyCtrl.text.isNotEmpty
                    ? const Color(0xFFD1FAE5) : AppColors.greenXLight,
                border: Border.all(
                    color: _qtyCtrl.text.isNotEmpty
                        ? AppColors.green : AppColors.border, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                Expanded(child: Text(
                  _qtyCtrl.text.isNotEmpty
                      ? '${_qtyCtrl.text} KG'
                      : widget.isSubmitted ? '—' : 'Click…',
                  style: GoogleFonts.outfit(fontSize: 11.5,
                      color: _qtyCtrl.text.isNotEmpty
                          ? AppColors.textDark : AppColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                )),
                if (!widget.isSubmitted)
                  const Icon(Icons.keyboard_arrow_down, size: 12,
                      color: AppColors.textMuted),
              ]),
            ),
          ),
        )),
        SizedBox(width: 36, child: Center(child: widget.canDelete
            ? _delBtn(widget.onRemove!) : const SizedBox.shrink())),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Consumption Section
// Table layout: row labels × 3 column groups (LPG | Electricity | Liquid O2)
// ─────────────────────────────────────────────
class _ConsumptionSection extends StatelessWidget {
  final TextEditingController lpgInitCtrl, lpgFinalCtrl;
  final String lpgConsumed;
  final TextEditingController elecInitCtrl, elecFinalCtrl;
  final String elecConsumed;
  final TextEditingController o2Nm3Ctrl, o2TimeCtrl;
  final double? o2FlowKg, o2Consumption;
  final bool isSubmitted;
  final ValueChanged<String> onLpgChanged, onElecChanged, onO2Changed;

  const _ConsumptionSection({
    required this.lpgInitCtrl, required this.lpgFinalCtrl, required this.lpgConsumed,
    required this.elecInitCtrl, required this.elecFinalCtrl, required this.elecConsumed,
    required this.o2Nm3Ctrl, required this.o2FlowKg,
    required this.o2TimeCtrl, required this.o2Consumption,
    required this.isSubmitted,
    required this.onLpgChanged, required this.onElecChanged, required this.onO2Changed,
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
            const Icon(Icons.show_chart, size: 15, color: AppColors.green),
            const SizedBox(width: 8),
            Text('CONSUMPTION', style: AppTextStyles.label(color: AppColors.green)),
          ]),
        ),
        // Column headers
        Container(
          decoration: const BoxDecoration(color: AppColors.greenLight,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 2))),
          child: Row(children: [
            _ch('', 130),
            _ch('LPG', 160, icon: Icons.local_fire_department_outlined),
            _ch('Electricity', 160, icon: Icons.bolt_outlined),
            Expanded(child: _ch('Liquid Oxygen', double.infinity,
                icon: Icons.water_drop_outlined)),
          ]),
        ),
        // Row: Initial
        _ConsRow(
          label: 'Initial',
          lpg:   _numField(lpgInitCtrl, isSubmitted, onChanged: onLpgChanged),
          elec:  _numField(elecInitCtrl, isSubmitted, onChanged: onElecChanged),
          o2: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _subLabel('FLOW (NM³)', badge: 'MANUAL', badgeColor: const Color(0xFF0369A1),
                  badgeBg: const Color(0xFFE0F2FE)),
              _numField(o2Nm3Ctrl, isSubmitted, onChanged: onO2Changed),
            ])),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _subLabel('FLOW (KG)', badge: 'AUTO', badgeColor: const Color(0xFF166534),
                  badgeBg: const Color(0xFFDCFCE7), note: '= NM³ × 1.429'),
              _roNumDisplay(o2FlowKg),
            ])),
          ]),
        ),
        // Row: Final
        _ConsRow(
          label: 'Final',
          lpg:   _numField(lpgFinalCtrl, isSubmitted, onChanged: onLpgChanged),
          elec:  _numField(elecFinalCtrl, isSubmitted, onChanged: onElecChanged),
          o2: SizedBox(width: 160, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _subLabel('FLOW TIME (HR)', badge: 'MANUAL', badgeColor: const Color(0xFF0369A1),
                  badgeBg: const Color(0xFFE0F2FE)),
              _numField(o2TimeCtrl, isSubmitted, onChanged: onO2Changed),
            ],
          )),
        ),
        // Row: Consumption totals
        Container(
          decoration: const BoxDecoration(color: AppColors.greenLight,
              border: Border(top: BorderSide(color: AppColors.border, width: 2))),
          child: Row(children: [
            SizedBox(width: 130, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text('CONSUMPTION', style: AppTextStyles.label(color: AppColors.green)),
            )),
            SizedBox(width: 160, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: _consTotal(lpgConsumed),
            )),
            SizedBox(width: 160, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: _consTotal(elecConsumed),
            )),
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _subLabel('CONSUMPTION (KG)', badge: 'AUTO', badgeColor: const Color(0xFF166534),
                    badgeBg: const Color(0xFFDCFCE7), note: '= Time × Flow(KG)'),
                const SizedBox(height: 6),
                _roNumDisplay(o2Consumption),
              ]),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _ch(String label, double width, {IconData? icon}) {
    final content = Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[
        Icon(icon, size: 13, color: AppColors.green),
        const SizedBox(width: 5),
      ],
      Text(label.toUpperCase(), style: AppTextStyles.label(color: AppColors.green)),
    ]);
    if (width == double.infinity) {
      return Padding(padding: const EdgeInsets.all(12), child: content);
    }
    return SizedBox(width: width, child: Padding(padding: const EdgeInsets.all(12), child: content));
  }

  static Widget _subLabel(String label, {required String badge,
    required Color badgeColor, required Color badgeBg, String? note}) =>
      Wrap(spacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700,
                color: AppColors.textMuted, letterSpacing: 0.5)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(3)),
          child: Text(badge, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
              color: badgeColor)),
        ),
        if (note != null)
          Text(note, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
      ]);

  static Widget _numField(TextEditingController ctrl, bool ro,
      {ValueChanged<String>? onChanged}) =>
      TextField(
        controller: ctrl, readOnly: ro, onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: ro ? null : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textDark),
        decoration: InputDecoration(
          isDense: true, filled: true, fillColor: AppColors.greenXLight,
          hintText: '0.000',
          hintStyle: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
        ),
      );

  static Widget _roNumDisplay(double? value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(color: const Color(0xFFEEF6F1),
        border: Border.all(color: const Color(0xFFC8DFD1), width: 1.5),
        borderRadius: BorderRadius.circular(8)),
    child: Text(
      value != null ? value.toStringAsFixed(3) : 'Auto',
      style: GoogleFonts.outfit(fontSize: 13, color: AppColors.green,
          fontWeight: FontWeight.w600),
    ),
  );

  static Widget _consTotal(String text) {
    final isDash = text == '—';
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('TOTAL', style: AppTextStyles.label(color: AppColors.green)),
      Text(text, style: GoogleFonts.outfit(
        fontSize: isDash ? 14 : 15,
        fontWeight: FontWeight.w700,
        color: isDash ? AppColors.textMuted : AppColors.green,
      )),
    ]);
  }
}

class _ConsRow extends StatelessWidget {
  final String label;
  final Widget lpg, elec, o2;
  const _ConsRow({required this.label, required this.lpg,
    required this.elec, required this.o2});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight))),
    child: Row(children: [
      Container(width: 130, color: AppColors.greenXLight, padding:
      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(label.toUpperCase(),
            style: AppTextStyles.label()),
      ),
      SizedBox(width: 160, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: lpg)),
      SizedBox(width: 160, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: elec)),
      Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: o2)),
    ]),
  );
}

// ─────────────────────────────────────────────
// Process Table (dynamic rows, process names from API)
// ─────────────────────────────────────────────
class _ProcessTable extends StatelessWidget {
  final List<_ProcRow> rows;
  final int totalProcMins;
  final bool isSubmitted;
  final List<String> processNames;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemove;
  final ValueChanged<int> onCalcTime;
  final void Function(int, String)? onSetNow;
  final void Function(int, String)? onPickTime;

  const _ProcessTable({
    required this.rows, required this.totalProcMins, required this.isSubmitted,
    required this.processNames, required this.onAdd, required this.onRemove,
    required this.onCalcTime, required this.onSetNow, required this.onPickTime,
  });

  @override
  Widget build(BuildContext context) {
    final h = totalProcMins ~/ 60;
    final m = totalProcMins % 60;
    final totalStr = totalProcMins > 0
        ? (h > 0 ? '${h}h ${m}min' : '${m} min') : '';

    return MesCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHead('Process Details', Icons.schedule_outlined, onAdd),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(children: [
            Container(
              decoration: const BoxDecoration(color: AppColors.greenLight,
                  border: Border(bottom: BorderSide(color: AppColors.border, width: 2))),
              child: Row(children: [
                _ph('Process',     180),
                _ph('Start',       110, center: true),
                _ph('',             44),
                _ph('End',         110, center: true),
                _ph('',             44),
                _ph('Total Time',   90),
                _ph('',             36),
              ]),
            ),
            ...rows.asMap().entries.map((e) => _ProcTblRow(
              index: e.key, row: e.value, isSubmitted: isSubmitted,
              processNames: processNames,
              onSetNow: onSetNow, onPickTime: onPickTime,
              onCalcTime: onCalcTime,
            )),
            Container(
              decoration: const BoxDecoration(color: AppColors.greenLight,
                  border: Border(top: BorderSide(color: AppColors.border, width: 2))),
              child: Row(children: [
                SizedBox(width: 180 + 110 + 44 + 110 + 44, child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Align(alignment: Alignment.centerRight,
                      child: Text('TOTAL PROCESS TIME',
                          style: AppTextStyles.label(color: AppColors.green))),
                )),
                SizedBox(width: 90 + 36, child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Text(totalStr, style: GoogleFonts.outfit(fontSize: 12.5,
                      fontWeight: FontWeight.w700, color: AppColors.green)),
                )),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _ph(String label, double w, {bool center = false}) => SizedBox(
    width: w,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Align(alignment: center ? Alignment.center : Alignment.centerLeft,
          child: Text(label.toUpperCase(),
              style: AppTextStyles.label(color: AppColors.green))),
    ),
  );
}

class _ProcTblRow extends StatefulWidget {
  final int index;
  final _ProcRow row;
  final bool isSubmitted;
  final List<String> processNames;
  final void Function(int, String)? onSetNow;
  final void Function(int, String)? onPickTime;
  final ValueChanged<int> onCalcTime;

  const _ProcTblRow({
    required this.index, required this.row, required this.isSubmitted,
    required this.processNames, required this.onSetNow, required this.onPickTime,
    required this.onCalcTime,
  });

  @override
  State<_ProcTblRow> createState() => _ProcTblRowState();
}

class _ProcTblRowState extends State<_ProcTblRow> {
  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final ro  = widget.isSubmitted;

    Widget timeInput(TextEditingController ctrl, String which) =>
        GestureDetector(
          onTap: ro ? null : () => widget.onPickTime?.call(widget.index, which),
          child: AbsorbPointer(absorbing: ro, child: TextField(
            controller: ctrl, readOnly: ro,
            style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textDark),
            decoration: InputDecoration(
              hintText: '--:--',
              hintStyle: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
              isDense: true, filled: true, fillColor: AppColors.greenXLight,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
            ),
          )),
        );

    Widget nowBtn(Color bg, String label, String which) => ro
        ? const SizedBox(width: 44)
        : SizedBox(width: 44, child: Center(child: GestureDetector(
      onTap: () => widget.onSetNow?.call(widget.index, which),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
        child: Text(label, style: GoogleFonts.outfit(fontSize: 9,
            fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    )));

    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderLight))),
      child: Row(children: [
        SizedBox(width: 180, child: Padding(padding: const EdgeInsets.all(5),
          child: ro
              ? _roCell(row.processName, 170)
              : SearchableDropdown<String>(
            value: row.processName.isNotEmpty ? row.processName : null,
            items: widget.processNames,
            displayString: (item) => item,
            hint: 'Select process…',
            onChanged: (v) => setState(() => row.processName = v ?? ''),
          ),
        )),
        SizedBox(width: 110, child: Padding(padding: const EdgeInsets.all(5),
            child: timeInput(row.startCtrl, 'start'))),
        nowBtn(const Color(0xFF16A34A), 'START', 'start'),
        SizedBox(width: 110, child: Padding(padding: const EdgeInsets.all(5),
            child: timeInput(row.endCtrl, 'end'))),
        nowBtn(const Color(0xFFDC2626), 'END', 'end'),
        SizedBox(width: 90, child: Padding(padding: const EdgeInsets.all(5),
          child: _tblInput(controller: row.totalCtrl, readOnly: true,
              calcStyle: true, hint: '0 min'),
        )),
        SizedBox(width: 36, child: Center(child: (widget.row.processName.isNotEmpty || !ro)
            ? _delBtn(() {}) : const SizedBox.shrink())),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Output table (shared for FG + Dross)
// ─────────────────────────────────────────────
class _OutputTable extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_OutputRow> rows;
  final double total;
  final bool isSubmitted;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemove;
  final ValueChanged<int>? onQtyTap;
  final VoidCallback onRecalc;

  const _OutputTable({
    required this.title, required this.icon, required this.rows,
    required this.total, required this.isSubmitted,
    required this.onAdd, required this.onRemove,
    required this.onQtyTap, required this.onRecalc,
  });

  @override
  Widget build(BuildContext context) {
    return MesCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHead(title, icon, onAdd),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(children: [
            _tblHeader(['#', 'Material', 'QTY (KG)', ''], [36, 180, 130, 36]),
            ...rows.asMap().entries.map((e) => _OutputTblRow(
              index: e.key, row: e.value, isSubmitted: isSubmitted,
              canDelete: rows.length > 1 && !isSubmitted,
              onQtyTap: onQtyTap == null ? null : () => onQtyTap!(e.key),
              onRemove: onRemove == null ? null : () => onRemove!(e.key),
              onRecalc: onRecalc,
            )),
            _tblFooter([
              (36 + 180.0, 'TOTAL', true),
              (130.0, total > 0 ? total.toStringAsFixed(3) : '', false),
              (36.0, '', false),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _OutputTblRow extends StatefulWidget {
  final int index;
  final _OutputRow row;
  final bool isSubmitted, canDelete;
  final VoidCallback? onQtyTap, onRemove;
  final VoidCallback onRecalc;

  const _OutputTblRow({
    required this.index, required this.row, required this.isSubmitted,
    required this.canDelete, required this.onQtyTap, required this.onRemove,
    required this.onRecalc,
  });

  @override
  State<_OutputTblRow> createState() => _OutputTblRowState();
}

class _OutputTblRowState extends State<_OutputTblRow> {
  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderLight))),
      child: Row(children: [
        SizedBox(width: 36, child: Center(child: Text('${widget.index + 1}',
            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700,
                color: AppColors.green)))),
        SizedBox(width: 180, child: Padding(padding: const EdgeInsets.all(5),
          child: widget.isSubmitted
              ? _roCell(row.materials.firstWhere((m) => m.id == row.materialId,
              orElse: () => RefiningMaterialOption(id: '', name: '—')).name, 170)
              : SearchableDropdown<String>(
            value: row.materialId.isNotEmpty ? row.materialId : null,
            items: row.materials.map((m) => m.id).toList(),
            displayString: (id) => row.materials.firstWhere(
                  (m) => m.id == id,
              orElse: () => RefiningMaterialOption(id: '', name: '—'),
            ).name,
            hint: 'Select…',
            onChanged: (v) {
              setState(() {
                row.materialId = v ?? '';
                row.outputBlocks = [];
                row.qtyCtrl.text = '';
              });
              widget.onRecalc();
            },
          ),
        )),
        SizedBox(width: 130, child: Padding(padding: const EdgeInsets.all(5),
          child: GestureDetector(
            onTap: widget.onQtyTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: row.qtyCtrl.text.isNotEmpty
                    ? const Color(0xFFD1FAE5) : AppColors.greenXLight,
                border: Border.all(color: row.qtyCtrl.text.isNotEmpty
                    ? AppColors.green : AppColors.border, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                Expanded(child: Text(
                  row.qtyCtrl.text.isNotEmpty
                      ? '${row.qtyCtrl.text} KG'
                      : widget.isSubmitted ? '—' : 'Enter blocks…',
                  style: GoogleFonts.outfit(fontSize: 11.5,
                      color: row.qtyCtrl.text.isNotEmpty
                          ? AppColors.textDark : AppColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                )),
                if (!widget.isSubmitted)
                  const Icon(Icons.keyboard_arrow_down, size: 12,
                      color: AppColors.textMuted),
              ]),
            ),
          ),
        )),
        SizedBox(width: 36, child: Center(child: widget.canDelete
            ? _delBtn(widget.onRemove!) : const SizedBox.shrink())),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Smelting Lot Modal
// ─────────────────────────────────────────────
class _SmeltingLotModal extends StatefulWidget {
  final String materialName;
  final List<RefiningSmeltingLot> lots;
  final bool isOffline;
  final List<SmeltingSelection> existingSelections;
  final ValueChanged<List<SmeltingSelection>> onConfirm;

  const _SmeltingLotModal({
    required this.materialName, required this.lots, required this.isOffline,
    required this.existingSelections, required this.onConfirm,
  });

  @override
  State<_SmeltingLotModal> createState() => _SmeltingLotModalState();
}

class _SmeltingLotModalState extends State<_SmeltingLotModal> {
  late final Map<String, TextEditingController> _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = {};
    for (final lot in widget.lots) {
      final existing = widget.existingSelections.firstWhere(
              (s) => s.smtId == lot.smeltingBatchId,
          orElse: () => SmeltingSelection(smtId: '', smtNo: '', qty: 0));
      _ctrl[lot.smeltingBatchId] = TextEditingController(
          text: existing.qty > 0 ? existing.qty.toStringAsFixed(3) : '');
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) c.dispose();
    super.dispose();
  }

  double get _total =>
      _ctrl.values.fold(0, (s, c) => s + (double.tryParse(c.text) ?? 0));

  void _confirm() {
    final sels = <SmeltingSelection>[];
    for (final lot in widget.lots) {
      final qty = double.tryParse(_ctrl[lot.smeltingBatchId]?.text ?? '') ?? 0;
      if (qty > 0) {
        sels.add(SmeltingSelection(
            smtId: lot.smeltingBatchId, smtNo: lot.batchNo, qty: qty));
      }
    }
    widget.onConfirm(sels);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7, maxChildSize: 0.92, minChildSize: 0.4,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        child: Column(children: [
          Center(child: Container(margin: const EdgeInsets.only(top: 10),
              width: 36, height: 4, decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)))),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: const BoxDecoration(color: AppColors.greenLight,
                border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              const Icon(Icons.factory_outlined, size: 16, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Select Smelting Batch',
                    style: AppTextStyles.subheading(color: AppColors.green)),
                Text('Material: ${widget.materialName}',
                    style: AppTextStyles.caption()),
              ])),
              GestureDetector(onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, size: 18, color: AppColors.textMuted)),
            ]),
          ),

          if (widget.isOffline)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B))),
              child: Row(children: [
                const Icon(Icons.wifi_off, size: 14, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(child: Text('You are offline. Showing cached smelting data.',
                    style: GoogleFonts.outfit(fontSize: 11.5,
                        color: const Color(0xFF92400E)))),
              ]),
            ),

          if (widget.lots.isEmpty)
            Expanded(child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.inbox_outlined, size: 48, color: AppColors.borderLight),
                const SizedBox(height: 12),
                Text('No submitted smelting batches found for this material.',
                    style: AppTextStyles.caption()),
              ],
            )))
          else ...[
            Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Text('Enter the quantity to assign from each smelting batch.',
                    style: AppTextStyles.caption())),
            Expanded(child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(children: [
                Container(
                  decoration: const BoxDecoration(color: AppColors.greenLight,
                      border: Border(bottom: BorderSide(color: AppColors.border, width: 2))),
                  child: Row(children: [
                    _mth('Batch No', 130), _mth('Material', 160),
                    _mth('Unit', 60), _mth('Available', 120), _mth('Assign Qty', 120),
                  ]),
                ),
                ...widget.lots.map((lot) {
                  final isZero = lot.availableQty <= 0;
                  return StatefulBuilder(builder: (_, ss) => Container(
                    decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.borderLight))),
                    child: Row(children: [
                      SizedBox(width: 130, child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.greenLight,
                              borderRadius: BorderRadius.circular(5)),
                          child: Text(lot.batchNo, style: GoogleFonts.outfit(fontSize: 11,
                              fontWeight: FontWeight.w700, color: AppColors.green),
                              overflow: TextOverflow.ellipsis),
                        ),
                      )),
                      SizedBox(width: 160, child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        child: Text(lot.secondaryName, style: GoogleFonts.outfit(
                            fontSize: 12.5, fontWeight: FontWeight.w600,
                            color: AppColors.textDark), overflow: TextOverflow.ellipsis),
                      )),
                      SizedBox(width: 60, child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        child: Text(lot.materialUnit, style: AppTextStyles.body()),
                      )),
                      SizedBox(width: 120, child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: isZero ? const Color(0xFFFEE2E2)
                                : lot.availableQty < 50 ? const Color(0xFFFEF9C3)
                                : const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('${lot.availableQty.toStringAsFixed(3)}',
                              style: GoogleFonts.outfit(fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isZero ? const Color(0xFF991B1B)
                                      : lot.availableQty < 50 ? const Color(0xFF854D0E)
                                      : const Color(0xFF065F46))),
                        ),
                      )),
                      SizedBox(width: 120, child: Padding(padding: const EdgeInsets.all(5),
                        child: TextField(
                          controller: _ctrl[lot.smeltingBatchId],
                          enabled: !isZero,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          onChanged: (v) {
                            final val = double.tryParse(v) ?? 0;
                            if (val > lot.availableQty) {
                              _ctrl[lot.smeltingBatchId]!.text =
                                  lot.availableQty.toStringAsFixed(3);
                            }
                            ss(() {}); setState(() {});
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
                  ));
                }),
                // Total row
                Container(
                  decoration: const BoxDecoration(color: AppColors.greenLight,
                      border: Border(top: BorderSide(color: AppColors.border, width: 2))),
                  child: Row(children: [
                    SizedBox(width: 130 + 160 + 60 + 120, child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Align(alignment: Alignment.centerRight,
                          child: Text('TOTAL ASSIGN QTY',
                              style: AppTextStyles.label(color: AppColors.green))),
                    )),
                    SizedBox(width: 120, child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Row(children: [
                        Text(_total.toStringAsFixed(3), style: GoogleFonts.outfit(
                            fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.green)),
                        const SizedBox(width: 4),
                        Text('KG', style: AppTextStyles.caption()),
                      ]),
                    )),
                  ]),
                ),
              ]),
            )),
          ],

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderLight))),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              MesOutlineButton(label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: 12),
              MesButton(label: 'OK', icon: Icons.check,
                  onPressed: _total > 0 ? _confirm : null),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _mth(String label, double w) => SizedBox(width: w, child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    child: Text(label.toUpperCase(), style: AppTextStyles.label(color: AppColors.green)),
  ));
}

// ─────────────────────────────────────────────
// Output Block Modal (shared for FG + Dross)
// Up to 11 rows by default, expandable with ADD button
// ─────────────────────────────────────────────
class _OutputBlockModal extends StatefulWidget {
  final String title, materialName;
  final List<double> blocks;
  final ValueChanged<List<double>> onConfirm;

  const _OutputBlockModal({
    required this.title, required this.materialName,
    required this.blocks, required this.onConfirm,
  });

  @override
  State<_OutputBlockModal> createState() => _OutputBlockModalState();
}

class _OutputBlockModalState extends State<_OutputBlockModal> {
  static const int _minRows = 11;
  late List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    final count = widget.blocks.length.clamp(_minRows, 100);
    _ctrls = List.generate(count, (i) {
      final v = i < widget.blocks.length && widget.blocks[i] > 0
          ? widget.blocks[i].toStringAsFixed(3) : '';
      return TextEditingController(text: v);
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  double get _total =>
      _ctrls.fold(0, (s, c) => s + (double.tryParse(c.text) ?? 0));

  void _addRow() {
    setState(() => _ctrls.add(TextEditingController()));
  }

  void _confirm() {
    final blocks = _ctrls.map((c) => double.tryParse(c.text) ?? 0).toList();
    widget.onConfirm(blocks);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.5,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        child: Column(children: [
          Center(child: Container(margin: const EdgeInsets.only(top: 10),
              width: 36, height: 4, decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)))),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: const BoxDecoration(color: AppColors.greenLight,
                border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              const Icon(Icons.view_list_outlined, size: 16, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: AppTextStyles.subheading(color: AppColors.green)),
                if (widget.materialName.isNotEmpty)
                  Text('Material: ${widget.materialName}',
                      style: AppTextStyles.caption()),
              ])),
              GestureDetector(onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, size: 18, color: AppColors.textMuted)),
            ]),
          ),
          Expanded(child: ListView.builder(
            controller: scrollCtrl,
            itemCount: _ctrls.length,
            itemBuilder: (ctx, i) => Container(
              decoration: BoxDecoration(
                color: i.isOdd ? AppColors.greenXLight : AppColors.white,
                border: const Border(bottom: BorderSide(color: AppColors.borderLight)),
              ),
              child: Row(children: [
                Container(
                  width: 80, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: const BoxDecoration(
                    color: AppColors.greenXLight,
                    border: Border(right: BorderSide(color: AppColors.borderLight)),
                  ),
                  child: Align(alignment: Alignment.centerRight,
                      child: Text('${i + 1}', style: GoogleFonts.outfit(fontSize: 12.5,
                          fontWeight: FontWeight.w700, color: AppColors.green))),
                ),
                Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: TextField(
                    controller: _ctrls[i],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    textAlign: TextAlign.right,
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textDark),
                    decoration: InputDecoration(
                      hintText: '0.000',
                      hintStyle: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
                      isDense: true, filled: true, fillColor: Colors.transparent,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                )),
              ]),
            ),
          )),
          // Total
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: const BoxDecoration(color: AppColors.greenLight,
                border: Border(top: BorderSide(color: AppColors.border, width: 2),
                    bottom: BorderSide(color: AppColors.border))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('TOTAL', style: AppTextStyles.label(color: AppColors.green)),
              Row(children: [
                Text(_total.toStringAsFixed(3), style: GoogleFonts.outfit(
                    fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.green)),
                const SizedBox(width: 4),
                Text('KG', style: AppTextStyles.caption()),
              ]),
            ]),
          ),
          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              MesOutlineButton(label: 'ADD', icon: Icons.add, onPressed: _addRow),
              Row(children: [
                MesOutlineButton(label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
                MesButton(label: 'OK', icon: Icons.check, onPressed: _confirm),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Small UI helpers
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

class _LockedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: const Color(0xFFFEF3C7),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
        borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      const Icon(Icons.lock_outline, size: 18, color: Color(0xFF92400E)),
      const SizedBox(width: 10),
      Expanded(child: Text('🔒 This batch has been submitted and is locked from editing.',
          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600,
              color: const Color(0xFF92400E)))),
    ]),
  );
}

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFF59E0B))),
    child: Row(children: [
      const Icon(Icons.wifi_off, size: 16, color: Color(0xFFF59E0B)),
      const SizedBox(width: 8),
      Expanded(child: Text('You are offline. Record will sync when connection restores.',
          style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF92400E)))),
    ]),
  );
}

class _SubmitBtn extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;
  const _SubmitBtn({required this.isLoading, required this.onPressed});

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
          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600,
              color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1D4ED8),
        disabledBackgroundColor: const Color(0xFF1D4ED8).withOpacity(0.5),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// File-level table helpers
// ─────────────────────────────────────────────
Widget _cardHead(String title, IconData icon, VoidCallback? onAdd) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(color: AppColors.greenLight,
          border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        Icon(icon, size: 15, color: AppColors.green),
        const SizedBox(width: 8),
        Text(title.toUpperCase(), style: AppTextStyles.label(color: AppColors.green)),
        const Spacer(),
        if (onAdd != null)
          GestureDetector(onTap: onAdd, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.green,
                borderRadius: BorderRadius.circular(7)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add, size: 13, color: Colors.white),
              const SizedBox(width: 4),
              Text('Add', style: GoogleFonts.outfit(fontSize: 12,
                  fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          )),
      ]),
    );

Widget _tblHeader(List<String> labels, List<double> widths) =>
    Container(
      decoration: const BoxDecoration(color: AppColors.greenLight,
          border: Border(bottom: BorderSide(color: AppColors.border, width: 2))),
      child: Row(children: List.generate(labels.length, (i) => SizedBox(
        width: widths[i],
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Text(labels[i].toUpperCase(),
                style: AppTextStyles.label(color: AppColors.green))),
      ))),
    );

Widget _tblFooter(List<(double, String, bool)> cells) =>
    Container(
      decoration: const BoxDecoration(color: AppColors.greenLight,
          border: Border(top: BorderSide(color: AppColors.border, width: 2))),
      child: Row(children: cells.map((c) => SizedBox(width: c.$1, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Align(alignment: c.$3 ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(c.$2, style: GoogleFonts.outfit(fontSize: 12.5,
                fontWeight: FontWeight.w700, color: AppColors.green))),
      ))).toList()),
    );

Widget _tblInput({required TextEditingController controller, String hint = '',
  bool readOnly = false, bool numeric = false, bool calcStyle = false,
  ValueChanged<String>? onChanged}) =>
    TextField(
      controller: controller, readOnly: readOnly, onChanged: onChanged,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      inputFormatters: numeric && !readOnly
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
      style: GoogleFonts.outfit(fontSize: 12.5,
        color: calcStyle ? AppColors.green : AppColors.textDark,
        fontWeight: calcStyle ? FontWeight.w600 : FontWeight.w400,
      ),
      decoration: InputDecoration(
        hintText: hint, hintStyle: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
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

Widget _roCell(String text, double width) => SizedBox(width: width, child: Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  decoration: BoxDecoration(color: const Color(0xFFF0F4F2),
      border: Border.all(color: AppColors.border, width: 1.5),
      borderRadius: BorderRadius.circular(6)),
  child: Text(text, style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textMuted),
      overflow: TextOverflow.ellipsis),
));

Widget _delBtn(VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(
  width: 26, height: 26,
  decoration: BoxDecoration(color: const Color(0xFFFEE2E2),
      borderRadius: BorderRadius.circular(5)),
  child: const Icon(Icons.delete_outline, size: 13, color: AppColors.error),
));

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