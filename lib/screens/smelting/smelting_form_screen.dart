// ─────────────────────────────────────────────────────────────────────────────
// smelting_form_screen.dart
//
// SECTION 1 — Primary Details (batch_no auto, date, rotary_no, start_time, end_time)
// SECTION 2 — Two-column: Raw Materials | Flux/Chemicals
//   Each row: material dropdown | QTY (tap → BBSU lot modal) | yield% | expected(auto)
//   BBSU lot modal: online = fresh API, offline = cached per materialId
// SECTION 3 — Two-column: Process Details (9 fixed) | Consumption + Output
//   Process: START/END buttons + time pickers + firing mode + total time (auto)
//   Consumption: LPG, O2, ID Fan, Rotary Power
//   Output: material dropdown + single qty field (simplified — no block modal)
// SECTION 4 — Temperature Records (dynamic rows)
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
import '../../models/smelting_model.dart';
import '../../services/smelting_service.dart';

class SmeltingFormScreen extends StatefulWidget {
  final String? recordId;
  final VoidCallback onLogout;

  const SmeltingFormScreen({
    super.key,
    this.recordId,
    required this.onLogout,
  });

  bool get isCreate => recordId == null;

  @override
  State<SmeltingFormScreen> createState() => _SmeltingFormScreenState();
}

class _SmeltingFormScreenState extends State<SmeltingFormScreen> {
  // ── Primary ────────────────────────────────────────────────────────────────
  final _batchNoCtrl = TextEditingController();
  final _dateCtrl    = TextEditingController();
  String _rotaryNo   = '';
  final _startCtrl   = TextEditingController();
  final _endCtrl     = TextEditingController();
  final _chargeCtrl  = TextEditingController();

  // ── Consumption ────────────────────────────────────────────────────────────
  final _lpgCtrl      = TextEditingController();
  final _o2Ctrl       = TextEditingController();
  final _idInitCtrl   = TextEditingController();
  final _idFinalCtrl  = TextEditingController();
  final _rotInitCtrl  = TextEditingController();
  final _rotFinalCtrl = TextEditingController();
  // Display strings for conversions
  String _lpgConverted = '0.00 LTR';
  String _o2Converted  = '0.00 KG';
  // Computed consumptions (read-only display)
  String _idConsumed  = '—';
  String _rotConsumed = '—';

  // ── Output (simplified — single qty field) ─────────────────────────────────
  List<SmeltingMaterialOption> _materials = [];
  String? _outputMaterialId;
  // final _outputQtyCtrl = TextEditingController();
  List<_OutputBlock> _outputBlocks = [];
  double get _outputTotalQty =>
      _outputBlocks.fold(0, (s, b) => s + b.weight);

  // ── Raw materials ──────────────────────────────────────────────────────────
  final List<_RawRow>  _rawRows  = [];
  final List<_FluxRow> _fluxRows = [];

  // ── Process rows (9 fixed) ─────────────────────────────────────────────────
  late final List<_ProcessRow> _processRows;

  // ── Temperature records ────────────────────────────────────────────────────
  final List<_TempRow> _tempRows = [];

  // ── Totals ─────────────────────────────────────────────────────────────────
  double _rawTotalQty      = 0;
  double _rawTotalExpected = 0;
  double _fluxTotalQty     = 0;
  String _totalBatchTime   = '0 min';

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _isLoading    = true;
  bool _isSaving     = false;
  bool _isSubmitting = false;
  bool _isSubmitted  = false;
  String? _currentId;
  bool _isPreloadingStock = false;

  @override
  void initState() {
    super.initState();
    _processRows = kSmeltingProcessNames
        .map((n) => _ProcessRow(n))
        .toList();
    _init();
  }

  @override
  void dispose() {
    _batchNoCtrl.dispose(); _dateCtrl.dispose();
    _startCtrl.dispose(); _endCtrl.dispose();
    _lpgCtrl.dispose(); _o2Ctrl.dispose();
    _idInitCtrl.dispose(); _idFinalCtrl.dispose();
    _rotInitCtrl.dispose(); _rotFinalCtrl.dispose();
    // _outputQtyCtrl.dispose(); _chargeCtrl.dispose();
    for (final b in _outputBlocks) b.dispose();
    for (final r in _rawRows)  r.dispose();
    for (final f in _fluxRows) f.dispose();
    for (final p in _processRows) p.dispose();
    for (final t in _tempRows) t.dispose();
    super.dispose();
  }
  void _initDefaultOutputBlocks() {
    _outputBlocks = List.generate(11, (i) => _OutputBlock(blockNo: i + 1));
  }
  String? _convertTo24Hour(String? time12hr) {
    if (time12hr == null || time12hr.isEmpty) return null;

    try {
      final parts = time12hr.trim().split(' ');
      if (parts.length != 2) return null;

      final timeParts = parts[0].split(':');
      if (timeParts.length != 2) return null;

      int hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final period = parts[1].toUpperCase();

      if (period == 'PM' && hour != 12) {
        hour += 12;
      } else if (period == 'AM' && hour == 12) {
        hour = 0;
      }

      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _openOutputBlockModal() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OutputBlockModal(
        initialBlocks: _outputBlocks,
        onConfirm: (blocks) {
          setState(() {
            for (final b in _outputBlocks) b.dispose();
            _outputBlocks = blocks;
          });
        },
      ),
    );
  }
  Future<void> _init() async {
    setState(() => _isLoading = true);
    _materials = await SmeltingService().getMaterials();

    if (widget.isCreate) {
      _dateCtrl.text    = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _batchNoCtrl.text = await SmeltingService().generateBatchNo();
      _addRawRow(); _addFluxRow(); _addTempRow(); _initDefaultOutputBlocks();
    } else {
      await _loadRecord();
    }
    setState(() => _isLoading = false);

    // Preload stock for all materials for offline usage.
      unawaited(_preloadAllStockForOffline());
  }

  Future<void> _preloadAllStockForOffline() async {
    if (!mounted || _isPreloadingStock) return;
    if (!ConnectivityService().isOnline || _materials.isEmpty) return;

    setState(() => _isPreloadingStock = true);
    try {
      await SmeltingService().preloadBbsuLotsForMaterials();
    } finally {
      if (mounted) {
        setState(() => _isPreloadingStock = false);
      } else {
        _isPreloadingStock = false;
      }
    }
  }

  Future<void> _loadRecord() async {
    final r = await SmeltingService().getOne(widget.recordId!);
    if (r == null) { _showSnack('Failed to load record.', error: true); return; }

    _currentId   = r.id;
    _isSubmitted = r.isSubmitted;

    _batchNoCtrl.text = r.batchNo;
    _dateCtrl.text    = r.date.length >= 10 ? r.date.substring(0, 10) : r.date;
    _rotaryNo         = r.rotaryNo;
    _startCtrl.text   = SmeltingService.toHHmm(r.startTime) ?? '';
    _endCtrl.text     = SmeltingService.toHHmm(r.endTime) ?? '';
    _chargeCtrl.text  = r.chargeNo ?? '';

    _lpgCtrl.text      = r.lpgConsumption?.toString() ?? '';
    _o2Ctrl.text       = r.o2Consumption?.toString() ?? '';
    _idInitCtrl.text   = r.idFanInitial?.toString() ?? '';
    _idFinalCtrl.text  = r.idFanFinal?.toString() ?? '';
    _rotInitCtrl.text  = r.rotaryPowerInitial?.toString() ?? '';
    _rotFinalCtrl.text = r.rotaryPowerFinal?.toString() ?? '';
    _calcLpg(); _calcO2();
    _calcConsumption('id'); _calcConsumption('rot');

    _outputMaterialId = r.outputMaterial;
    // _outputQtyCtrl.text = r.outputQty != null && r.outputQty! > 0
    //     ? r.outputQty!.toStringAsFixed(3) : '';
    // Load saved blocks, or fall back to 11 empty defaults
    if (r.outputBlocks != null && r.outputBlocks!.isNotEmpty) {
      _outputBlocks = r.outputBlocks!.asMap().entries.map((e) {
        final v = e.value['weight_kg'];
        final weight = (v is double) ? v : (v is int) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
        return _OutputBlock(blockNo: e.key + 1, weight: weight);
      }).toList();
    } else {
      _initDefaultOutputBlocks();
      if (r.outputQty != null && r.outputQty! > 0) {
        _outputBlocks[0].weightCtrl.text = r.outputQty!.toStringAsFixed(3);
      }
    }

    for (final rm in r.rawMaterials) _addRawRow(data: rm);
    if (r.rawMaterials.isEmpty) _addRawRow();

    for (final f in r.fluxChemicals) _addFluxRow(data: f);
    if (r.fluxChemicals.isEmpty) _addFluxRow();

    for (final pd in r.processDetails) {
      final idx = kSmeltingProcessNames.indexOf(pd.processName);
      if (idx >= 0) {
        _processRows[idx].startCtrl.text = SmeltingService.toHHmm(pd.startTime) ?? '';
        _processRows[idx].endCtrl.text   = SmeltingService.toHHmm(pd.endTime) ?? '';
        _processRows[idx].firingMode     = pd.firingMode ?? '';
        _calcProcessTime(idx);
      }
    }

    for (final t in r.temperatureRecords) _addTempRow(data: t);
    if (r.temperatureRecords.isEmpty) _addTempRow();

    _recalcRawTotals();
    _recalcFluxTotals();
  }

  // ── Row management ─────────────────────────────────────────────────────────
  void _addRawRow({SmeltingRawMaterial? data}) {
    _rawRows.add(_RawRow(
      materials: _materials, materialId: data?.rawMaterialId ?? '',
      bbsuSelections: data?.bbsuSelections ?? [],
      qty: data?.rawMaterialQty ?? 0,
      yieldPct: data?.rawMaterialYieldPct ?? 0,
      expected: data?.expectedOutputQty ?? 0,
    ));
    _recalcRawTotals();
    if (!_isLoading) setState(() {});
  }

  void _removeRawRow(int i) {
    if (_rawRows.length <= 1) return;
    setState(() { _rawRows[i].dispose(); _rawRows.removeAt(i); });
    _recalcRawTotals();
  }

  void _recalcRawTotals() {
    double tQty = 0, tExp = 0;
    for (final r in _rawRows) {
      tQty += double.tryParse(r.qtyCtrl.text) ?? 0;
      tExp += double.tryParse(r.expCtrl.text) ?? 0;
    }
    setState(() { _rawTotalQty = tQty; _rawTotalExpected = tExp; });
  }

  void _calcRawExpected(int i) {
    final qty   = double.tryParse(_rawRows[i].qtyCtrl.text) ?? 0;
    final yield_ = double.tryParse(_rawRows[i].yieldCtrl.text) ?? 0;
    _rawRows[i].expCtrl.text =
    yield_ > 0 ? (qty * yield_ / 100).toStringAsFixed(3) : '';
    _recalcRawTotals();
  }

  void _addFluxRow({SmeltingFluxChemical? data}) {
    _fluxRows.add(_FluxRow(
      materials: _materials, materialId: data?.chemicalId ?? '',
      bbsuSelections: data?.bbsuSelections ?? [],
      qty: data?.qty ?? 0,
    ));
    _recalcFluxTotals();
    if (!_isLoading) setState(() {});
  }

  void _removeFluxRow(int i) {
    if (_fluxRows.length <= 1) return;
    setState(() { _fluxRows[i].dispose(); _fluxRows.removeAt(i); });
    _recalcFluxTotals();
  }

  void _recalcFluxTotals() {
    double t = 0;
    for (final f in _fluxRows) t += double.tryParse(f.qtyCtrl.text) ?? 0;
    setState(() => _fluxTotalQty = t);
  }

  void _addTempRow({SmeltingTempRecord? data}) {
    _tempRows.add(_TempRow(
      time:     SmeltingService.toHHmm(data?.recordTime) ?? '',
      inside:   data?.insideTempBeforeCharging?.toString() ?? '',
      pgc:      data?.processGasChamberTemp ?? '',
      shell:    data?.shellTemp ?? '',
      bagHouse: data?.bagHouseTemp ?? '',
    ));
    if (!_isLoading) setState(() {});
  }

  void _removeTempRow(int i) {
    if (_tempRows.length <= 1) return;
    setState(() { _tempRows[i].dispose(); _tempRows.removeAt(i); });
  }

  // ── Process time ────────────────────────────────────────────────────────────
  void _calcProcessTime(int idx) {
    final r = _processRows[idx];
    final s = r.startCtrl.text;
    final e = r.endCtrl.text;
    if (s.isNotEmpty && e.isNotEmpty) {
      try {
        // Parse 12-hour format like "2:30 PM"
        int getMinutesFrom12Hour(String timeStr) {
          final parts = timeStr.split(' ');
          if (parts.length != 2) return 0;

          final timeParts = parts[0].split(':');
          int hour = int.parse(timeParts[0]);
          final minute = int.parse(timeParts[1]);
          final period = parts[1];

          if (period == 'PM' && hour != 12) {
            hour += 12;
          } else if (period == 'AM' && hour == 12) {
            hour = 0;
          }

          return hour * 60 + minute;
        }

        int startMins = getMinutesFrom12Hour(s);
        int endMins = getMinutesFrom12Hour(e);

        int m = endMins - startMins;
        if (m < 0) m += 1440;
        r.totalMins = m;
        r.totalCtrl.text = '${m} min';
      } catch (_) {}
    } else {
      r.totalMins = 0;
      r.totalCtrl.text = '';
    }
    _calcTotalBatchTime();
    setState(() {});
  }

  void _calcTotalBatchTime() {
    final total = _processRows.fold<int>(0, (s, r) => s + r.totalMins);
    final h = total ~/ 60;
    final m = total % 60;
    setState(() => _totalBatchTime = h > 0 ? '${h}h ${m}min' : '${m} min');
  }

  // ── Consumption calcs ───────────────────────────────────────────────────────
  void _calcLpg() {
    final v = double.tryParse(_lpgCtrl.text) ?? 0;
    setState(() => _lpgConverted =
    v > 0 ? '${(v * 4.2).toStringAsFixed(2)} LTR' : '0.00 LTR');
  }

  void _calcO2() {
    final v = double.tryParse(_o2Ctrl.text) ?? 0;
    setState(() => _o2Converted =
    v > 0 ? '${(v * 1.429).toStringAsFixed(2)} KG' : '0.00 KG');
  }

  void _calcConsumption(String which) {
    final init   = double.tryParse(
        which == 'id' ? _idInitCtrl.text : _rotInitCtrl.text) ?? 0;
    final final_ = double.tryParse(
        which == 'id' ? _idFinalCtrl.text : _rotFinalCtrl.text) ?? 0;
    final diff = final_ >= init ? final_ - init : null;
    final str  = diff != null ? diff.toStringAsFixed(3) : '—';
    setState(() {
      if (which == 'id') _idConsumed = str;
      else _rotConsumed = str;
    });
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
        // Parse 12-hour format
        final parts = ctrl.text.split(' ');
        if (parts.length == 2) {
          final timeParts = parts[0].split(':');
          final period = parts[1];
          int hour = int.parse(timeParts[0]);
          final minute = int.parse(timeParts[1]);

          if (period == 'PM' && hour != 12) {
            hour += 12;
          } else if (period == 'AM' && hour == 12) {
            hour = 0;
          }
          current = TimeOfDay(hour: hour, minute: minute);
        }
      } catch (_) {}
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.green,
              onPrimary: Colors.white,
            ),
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
            child: child!,
          ),
        );
      },
    );

    if (picked != null) {
      // Convert to 12-hour format
      int hour = picked.hour;
      final minute = picked.minute;
      final period = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      final time12hr = '$hour:${minute.toString().padLeft(2, '0')} $period';

      setState(() => ctrl.text = time12hr);
    }
  }

  // ── BBSU lot modal ──────────────────────────────────────────────────────────
  // Online: fetches fresh data + caches per materialId
  // Offline: reads from smelting_bbsu_lot_cache for that materialId
  Future<void> _openBbsuModal({
    required String materialId,
    required String materialName,
    required bool isRaw,
    required int rowIndex,
  }) async {
    if (materialId.isEmpty) {
      _showSnack('Please select a material first.', error: true);
      return;
    }

    // Brief loading snack
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        const SizedBox(width: 10),
        Text('Loading stock data…',
            style: GoogleFonts.outfit(fontSize: 13, color: Colors.white)),
      ]),
      backgroundColor: AppColors.green,
      duration: const Duration(milliseconds: 900),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      margin: const EdgeInsets.all(16),
    ));

    final lots = await SmeltingService().getBbsuLots(
      materialId,
      excludeSmeltingId: _currentId,
    );

    if (!mounted) return;

    final existing = isRaw
        ? _rawRows[rowIndex].bbsuSelections
        : _fluxRows[rowIndex].bbsuSelections;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BbsuLotModal(
        materialName:       materialName,
        lots:               lots,
        isOffline:          !ConnectivityService().isOnline,
        existingSelections: existing,
        onConfirm: (selections) {
          final totalQty = selections.fold<double>(0, (s, r) => s + r.qty);
          setState(() {
            if (isRaw) {
              _rawRows[rowIndex].bbsuSelections = selections;
              _rawRows[rowIndex].qtyCtrl.text   = totalQty.toStringAsFixed(3);
              _calcRawExpected(rowIndex);
            } else {
              _fluxRows[rowIndex].bbsuSelections = selections;
              _fluxRows[rowIndex].qtyCtrl.text   = totalQty.toStringAsFixed(3);
              _recalcFluxTotals();
            }
          });
        },
      ),
    );
  }

  // ── Build payload ────────────────────────────────────────────────────────────
  Map<String, dynamic>? _buildPayload() {
    if (_dateCtrl.text.isEmpty) {
      _showSnack('Date is required.', error: true); return null;
    }
    if (_rotaryNo.isEmpty) {
      _showSnack('Rotary No is required.', error: true); return null;
    }

    final date = _dateCtrl.text.trim();

    final rawMats = <Map<String, dynamic>>[];
    for (final r in _rawRows) {
      if (r.materialId.isEmpty) continue;
      rawMats.add({
        'raw_material_id':        r.materialId,
        'bbsu_batch_id':          r.bbsuSelections.isNotEmpty
            ? r.bbsuSelections.first.bbsuId : null,
        'bbsu_batch_no':          r.bbsuSelections.isNotEmpty
            ? r.bbsuSelections.first.bbsuNo : null,
        'bbsu_selections':        r.bbsuSelections.map((s) => s.toJson()).toList(),
        'raw_material_qty':       double.tryParse(r.qtyCtrl.text) ?? 0,
        'raw_material_yield_pct': double.tryParse(r.yieldCtrl.text) ?? 0,
        'expected_output_qty':    double.tryParse(r.expCtrl.text) ?? 0,
      });
    }

    final fluxChems = <Map<String, dynamic>>[];
    for (final f in _fluxRows) {
      if (f.materialId.isEmpty) continue;
      fluxChems.add({
        'chemical_id':    f.materialId,
        'bbsu_batch_id':  f.bbsuSelections.isNotEmpty
            ? f.bbsuSelections.first.bbsuId : null,
        'bbsu_batch_no':  f.bbsuSelections.isNotEmpty
            ? f.bbsuSelections.first.bbsuNo : null,
        'bbsu_selections': f.bbsuSelections.map((s) => s.toJson()).toList(),
        'qty':             double.tryParse(f.qtyCtrl.text) ?? 0,
      });
    }

    // Only include process rows with at least one time set
    final procDetails = <Map<String, dynamic>>[];
    for (int i = 0; i < _processRows.length; i++) {
      final p = _processRows[i];
      final s = p.startCtrl.text.trim();
      final e = p.endCtrl.text.trim();
      if (s.isEmpty && e.isEmpty) continue;
      procDetails.add({
        'process_name': p.processName,
        'start_time': _convertTo24Hour(s),
        'end_time': _convertTo24Hour(e),
        'total_time':   p.totalMins,
        'firing_mode':  p.firingMode.isNotEmpty ? p.firingMode : null,
      });
    }

    final tempRecs = _tempRows.map((t) => {
      'record_time': t.timeCtrl.text.isNotEmpty
          ? SmeltingService.toIsoDateTime(date, t.timeCtrl.text) : null,
      'inside_temp_before_charging': double.tryParse(t.insideCtrl.text),
      'process_gas_chamber_temp': t.pgcCtrl.text.trim().isNotEmpty
          ? t.pgcCtrl.text.trim() : null,
      'shell_temp': t.shellCtrl.text.trim().isNotEmpty
          ? t.shellCtrl.text.trim() : null,
      'bag_house_temp': t.bagCtrl.text.trim().isNotEmpty
          ? t.bagCtrl.text.trim() : null,
    }).toList();

    final idInit   = double.tryParse(_idInitCtrl.text);
    final idFin    = double.tryParse(_idFinalCtrl.text);
    final rotInit  = double.tryParse(_rotInitCtrl.text);
    final rotFin   = double.tryParse(_rotFinalCtrl.text);

    return {
      'batch_no':  _batchNoCtrl.text.trim(),
      'date':      date,
      'rotary_no': _rotaryNo,
      'charge_no': _chargeCtrl.text.trim(),
      'start_time': _convertTo24Hour(_startCtrl.text),
      'end_time': _convertTo24Hour(_endCtrl.text),
      'lpg_consumption':         double.tryParse(_lpgCtrl.text),
      'o2_consumption':          double.tryParse(_o2Ctrl.text),
      'id_fan_initial':          idInit,
      'id_fan_final':            idFin,
      'id_fan_consumption':      (idInit != null && idFin != null && idFin >= idInit)
          ? idFin - idInit : null,
      'rotary_power_initial':    rotInit,
      'rotary_power_final':      rotFin,
      'rotary_power_consumption': (rotInit != null && rotFin != null && rotFin >= rotInit)
          ? rotFin - rotInit : null,
      'output_material': _outputMaterialId,
      'output_qty':      _outputTotalQty > 0 ? _outputTotalQty : null,
      'output_blocks':   _outputBlocks
          .where((b) => b.weight > 0)
          .map((b) => {'block_no': b.blockNo, 'weight_kg': b.weight})
          .toList(),
      'raw_materials':       rawMats,
      'flux_chemicals':      fluxChems,
      'process_details':     procDetails,
      'temperature_records': tempRecs,
    };
  }

  // ── Save ─────────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final payload = _buildPayload();
    if (payload == null) return;
    setState(() => _isSaving = true);
    final result = await SmeltingService().save(payload, id: _currentId);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (result.success) {
      _showSnack('Record saved successfully.');
      if (widget.isCreate) {
        if (result.newId != null) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => SmeltingFormScreen(
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
    final error = await SmeltingService().submit(_currentId!);
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (error == null) {
      _showSnack('Batch submitted successfully.');
      Navigator.of(context).pop();
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

  // ── BUILD ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.hPad(context);

    return AppShell(
      currentRoute: '/smelting',
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
              if (_isSubmitted)
                _LockedBanner(),

              // Page header
              MesPageHeader(
                title: _isSubmitted
                    ? 'Smelting Batch (Submitted)'
                    : (widget.isCreate ? 'Create Smelting Batch' : 'Edit Smelting Batch'),
                subtitle: 'Record rotary furnace smelting batch log',
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

              // ══ SECTION 1 — Primary Details ════════════════════════════
              _SectionCard(
                icon: Icons.calendar_today_outlined,
                title: 'Primary Details',
                child: Column(children: [
                  Row(children: [
                    Expanded(child: MesTextField(label: 'Batch No',
                        controller: _batchNoCtrl, readOnly: true,
                        prefixIcon: Icons.description_outlined, badge: 'AUTO')),
                    const SizedBox(width: 16),
                    Expanded(child: GestureDetector(
                      onTap: _isSubmitted ? null : _pickDate,
                      child: AbsorbPointer(absorbing: _isSubmitted,
                          child: MesTextField(label: 'Date *',
                              controller: _dateCtrl, readOnly: true,
                              prefixIcon: Icons.calendar_today_outlined)),
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _DropField(
                      label: 'Rotary No *',
                      value: _rotaryNo.isNotEmpty ? _rotaryNo : null,
                      items: const [
                        DropdownMenuItem(value: '1', child: Text('Rotary 1')),
                        DropdownMenuItem(value: '2', child: Text('Rotary 2')),
                      ],
                      enabled: !_isSubmitted,
                      onChanged: (v) => setState(() => _rotaryNo = v ?? ''),
                    )),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: GestureDetector(
                      onTap: _isSubmitted ? null : () => _pickTime(_startCtrl),
                      child: AbsorbPointer(absorbing: true,
                          child: MesTextField(label: 'Start Time', controller: _startCtrl,
                              readOnly: true, prefixIcon: Icons.schedule_outlined)),
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: GestureDetector(
                      onTap: _isSubmitted ? null : () => _pickTime(_endCtrl),
                      child: AbsorbPointer(absorbing: true,
                          child: MesTextField(label: 'End Time', controller: _endCtrl,
                              readOnly: true, prefixIcon: Icons.schedule_outlined)),
                    )),
                    const SizedBox(width: 16),
                    Expanded(
                      child: MesTextField(
                        label: 'Charge no',
                        controller: _chargeCtrl,
                        prefixIcon: Icons.schedule_outlined,
                        // User can now type directly into this field
                      ),
                    )

                  ]),

                ]),
              ),

              const SizedBox(height: 16),

              // ══ SECTION 2 — Raw Materials + Flux ═══════════════════════
              LayoutBuilder(builder: (_, box) {
                final wide = box.maxWidth > 700;
                if (wide) {
                  const rawCardWidth = 555.0 + 32;
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: rawCardWidth,child: _RawCard(
                      rows: _rawRows, isSubmitted: _isSubmitted, materials: _materials,
                      totalQty: _rawTotalQty, totalExp: _rawTotalExpected,
                      onAdd: _isSubmitted ? null : _addRawRow,
                      onRemove: _isSubmitted ? null : _removeRawRow,
                      onQtyTap: _isSubmitted ? null : (i) async {
                        final r = _rawRows[i];
                        await _openBbsuModal(materialId: r.materialId,
                            materialName: r.materialName, isRaw: true, rowIndex: i);
                      },
                      onCalcExp: _calcRawExpected,
                      onRecalc: _recalcRawTotals,
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _FluxCard(
                      rows: _fluxRows, isSubmitted: _isSubmitted, materials: _materials,
                      totalQty: _fluxTotalQty,
                      onAdd: _isSubmitted ? null : _addFluxRow,
                      onRemove: _isSubmitted ? null : _removeFluxRow,
                      onQtyTap: _isSubmitted ? null : (i) async {
                        final f = _fluxRows[i];
                        await _openBbsuModal(materialId: f.materialId,
                            materialName: f.materialName, isRaw: false, rowIndex: i);
                      },
                      onRecalc: _recalcFluxTotals,
                    )),
                  ]);
                }
                return Column(children: [
                  _RawCard(
                    rows: _rawRows, isSubmitted: _isSubmitted, materials: _materials,
                    totalQty: _rawTotalQty, totalExp: _rawTotalExpected,
                    onAdd: _isSubmitted ? null : _addRawRow,
                    onRemove: _isSubmitted ? null : _removeRawRow,
                    onQtyTap: _isSubmitted ? null : (i) async {
                      final r = _rawRows[i];
                      await _openBbsuModal(materialId: r.materialId,
                          materialName: r.materialName, isRaw: true, rowIndex: i);
                    },
                    onCalcExp: _calcRawExpected, onRecalc: _recalcRawTotals,
                  ),
                  const SizedBox(height: 16),
                  _FluxCard(
                    rows: _fluxRows, isSubmitted: _isSubmitted, materials: _materials,
                    totalQty: _fluxTotalQty,
                    onAdd: _isSubmitted ? null : _addFluxRow,
                    onRemove: _isSubmitted ? null : _removeFluxRow,
                    onQtyTap: _isSubmitted ? null : (i) async {
                      final f = _fluxRows[i];
                      await _openBbsuModal(materialId: f.materialId,
                          materialName: f.materialName, isRaw: false, rowIndex: i);
                    },
                    onRecalc: _recalcFluxTotals,
                  ),
                ]);
              }),

              const SizedBox(height: 16),

              // ══ SECTION 3 — Process + Consumption/Output ═══════════════
              LayoutBuilder(builder: (_, box) {
                final wide = box.maxWidth > 700;
                final processCard = _ProcessCard(
                  rows: _processRows, isSubmitted: _isSubmitted,
                  totalBatchTime: _totalBatchTime,
                  onCalcTime: _calcProcessTime,
                  onSetNow: _isSubmitted ? null : (idx, which) {
                    final now = DateTime.now();
                    int hour = now.hour;
                    final minute = now.minute;
                    final period = hour >= 12 ? 'PM' : 'AM';

                    // Convert to 12-hour format
                    hour = hour % 12;
                    if (hour == 0) hour = 12;

                    final time12hr = '$hour:${minute.toString().padLeft(2, '0')} $period';

                    setState(() {
                      if (which == 'start') {
                        _processRows[idx].startCtrl.text = time12hr;
                      } else {
                        _processRows[idx].endCtrl.text = time12hr;
                      }
                      _calcProcessTime(idx);
                    });
                  },
                  onPickTime: _isSubmitted ? null : (idx, which) async {
                    final ctrl = which == 'start'
                        ? _processRows[idx].startCtrl
                        : _processRows[idx].endCtrl;
                    await _pickTime(ctrl);
                    _calcProcessTime(idx);
                  },
                );
                final rightCol = Column(children: [
                  _ConsumptionCard(
                    lpgCtrl: _lpgCtrl, o2Ctrl: _o2Ctrl,
                    lpgConverted: _lpgConverted, o2Converted: _o2Converted,
                    idInitCtrl: _idInitCtrl, idFinalCtrl: _idFinalCtrl,
                    idConsumed: _idConsumed,
                    rotInitCtrl: _rotInitCtrl, rotFinalCtrl: _rotFinalCtrl,
                    rotConsumed: _rotConsumed,
                    isSubmitted: _isSubmitted,
                    onLpgChanged: (_) => _calcLpg(),
                    onO2Changed:  (_) => _calcO2(),
                    onIdChanged:  (_) => _calcConsumption('id'),
                    onRotChanged: (_) => _calcConsumption('rot'),
                  ),
                  const SizedBox(height: 16),
                  // ── Output (simplified — single qty field) ──────────────
                  _SectionCard(
                    icon: Icons.output_outlined,
                    title: 'Output Window',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('MATERIAL', style: AppTextStyles.label()),
                              const SizedBox(height: 5),
                              _SearchableDropdown(
                                value: _outputMaterialId?.isNotEmpty == true
                                    ? _outputMaterialId : null,
                                materials: _materials,
                                hint: 'Select material…',
                                enabled: !_isSubmitted,
                                onChanged: (v) => setState(() => _outputMaterialId = v),
                              ),
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      // Tappable block summary chip
                      GestureDetector(
                        onTap: _isSubmitted ? null : _openOutputBlockModal,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: _outputTotalQty > 0
                                ? const Color(0xFFD1FAE5)
                                : AppColors.greenXLight,
                            border: Border.all(
                              color: _outputTotalQty > 0
                                  ? AppColors.green : AppColors.border,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Row(children: [
                            const Icon(Icons.view_module_outlined,
                                size: 16, color: AppColors.green),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _outputTotalQty > 0
                                          ? 'Total: ${_outputTotalQty.toStringAsFixed(3)} KG'
                                          : _isSubmitted
                                          ? 'No output recorded'
                                          : 'Tap to enter block weights…',
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _outputTotalQty > 0
                                            ? AppColors.textDark
                                            : AppColors.textMuted,
                                      ),
                                    ),
                                    if (_outputTotalQty > 0)
                                      Text(
                                        '${_outputBlocks.where((b) => b.weight > 0).length} block(s) recorded',
                                        style: GoogleFonts.outfit(
                                            fontSize: 11,
                                            color: AppColors.green),
                                      ),
                                  ]),
                            ),
                            if (!_isSubmitted)
                              const Icon(Icons.chevron_right,
                                  size: 16, color: AppColors.textMuted),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ]);

                if (wide) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 65, child: processCard),
                    const SizedBox(width: 16),
                    Expanded(flex: 35, child: rightCol),
                  ]);
                }
                return Column(children: [
                  processCard, const SizedBox(height: 16), rightCol,
                ]);
              }),

              const SizedBox(height: 16),

              // ══ SECTION 4 — Temperature Records ═══════════════════════
              _TempCard(
                rows: _tempRows, isSubmitted: _isSubmitted,
                onAdd: _isSubmitted ? null : () { _addTempRow(); setState(() {}); },
                onRemove: _isSubmitted ? null : _removeTempRow,
              ),

              const SizedBox(height: 24),

              // Action buttons
              if (_isSubmitted)
                const SizedBox.shrink()
              else if (!widget.isCreate)
                Row(children: [
                  Expanded(child: MesButton(
                    label: 'Save Draft', icon: Icons.save_outlined,
                    isLoading: _isSaving,
                    onPressed: _isSubmitting ? null : _save,
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _SubmitBtn(
                    isLoading: _isSubmitting,
                    onPressed: _isSaving ? null : _submit,
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

class _OutputBlock {
  final TextEditingController weightCtrl;
  int blockNo;

  _OutputBlock({required this.blockNo, double weight = 0})
      : weightCtrl = TextEditingController(
      text: weight > 0 ? weight.toStringAsFixed(3) : '');

  double get weight => double.tryParse(weightCtrl.text) ?? 0;

  void dispose() => weightCtrl.dispose();
}
class _RawRow {
  final List<SmeltingMaterialOption> materials;
  String materialId;
  List<BbsuSelection> bbsuSelections;
  final TextEditingController qtyCtrl, yieldCtrl, expCtrl;

  _RawRow({
    required this.materials, required String materialId,
    required this.bbsuSelections,
    required double qty, required double yieldPct, required double expected,
  })  : materialId = materialId,
        qtyCtrl    = TextEditingController(text: qty > 0 ? qty.toStringAsFixed(3) : ''),
        yieldCtrl  = TextEditingController(text: yieldPct > 0 ? yieldPct.toString() : ''),
        expCtrl    = TextEditingController(text: expected > 0 ? expected.toStringAsFixed(3) : '');

  String get materialName => materials.firstWhere((m) => m.id == materialId,
      orElse: () => SmeltingMaterialOption(id: '', name: '—')).name;

  void dispose() { qtyCtrl.dispose(); yieldCtrl.dispose(); expCtrl.dispose(); }
}

class _FluxRow {
  final List<SmeltingMaterialOption> materials;
  String materialId;
  List<BbsuSelection> bbsuSelections;
  final TextEditingController qtyCtrl;

  _FluxRow({
    required this.materials, required String materialId,
    required this.bbsuSelections, required double qty,
  })  : materialId = materialId,
        qtyCtrl    = TextEditingController(text: qty > 0 ? qty.toStringAsFixed(3) : '');

  String get materialName => materials.firstWhere((m) => m.id == materialId,
      orElse: () => SmeltingMaterialOption(id: '', name: '—')).name;

  void dispose() => qtyCtrl.dispose();
}

class _ProcessRow {
  final String processName;
  final TextEditingController startCtrl, endCtrl, totalCtrl;
  int totalMins = 0;
  String firingMode = '';

  _ProcessRow(this.processName)
      : startCtrl = TextEditingController(),
        endCtrl   = TextEditingController(),
        totalCtrl = TextEditingController();

  void dispose() { startCtrl.dispose(); endCtrl.dispose(); totalCtrl.dispose(); }
}

class _TempRow {
  final TextEditingController timeCtrl, insideCtrl, pgcCtrl, shellCtrl, bagCtrl;

  _TempRow({required String time, required String inside, required String pgc,
    required String shell, required String bagHouse})
      : timeCtrl   = TextEditingController(text: time),
        insideCtrl = TextEditingController(text: inside),
        pgcCtrl    = TextEditingController(text: pgc),
        shellCtrl  = TextEditingController(text: shell),
        bagCtrl    = TextEditingController(text: bagHouse);

  void dispose() {
    timeCtrl.dispose(); insideCtrl.dispose(); pgcCtrl.dispose();
    shellCtrl.dispose(); bagCtrl.dispose();
  }
}

// ─────────────────────────────────────────────
// Raw Materials Card
// ─────────────────────────────────────────────
// class _RawCard extends StatelessWidget {
//   final List<_RawRow> rows;
//   final bool isSubmitted;
//   final List<SmeltingMaterialOption> materials;
//   final double totalQty, totalExp;
//   final VoidCallback? onAdd;
//   final ValueChanged<int>? onRemove;
//   final ValueChanged<int>? onQtyTap;
//   final ValueChanged<int> onCalcExp;
//   final VoidCallback onRecalc;
//
//   const _RawCard({
//     required this.rows, required this.isSubmitted, required this.materials,
//     required this.totalQty, required this.totalExp, required this.onAdd,
//     required this.onRemove, required this.onQtyTap,
//     required this.onCalcExp, required this.onRecalc,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return MesCard(
//       padding: EdgeInsets.zero,
//       child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//         _cardHead('Raw Materials', Icons.layers_outlined, onAdd),
//         SingleChildScrollView(
//           scrollDirection: Axis.horizontal,
//           child: Column(children: [
//             _tblHeader(['#', 'Raw Material', 'QTY (KG)', 'Yield %', 'Expected', ''],
//                 [36, 180, 130, 90, 110, 36]),
//             ...rows.asMap().entries.map((e) => _RawTblRow(
//               index: e.key, row: e.value, materials: materials,
//               isSubmitted: isSubmitted, canDelete: rows.length > 1 && !isSubmitted,
//               onQtyTap:    onQtyTap == null ? null : () => onQtyTap!(e.key),
//               onRemove:    onRemove == null ? null : () => onRemove!(e.key),
//               onCalcExp:   () => onCalcExp(e.key),
//               onRecalc:    onRecalc,
//             )),
//             _tblFooter([
//               (36 + 180.0, 'TOTAL', true),
//               (130.0, totalQty > 0 ? totalQty.toStringAsFixed(3) : '', false),
//               (90.0, '', false),
//               (110.0, totalExp > 0 ? totalExp.toStringAsFixed(3) : '', false),
//               (36.0, '', false),
//             ]),
//           ]),
//         ),
//       ]),
//     );
//   }
// }
class _RawCard extends StatelessWidget {
  final List<_RawRow> rows;
  final bool isSubmitted;
  final List<SmeltingMaterialOption> materials;
  final double totalQty, totalExp;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemove;
  final ValueChanged<int>? onQtyTap;
  final ValueChanged<int> onCalcExp;
  final VoidCallback onRecalc;

  const _RawCard({
    required this.rows, required this.isSubmitted, required this.materials,
    required this.totalQty, required this.totalExp, required this.onAdd,
    required this.onRemove, required this.onQtyTap,
    required this.onCalcExp, required this.onRecalc,
  });

  @override
  Widget build(BuildContext context) {
    return MesCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHead('Raw Materials', Icons.layers_outlined, onAdd),
        // Responsive header
        Container(
          decoration: const BoxDecoration(
            color: AppColors.greenLight,
            border: Border(bottom: BorderSide(color: AppColors.border, width: 2)),
          ),
          child: Row(children: [
            const SizedBox(width: 36, child: SizedBox.shrink()),
            const Expanded(flex: 22, child: _RawHeaderCell('Raw Material')),
            const Expanded(flex: 16, child: _RawHeaderCell('QTY (KG)')),
            const Expanded(flex: 12, child: _RawHeaderCell('Yield %')),
            const Expanded(flex: 14, child: _RawHeaderCell('Expected')),
            const SizedBox(width: 36, child: SizedBox.shrink()),
          ]),
        ),
        // Rows
        ...rows.asMap().entries.map((e) => _RawTblRow(
          index: e.key, row: e.value, materials: materials,
          isSubmitted: isSubmitted, canDelete: rows.length > 1 && !isSubmitted,
          onQtyTap:  onQtyTap == null ? null : () => onQtyTap!(e.key),
          onRemove:  onRemove == null ? null : () => onRemove!(e.key),
          onCalcExp: () => onCalcExp(e.key),
          onRecalc:  onRecalc,
        )),
        // Footer
        Container(
          decoration: const BoxDecoration(
            color: AppColors.greenLight,
            border: Border(top: BorderSide(color: AppColors.border, width: 2)),
          ),
          child: Row(children: [
            const SizedBox(width: 36),
            Expanded(
              flex: 22,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('TOTAL',
                      style: AppTextStyles.label(color: AppColors.green)),
                ),
              ),
            ),
            Expanded(
              flex: 16,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Text(
                  totalQty > 0 ? totalQty.toStringAsFixed(3) : '',
                  style: GoogleFonts.outfit(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: AppColors.green),
                ),
              ),
            ),
            const Expanded(flex: 12, child: SizedBox.shrink()),
            Expanded(
              flex: 14,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Text(
                  totalExp > 0 ? totalExp.toStringAsFixed(3) : '',
                  style: GoogleFonts.outfit(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: AppColors.green),
                ),
              ),
            ),
            const SizedBox(width: 36),
          ]),
        ),
      ]),
    );
  }
}

class _RawHeaderCell extends StatelessWidget {
  final String label;
  const _RawHeaderCell(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    child: Text(label.toUpperCase(),
        style: AppTextStyles.label(color: AppColors.green)),
  );
}
// ─────────────────────────────────────────────
// Flux / Chemicals Card
// ─────────────────────────────────────────────
class _FluxCard extends StatelessWidget {
  final List<_FluxRow> rows;
  final bool isSubmitted;
  final List<SmeltingMaterialOption> materials;
  final double totalQty;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemove;
  final ValueChanged<int>? onQtyTap;
  final VoidCallback onRecalc;

  const _FluxCard({
    required this.rows, required this.isSubmitted, required this.materials,
    required this.totalQty, required this.onAdd, required this.onRemove,
    required this.onQtyTap, required this.onRecalc,
  });

  @override
  Widget build(BuildContext context) {
    return MesCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHead('Flux / Chemicals', Icons.science_outlined, onAdd),
        // Responsive header
        Container(
          decoration: const BoxDecoration(
            color: AppColors.greenLight,
            border: Border(bottom: BorderSide(color: AppColors.border, width: 2)),
          ),
          child: Row(children: [
            const SizedBox(width: 36, child: SizedBox.shrink()),
            const Expanded(flex: 3, child: _RawHeaderCell('Flux / Chemical')),
            const Expanded(flex: 2, child: _RawHeaderCell('QTY (KG)')),
            const SizedBox(width: 36, child: SizedBox.shrink()),
          ]),
        ),
        // Rows
        ...rows.asMap().entries.map((e) => _FluxTblRow(
          index: e.key, row: e.value, materials: materials,
          isSubmitted: isSubmitted, canDelete: rows.length > 1 && !isSubmitted,
          onQtyTap: onQtyTap == null ? null : () => onQtyTap!(e.key),
          onRemove: onRemove == null ? null : () => onRemove!(e.key),
          onRecalc: onRecalc,
        )),
        // Footer
        Container(
          decoration: const BoxDecoration(
            color: AppColors.greenLight,
            border: Border(top: BorderSide(color: AppColors.border, width: 2)),
          ),
          child: Row(children: [
            const SizedBox(width: 36),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('TOTAL',
                      style: AppTextStyles.label(color: AppColors.green)),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Text(
                  totalQty > 0 ? totalQty.toStringAsFixed(3) : '',
                  style: GoogleFonts.outfit(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: AppColors.green),
                ),
              ),
            ),
            const SizedBox(width: 36),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Process Details Card (9 fixed rows)
// ─────────────────────────────────────────────
class _ProcessCard extends StatelessWidget {
  final List<_ProcessRow> rows;
  final bool isSubmitted;
  final String totalBatchTime;
  final ValueChanged<int> onCalcTime;
  final void Function(int, String)? onSetNow;
  final void Function(int, String)? onPickTime;

  const _ProcessCard({
    required this.rows, required this.isSubmitted,
    required this.totalBatchTime, required this.onCalcTime,
    required this.onSetNow, required this.onPickTime,
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
            Text('PROCESS DETAILS',
                style: AppTextStyles.label(color: AppColors.green)),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(children: [
            // Table header
            Container(
              decoration: const BoxDecoration(color: AppColors.greenLight,
                  border: Border(bottom: BorderSide(color: AppColors.border, width: 2))),
              child: Row(children: [
                _ph('Process',      130),
                _ph('Start',        110, center: true),
                _ph('',             60),
                _ph('End',          110, center: true),
                _ph('',             60),
                _ph('Total',        90),
                _ph('Firing Mode',  120),
              ]),
            ),
            // 9 fixed rows
            ...rows.asMap().entries.map((e) => _ProcTblRow(
              index: e.key, row: e.value, isSubmitted: isSubmitted,
              onSetNow: onSetNow, onPickTime: onPickTime,
              onCalcTime: onCalcTime,
            )),
            // Footer total batch time
            Container(
              decoration: const BoxDecoration(color: AppColors.greenLight,
                  border: Border(top: BorderSide(color: AppColors.border, width: 2))),
              child: Row(children: [
                SizedBox(width: 130 + 110 + 44 + 110 + 44, child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Align(alignment: Alignment.centerRight,
                      child: Text('TOTAL BATCH TIME',
                          style: AppTextStyles.label(color: AppColors.green))),
                )),
                SizedBox(width: 90 + 120, child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Text(totalBatchTime, style: GoogleFonts.outfit(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: AppColors.green)),
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

// ─────────────────────────────────────────────
// Consumption Card
// ─────────────────────────────────────────────
class _ConsumptionCard extends StatelessWidget {
  final TextEditingController lpgCtrl, o2Ctrl;
  final String lpgConverted, o2Converted;
  final TextEditingController idInitCtrl, idFinalCtrl;
  final String idConsumed;
  final TextEditingController rotInitCtrl, rotFinalCtrl;
  final String rotConsumed;
  final bool isSubmitted;
  final ValueChanged<String> onLpgChanged, onO2Changed, onIdChanged, onRotChanged;

  const _ConsumptionCard({
    required this.lpgCtrl, required this.o2Ctrl,
    required this.lpgConverted, required this.o2Converted,
    required this.idInitCtrl, required this.idFinalCtrl, required this.idConsumed,
    required this.rotInitCtrl, required this.rotFinalCtrl, required this.rotConsumed,
    required this.isSubmitted,
    required this.onLpgChanged, required this.onO2Changed,
    required this.onIdChanged, required this.onRotChanged,
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
            const Icon(Icons.speed_outlined, size: 15, color: AppColors.green),
            const SizedBox(width: 8),
            Text('CONSUMPTION', style: AppTextStyles.label(color: AppColors.green)),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          // LPG + O2
          Row(children: [
            Expanded(child: Column(children: [
              _numField('LPG (NM³)', lpgCtrl, isSubmitted, onChanged: onLpgChanged),
              const SizedBox(height: 4),
              Text(lpgConverted, style: GoogleFonts.outfit(fontSize: 11,
                  color: AppColors.green, fontWeight: FontWeight.w600)),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(children: [
              _numField('Liquid O₂ (NM³)', o2Ctrl, isSubmitted, onChanged: onO2Changed),
              const SizedBox(height: 4),
              Text(o2Converted, style: GoogleFonts.outfit(fontSize: 11,
                  color: AppColors.green, fontWeight: FontWeight.w600)),
            ])),
          ]),
          const SizedBox(height: 14),
          // ID Fan
          _consSect('ID Fan Consumption', idInitCtrl, idFinalCtrl, idConsumed,
              isSubmitted, onIdChanged),
          const SizedBox(height: 14),
          // Rotary Power
          _consSect('Rotary Power Consumption', rotInitCtrl, rotFinalCtrl, rotConsumed,
              isSubmitted, onRotChanged),
        ])),
      ]),
    );
  }

  Widget _consSect(String title, TextEditingController initC,
      TextEditingController finalC, String consumed, bool ro,
      ValueChanged<String> onChange) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: AppTextStyles.label()),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _numField('Initial', initC, ro, onChanged: onChange)),
          const SizedBox(width: 12),
          Expanded(child: _numField('Final', finalC, ro, onChanged: onChange)),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: AppColors.greenLight,
              borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('CONSUMPTION', style: AppTextStyles.label(color: AppColors.green)),
            Text(consumed, style: GoogleFonts.outfit(fontSize: 14,
                fontWeight: FontWeight.w800, color: AppColors.green)),
          ]),
        ),
      ]);

  Widget _numField(String label, TextEditingController ctrl, bool ro,
      {ValueChanged<String>? onChanged}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: AppTextStyles.label()),
        const SizedBox(height: 5),
        TextField(
          controller: ctrl, readOnly: ro, onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: ro ? null : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textDark),
          decoration: InputDecoration(
            isDense: true, filled: true, fillColor: AppColors.greenXLight,
            hintText: '0.000',
            hintStyle: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
          ),
        ),
      ]);
}

// ─────────────────────────────────────────────
// Temperature Records Card
// ─────────────────────────────────────────────
class _TempCard extends StatelessWidget {
  final List<_TempRow> rows;
  final bool isSubmitted;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemove;

  const _TempCard({
    required this.rows, required this.isSubmitted,
    required this.onAdd, required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return MesCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHead('Temperature Record', Icons.thermostat_outlined, onAdd),
        Column(children: [
          // Responsive header
          Container(
            decoration: const BoxDecoration(color: AppColors.greenLight,
                border: Border(bottom: BorderSide(color: AppColors.border, width: 2))),
            child: Row(children: [
              const SizedBox(width: 40, child: SizedBox.shrink()), // Spacer for row number
              const Expanded(flex: 2, child: _HeaderCell('Time')),
              const Expanded(flex: 3, child: _HeaderCell('Inside Temp Before Charging (°C)')),
              const Expanded(flex: 2, child: _HeaderCell('Process Gas Chamber')),
              const Expanded(flex: 2, child: _HeaderCell('Shell')),
              const Expanded(flex: 2, child: _HeaderCell('Bag House')),
              const SizedBox(width: 40, child: SizedBox.shrink()), // Spacer for delete button
            ]),
          ),
          ...rows.asMap().entries.map((e) => _TempTblRow(
            index: e.key, row: e.value, isSubmitted: isSubmitted,
            canDelete: rows.length > 1 && !isSubmitted,
            onRemove: onRemove == null ? null : () => onRemove!(e.key),
          )),
        ]),
      ]),
    );
  }
}

// Helper widget for responsive headers
class _HeaderCell extends StatelessWidget {
  final String label;
  const _HeaderCell(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(label.toUpperCase(),
          style: AppTextStyles.label(color: AppColors.green)),
    );
  }
}

// ─────────────────────────────────────────────
// Individual table row widgets
// ─────────────────────────────────────────────
class _RawTblRow extends StatefulWidget {
  final int index;
  final _RawRow row;
  final List<SmeltingMaterialOption> materials;
  final bool isSubmitted, canDelete;
  final VoidCallback? onQtyTap, onRemove;
  final VoidCallback onCalcExp, onRecalc;

  const _RawTblRow({
    required this.index, required this.row, required this.materials,
    required this.isSubmitted, required this.canDelete,
    required this.onQtyTap, required this.onRemove,
    required this.onCalcExp, required this.onRecalc,
  });

  @override
  State<_RawTblRow> createState() => _RawTblRowState();
}

class _RawTblRowState extends State<_RawTblRow> {
  @override
  Widget build(BuildContext context) {
    final row = widget.row;

    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderLight))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // SR number — fixed 36
        SizedBox(
          width: 36,
          child: Center(
            child: Text('${widget.index + 1}',
                style: GoogleFonts.outfit(fontSize: 12,
                    fontWeight: FontWeight.w700, color: AppColors.green)),
          ),
        ),

        // Material dropdown — flex 22
        Expanded(
          flex: 22,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: widget.isSubmitted
                ? _roResponsiveCell(row.materialName)
                : _SearchableDropdown(
              value: row.materialId.isNotEmpty ? row.materialId : null,
              materials: widget.materials,
              onChanged: (v) {
                setState(() => row.materialId = v ?? '');
                widget.onRecalc();
              },
            ),
          ),
        ),

        // QTY tap button — flex 16
        Expanded(
          flex: 16,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: GestureDetector(
              onTap: widget.onQtyTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: row.qtyCtrl.text.isNotEmpty
                      ? const Color(0xFFD1FAE5) : AppColors.greenXLight,
                  border: Border.all(
                      color: row.qtyCtrl.text.isNotEmpty
                          ? AppColors.green : AppColors.border,
                      width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      row.qtyCtrl.text.isNotEmpty
                          ? '${row.qtyCtrl.text} KG'
                          : widget.isSubmitted ? '—' : 'Tap…',
                      style: GoogleFonts.outfit(fontSize: 11.5,
                          color: row.qtyCtrl.text.isNotEmpty
                              ? AppColors.textDark : AppColors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!widget.isSubmitted)
                    const Icon(Icons.keyboard_arrow_down, size: 12,
                        color: AppColors.textMuted),
                ]),
              ),
            ),
          ),
        ),

        // Yield % — flex 12
        Expanded(
          flex: 12,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: _tblInput(
              controller: row.yieldCtrl, hint: '0.00',
              numeric: true, readOnly: widget.isSubmitted,
              onChanged: (_) => widget.onCalcExp(),
            ),
          ),
        ),

        // Expected (auto) — flex 14
        Expanded(
          flex: 14,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: _tblInput(
              controller: row.expCtrl, readOnly: true,
              calcStyle: true, hint: '0.000',
            ),
          ),
        ),

        // Delete — fixed 36
        SizedBox(
          width: 36,
          child: Center(
            child: widget.canDelete
                ? _delBtn(widget.onRemove!)
                : const SizedBox.shrink(),
          ),
        ),
      ]),
    );
  }
}

class _FluxTblRow extends StatefulWidget {
  final int index;
  final _FluxRow row;
  final List<SmeltingMaterialOption> materials;
  final bool isSubmitted, canDelete;
  final VoidCallback? onQtyTap, onRemove;
  final VoidCallback onRecalc;

  const _FluxTblRow({
    required this.index, required this.row, required this.materials,
    required this.isSubmitted, required this.canDelete,
    required this.onQtyTap, required this.onRemove, required this.onRecalc,
  });

  @override
  State<_FluxTblRow> createState() => _FluxTblRowState();
}

class _FluxTblRowState extends State<_FluxTblRow> {
  @override
  Widget build(BuildContext context) {
    final row = widget.row;

    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderLight))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // SR number — fixed 36
        SizedBox(
          width: 36,
          child: Center(
            child: Text('${widget.index + 1}',
                style: GoogleFonts.outfit(fontSize: 12,
                    fontWeight: FontWeight.w700, color: AppColors.green)),
          ),
        ),

        // Material dropdown — flex 3
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: widget.isSubmitted
                ? _roResponsiveCell(row.materialName)
                : _SearchableDropdown(
              value: row.materialId.isNotEmpty ? row.materialId : null,
              materials: widget.materials,
              onChanged: (v) {
                setState(() => row.materialId = v ?? '');
                widget.onRecalc();
              },
            ),
          ),
        ),

        // QTY tap button — flex 2
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: GestureDetector(
              onTap: widget.onQtyTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: row.qtyCtrl.text.isNotEmpty
                      ? const Color(0xFFD1FAE5) : AppColors.greenXLight,
                  border: Border.all(
                      color: row.qtyCtrl.text.isNotEmpty
                          ? AppColors.green : AppColors.border,
                      width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      row.qtyCtrl.text.isNotEmpty
                          ? '${row.qtyCtrl.text} KG'
                          : widget.isSubmitted ? '—' : 'Tap…',
                      style: GoogleFonts.outfit(fontSize: 11.5,
                          color: row.qtyCtrl.text.isNotEmpty
                              ? AppColors.textDark : AppColors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!widget.isSubmitted)
                    const Icon(Icons.keyboard_arrow_down, size: 12,
                        color: AppColors.textMuted),
                ]),
              ),
            ),
          ),
        ),

        // Delete — fixed 36
        SizedBox(
          width: 36,
          child: Center(
            child: widget.canDelete
                ? _delBtn(widget.onRemove!)
                : const SizedBox.shrink(),
          ),
        ),
      ]),
    );
  }
}
Widget _roResponsiveCell(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
  decoration: BoxDecoration(
    color: const Color(0xFFF0F4F2),
    border: Border.all(color: AppColors.border, width: 1.5),
    borderRadius: BorderRadius.circular(6),
  ),
  child: Text(text,
      style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textMuted),
      overflow: TextOverflow.ellipsis),
);
class _ProcTblRow extends StatefulWidget {
  final int index;
  final _ProcessRow row;
  final bool isSubmitted;
  final void Function(int, String)? onSetNow;
  final void Function(int, String)? onPickTime;
  final ValueChanged<int> onCalcTime;

  const _ProcTblRow({
    required this.index,
    required this.row,
    required this.isSubmitted,
    required this.onSetNow,
    required this.onPickTime,
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

    Widget nowBtn(Color bg, String label, String which) => ro
        ? const SizedBox(width: 52)
        : SizedBox(width: 52, child: Center(child: GestureDetector(
      onTap: () => widget.onSetNow?.call(widget.index, which),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
        child: Text(label, style: GoogleFonts.outfit(fontSize: 10,
            fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    )));

    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderLight))),
      child: Row(children: [
        // Process Name
        SizedBox(width: 130, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(row.processName, style: GoogleFonts.outfit(fontSize: 11.5,
              fontWeight: FontWeight.w600, color: AppColors.textDark)),
        )),

        // Start Time - Using CompactTimePickerField
        Padding(
          padding: const EdgeInsets.all(5),
          child: CompactTimePickerField(
            controller: row.startCtrl,
            readOnly: ro,
            width: 110,
            onTimeSelected: () => widget.onCalcTime(widget.index),
          ),
        ),

        // Start Now button
        nowBtn(const Color(0xFF16A34A), 'START', 'start'),

        // End Time - Using CompactTimePickerField
        Padding(
          padding: const EdgeInsets.all(5),
          child: CompactTimePickerField(
            controller: row.endCtrl,
            readOnly: ro,
            width: 110,
            onTimeSelected: () => widget.onCalcTime(widget.index),
          ),
        ),

        // End Now button
        nowBtn(const Color(0xFFDC2626), 'END', 'end'),

        // Total Time
        SizedBox(width: 90, child: Padding(padding: const EdgeInsets.all(5),
          child: _tblInput(controller: row.totalCtrl, readOnly: true,
              calcStyle: true, hint: '0 min'),
        )),

        // Firing Mode
        SizedBox(width: 120, child: Padding(padding: const EdgeInsets.all(5),
          child: ro
              ? _roCell(row.firingMode, 110)
              : DropdownButtonFormField<String>(
            value: row.firingMode.isNotEmpty ? row.firingMode : null,
            isDense: true,
            hint: Text('Select…', style: GoogleFonts.outfit(fontSize: 12,
                color: AppColors.textMuted)),
            decoration: _dropDec(),
            items: kFiringOptions.map((f) => DropdownMenuItem(
              value: f,
              child: Text(f, style: GoogleFonts.outfit(fontSize: 12)),
            )).toList(),
            onChanged: (v) => setState(() => row.firingMode = v ?? ''),
          ),
        )),
      ]),
    );
  }
}

class _TempTblRow extends StatelessWidget {
  final int index;
  final _TempRow row;
  final bool isSubmitted, canDelete;
  final VoidCallback? onRemove;

  const _TempTblRow({
    required this.index, required this.row, required this.isSubmitted,
    required this.canDelete, required this.onRemove,
  });

  Future<void> _pickTime(BuildContext context) async {
    TimeOfDay current = TimeOfDay.now();
    if (row.timeCtrl.text.isNotEmpty) {
      try {
        final parts = row.timeCtrl.text.split(':');
        current = TimeOfDay(
            hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {}
    }
    final picked =
    await showTimePicker(context: context, initialTime: current);
    if (picked != null) {
      row.timeCtrl.text =
      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderLight))),
      child: Row(children: [
        // Row number - fixed small width
        SizedBox(width: 40, child: Center(child: Text('${index + 1}',
            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700,
                color: AppColors.green)))),

        // Time field - responsive
        Expanded(
          flex: 2,
          child: Padding(padding: const EdgeInsets.all(5),
            child: GestureDetector(
              onTap: isSubmitted ? null : () => _pickTime(context),
              child: AbsorbPointer(
                absorbing: true,
                child: TextField(
                  controller: row.timeCtrl,
                  readOnly: true,
                  style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textDark),
                  decoration: InputDecoration(
                    hintText: '--:--',
                    hintStyle: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
                    suffixIcon: isSubmitted
                        ? null
                        : const Icon(Icons.access_time, size: 14, color: AppColors.textMuted),
                    isDense: true,
                    filled: true,
                    fillColor: isSubmitted
                        ? const Color(0xFFF0F4F2) : AppColors.greenXLight,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Inside Temp Before Charging - responsive
        Expanded(
          flex: 3,
          child: Padding(padding: const EdgeInsets.all(5),
              child: _tblInput(controller: row.insideCtrl, readOnly: isSubmitted,
                  hint: '°C', numeric: true)),
        ),

        // Process Gas Chamber - responsive
        Expanded(
          flex: 2,
          child: Padding(padding: const EdgeInsets.all(5),
              child: _tblInput(controller: row.pgcCtrl, readOnly: isSubmitted, hint: 'Text')),
        ),

        // Shell - responsive
        Expanded(
          flex: 2,
          child: Padding(padding: const EdgeInsets.all(5),
              child: _tblInput(controller: row.shellCtrl, readOnly: isSubmitted, hint: 'Text')),
        ),

        // Bag House - responsive
        Expanded(
          flex: 2,
          child: Padding(padding: const EdgeInsets.all(5),
              child: _tblInput(controller: row.bagCtrl, readOnly: isSubmitted, hint: 'Text')),
        ),

        // Delete button - fixed width
        SizedBox(width: 40, child: Center(child: canDelete
            ? _delBtn(onRemove!) : const SizedBox.shrink())),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// BBSU Lot Modal
// Online: fresh API data; Offline: from smelting_bbsu_lot_cache
// ─────────────────────────────────────────────
class _BbsuLotModal extends StatefulWidget {
  final String materialName;
  final List<SmeltingBbsuLot> lots;
  final bool isOffline;
  final List<BbsuSelection> existingSelections;
  final ValueChanged<List<BbsuSelection>> onConfirm;

  const _BbsuLotModal({
    required this.materialName, required this.lots, required this.isOffline,
    required this.existingSelections, required this.onConfirm,
  });

  @override
  State<_BbsuLotModal> createState() => _BbsuLotModalState();
}

class _BbsuLotModalState extends State<_BbsuLotModal> {
  late final Map<String, TextEditingController> _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = {};
    for (final lot in widget.lots) {
      final existing = widget.existingSelections.firstWhere(
              (s) => s.bbsuId == lot.bbsuBatchId,
          orElse: () => BbsuSelection(bbsuId: '', bbsuNo: '', qty: 0));
      _ctrl[lot.bbsuBatchId] = TextEditingController(
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
    final sels = <BbsuSelection>[];
    for (final lot in widget.lots) {
      final qty = double.tryParse(_ctrl[lot.bbsuBatchId]?.text ?? '') ?? 0;
      if (qty > 0) sels.add(BbsuSelection(bbsuId: lot.bbsuBatchId, bbsuNo: lot.batchNo, qty: qty));
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
              const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(child: Text('Available Stock — ${widget.materialName}',
                  style: AppTextStyles.subheading(color: AppColors.green),
                  overflow: TextOverflow.ellipsis)),
              GestureDetector(onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, size: 18, color: AppColors.textMuted)),
            ]),
          ),

          // Offline notice
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
                Expanded(child: Text('You are offline. Showing cached stock data.',
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
                Text('No available stock found for this material.',
                    style: AppTextStyles.caption()),
              ],
            )))
          else ...[
            Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Text('Select the quantity to assign from available stock.',
                    style: AppTextStyles.caption())),
            Expanded(child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(children: [
                // Header
                Container(
                  decoration: const BoxDecoration(color: AppColors.greenLight,
                      border: Border(bottom: BorderSide(color: AppColors.border, width: 2))),
                  child: Row(children: [
                    _mth('Doc No', 120), _mth('Material', 160),
                    _mth('Unit', 60), _mth('Available', 120), _mth('Assign Qty', 120),
                  ]),
                ),
                // Rows
                ...widget.lots.map((lot) {
                  final isZero = lot.availableQty <= 0;
                  return StatefulBuilder(builder: (_, ss) => Container(
                    decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.borderLight))),
                    child: Row(children: [
                      SizedBox(width: 120, child: Padding(
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
                        child: Text(lot.materialName, style: GoogleFonts.outfit(
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
                          controller: _ctrl[lot.bbsuBatchId],
                          enabled: !isZero,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          onChanged: (v) {
                            final val = double.tryParse(v) ?? 0;
                            if (val > lot.availableQty) {
                              _ctrl[lot.bbsuBatchId]!.text =
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
                    SizedBox(width: 120 + 160 + 60 + 120, child: Padding(
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
              MesButton(label: 'Confirm Selection', icon: Icons.check,
                  onPressed: _total > 0 ? _confirm : null),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _mth(String label, double w) => SizedBox(width: w, child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    child: Text(label.toUpperCase(),
        style: AppTextStyles.label(color: AppColors.green)),
  ));
}

// ─────────────────────────────────────────────
// Small UI helpers (section card, submit btn, banners)
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

class _DropField extends StatelessWidget {
  final String label;
  final String? value, hint;
  final List<DropdownMenuItem<String>> items;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _DropField({required this.label, required this.value, required this.items,
    required this.enabled, required this.onChanged, this.hint});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: AppTextStyles.label()),
      const SizedBox(height: 5),
      DropdownButtonFormField<String>(
        value: value,
        isDense: true,
        hint: hint != null
            ? Text(hint!, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted))
            : null,
        decoration: InputDecoration(
          isDense: true, filled: true, fillColor: AppColors.greenXLight,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
        ),
        items: items,
        onChanged: enabled ? onChanged : null,
      ),
    ],
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
// Output Block Modal
// 11 default rows; ADD adds more; total auto-calculates
// ─────────────────────────────────────────────
class _OutputBlockModal extends StatefulWidget {
  final List<_OutputBlock> initialBlocks;
  final ValueChanged<List<_OutputBlock>> onConfirm;

  const _OutputBlockModal({
    required this.initialBlocks,
    required this.onConfirm,
  });

  @override
  State<_OutputBlockModal> createState() => _OutputBlockModalState();
}

class _OutputBlockModalState extends State<_OutputBlockModal> {
  late List<_OutputBlock> _blocks;

  @override
  void initState() {
    super.initState();
    // Deep-copy so cancelling discards changes
    _blocks = widget.initialBlocks
        .map((b) => _OutputBlock(blockNo: b.blockNo, weight: b.weight))
        .toList();
  }

  @override
  void dispose() {
    // Only dispose our local copies — originals are owned by parent
    for (final b in _blocks) b.dispose();
    super.dispose();
  }

  double get _total => _blocks.fold(0, (s, b) => s + b.weight);

  void _addBlock() {
    setState(() {
      _blocks.add(_OutputBlock(blockNo: _blocks.length + 1));
    });
  }

  void _removeBlock(int i) {
    if (_blocks.length <= 1) return;
    setState(() {
      _blocks[i].dispose();
      _blocks.removeAt(i);
      // Renumber
      for (int j = 0; j < _blocks.length; j++) {
        _blocks[j].blockNo = j + 1;
      }
    });
  }

  void _confirm() {
    // Return a fresh list owned by the parent
    final confirmed = _blocks
        .map((b) => _OutputBlock(blockNo: b.blockNo, weight: b.weight))
        .toList();
    // Dispose the modal's copies first
    for (final b in _blocks) b.dispose();
    _blocks = []; // prevent double-dispose in dispose()
    widget.onConfirm(confirmed);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.93,
      minChildSize: 0.4,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: const BoxDecoration(
              color: AppColors.greenLight,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(children: [
              const Icon(Icons.view_module_outlined,
                  size: 16, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Output Blocks',
                  style: AppTextStyles.subheading(color: AppColors.green),
                ),
              ),
              // ADD button
              GestureDetector(
                onTap: _addBlock,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.add, size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('Add',
                        style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.close,
                    size: 18, color: AppColors.textMuted),
              ),
            ]),
          ),

          // Instruction
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Text(
              'Enter the weight of each output block in KG.',
              style: AppTextStyles.caption(),
            ),
          ),

          // Table
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(children: [
                // Table header
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.greenLight,
                    border: Border(
                        bottom: BorderSide(
                            color: AppColors.border, width: 2)),
                  ),
                  child: Row(children: [
                    _bh('Block', 80),
                    _bh('Weight (KG)', 160),
                    _bh('', 36),
                  ]),
                ),
                // Rows
                StatefulBuilder(builder: (_, ss) {
                  return Column(
                    children: _blocks.asMap().entries.map((e) {
                      final i = e.key;
                      final b = e.value;
                      return Container(
                        decoration: const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: AppColors.borderLight)),
                        ),
                        child: Row(children: [
                          // Block label
                          SizedBox(
                            width: 80,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.greenLight,
                                  borderRadius:
                                  BorderRadius.circular(5),
                                ),
                                child: Text(
                                  'Block ${b.blockNo}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.green,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Weight input
                          SizedBox(
                            width: 160,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: TextField(
                                controller: b.weightCtrl,
                                keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.]'))
                                ],
                                onChanged: (_) => ss(() {}),
                                style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: AppColors.textDark),
                                decoration: InputDecoration(
                                  hintText: '0.000',
                                  hintStyle: GoogleFonts.outfit(
                                      fontSize: 12,
                                      color: AppColors.textMuted),
                                  isDense: true,
                                  filled: true,
                                  fillColor: AppColors.greenXLight,
                                  contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8),
                                  border: OutlineInputBorder(
                                      borderRadius:
                                      BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: AppColors.border,
                                          width: 1.5)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius:
                                      BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: AppColors.border,
                                          width: 1.5)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius:
                                      BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: AppColors.green,
                                          width: 1.5)),
                                ),
                              ),
                            ),
                          ),
                          // Delete
                          SizedBox(
                            width: 36,
                            child: Center(
                              child: _blocks.length > 1
                                  ? _delBtn(() {
                                _removeBlock(i);
                                ss(() {});
                              })
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ]),
                      );
                    }).toList(),
                  );
                }),
                // Total footer
                StatefulBuilder(builder: (_, ss) {
                  // Listen on all controllers
                  for (final b in _blocks) {
                    b.weightCtrl.addListener(() => ss(() {}));
                  }
                  return Container(
                    decoration: const BoxDecoration(
                      color: AppColors.greenLight,
                      border: Border(
                          top: BorderSide(
                              color: AppColors.border, width: 2)),
                    ),
                    child: Row(children: [
                      const SizedBox(
                        width: 80,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox.shrink(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                              children: [
                                Text('TOTAL',
                                    style: AppTextStyles.label(
                                        color: AppColors.green)),
                                Text(
                                  '${_total.toStringAsFixed(3)} KG',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.green,
                                  ),
                                ),
                              ]),
                        ),
                      ),
                      const SizedBox(width: 36),
                    ]),
                  );
                }),
              ]),
            ),
          ),

          // Footer actions
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: AppColors.borderLight))),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MesOutlineButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  MesButton(
                    label: 'Confirm',
                    icon: Icons.check,
                    onPressed: _confirm,
                  ),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _bh(String label, double w) => SizedBox(
    width: w,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(label.toUpperCase(),
          style: AppTextStyles.label(color: AppColors.green)),
    ),
  );
}
// ─────────────────────────────────────────────
// Searchable Dropdown (replaces DropdownButtonFormField)
// ─────────────────────────────────────────────
class _SearchableDropdown extends StatelessWidget {
  final String? value;
  final List<SmeltingMaterialOption> materials;
  final String hint;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _SearchableDropdown({
    required this.value,
    required this.materials,
    required this.onChanged,
    this.hint = 'Select…',
    this.enabled = true,
  });

  String get _selectedName => value != null && value!.isNotEmpty
      ? materials.firstWhere((m) => m.id == value,
      orElse: () => SmeltingMaterialOption(id: '', name: '—')).name
      : '';

  Future<void> _open(BuildContext context) async {
    if (!enabled) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchableDropdownModal(
        materials: materials,
        selectedId: value,
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = _selectedName.isNotEmpty;
    return GestureDetector(
      onTap: enabled ? () => _open(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: enabled ? AppColors.greenXLight : const Color(0xFFF0F4F2),
          border: Border.all(color: AppColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              hasValue ? _selectedName : hint,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: hasValue ? AppColors.textDark : AppColors.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (enabled)
            const Icon(Icons.search, size: 14, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}

class _SearchableDropdownModal extends StatefulWidget {
  final List<SmeltingMaterialOption> materials;
  final String? selectedId;

  const _SearchableDropdownModal({
    required this.materials,
    required this.selectedId,
  });

  @override
  State<_SearchableDropdownModal> createState() => _SearchableDropdownModalState();
}

class _SearchableDropdownModalState extends State<_SearchableDropdownModal> {
  final _searchCtrl = TextEditingController();
  late List<SmeltingMaterialOption> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.materials;
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? widget.materials
          : widget.materials
          .where((m) => m.name.toLowerCase().contains(q))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Wrap with Scaffold to handle keyboard insets
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true, // This is key - resizes when keyboard opens
      body: DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.88,
        minChildSize: 0.4,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              decoration: const BoxDecoration(
                color: AppColors.greenLight,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(children: [
                const Icon(Icons.search, size: 16, color: AppColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Select Material',
                      style: AppTextStyles.subheading(color: AppColors.green)),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                ),
              ]),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Search materials…',
                  hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? GestureDetector(
                    onTap: () => _searchCtrl.clear(),
                    child: const Icon(Icons.clear, size: 16, color: AppColors.textMuted),
                  )
                      : null,
                  isDense: true, filled: true, fillColor: AppColors.greenXLight,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
                ),
              ),
            ),
            // Results count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${_filtered.length} result(s)',
                    style: AppTextStyles.caption()),
              ),
            ),
            // List - use Expanded with keyboard handling
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.search_off_outlined,
                        size: 40, color: AppColors.borderLight),
                    const SizedBox(height: 8),
                    Text('No materials match your search.',
                        style: AppTextStyles.caption()),
                  ],
                ),
              )
                  : ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 8),
                // Add bottom padding to ensure last items are scrollable above keyboard
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: _filtered.length,
                separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.borderLight),
                itemBuilder: (_, i) {
                  final m = _filtered[i];
                  final isSelected = m.id == widget.selectedId;
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(m.id),
                    child: Container(
                      color: isSelected
                          ? AppColors.greenXLight : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(children: [
                        Expanded(
                          child: Text(m.name,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w700 : FontWeight.w400,
                                color: isSelected
                                    ? AppColors.green : AppColors.textDark,
                              )),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle,
                              size: 16, color: AppColors.green),
                      ]),
                    ),
                  );
                },
              ),
            ),
            // Add a small bottom spacer for keyboard
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 10 : 0),
          ]),
        ),
      ),
    );
  }
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

Widget _tblInput({
  required TextEditingController controller,
  String hint = '', bool readOnly = false,
  bool numeric = false, bool calcStyle = false,
  ValueChanged<String>? onChanged,
}) =>
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
        hintText: hint,
        hintStyle: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
        isDense: true, filled: true,
        fillColor: calcStyle ? const Color(0xFFEEF6F1)
            : readOnly ? const Color(0xFFF0F4F2) : AppColors.greenXLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: calcStyle
                ? const Color(0xFFC8DFD1) : AppColors.border, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: calcStyle
                ? const Color(0xFFC8DFD1) : AppColors.border, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppColors.green, width: 1.5)),
      ),
    );

Widget _roCell(String text, double width) => SizedBox(width: width,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFF0F4F2),
          border: Border.all(color: AppColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: GoogleFonts.outfit(fontSize: 12.5,
          color: AppColors.textMuted), overflow: TextOverflow.ellipsis),
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