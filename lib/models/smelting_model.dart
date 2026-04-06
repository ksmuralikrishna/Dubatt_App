// ─────────────────────────────────────────────────────────────────────────────
// smelting_model.dart
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────
// Material option
// ─────────────────────────────────────────────
class SmeltingMaterialOption {
  final String id;
  final String name;
  final String? unit;

  const SmeltingMaterialOption({
    required this.id,
    required this.name,
    this.unit,
  });

  factory SmeltingMaterialOption.fromJson(Map<String, dynamic> json) {
    return SmeltingMaterialOption(
      id:   json['id']?.toString() ?? '',
      name: json['secondary_name']?.toString()
          ?? json['name']?.toString()
          ?? json['material_name']?.toString()
          ?? '',
      unit: json['unit']?.toString(),
    );
  }
}

// ─────────────────────────────────────────────
// BBSU lot option (for raw material & flux lot modals)
// Cached per materialId in smelting_bbsu_lot_cache
// ─────────────────────────────────────────────
class SmeltingBbsuLot {
  final String bbsuBatchId;
  final String batchNo;
  final String materialName;
  final String materialUnit;
  final double availableQty;

  const SmeltingBbsuLot({
    required this.bbsuBatchId,
    required this.batchNo,
    required this.materialName,
    required this.materialUnit,
    required this.availableQty,
  });

  factory SmeltingBbsuLot.fromJson(Map<String, dynamic> json) {
    return SmeltingBbsuLot(
      bbsuBatchId:  json['bbsu_batch_id']?.toString() ?? '',
      batchNo:      json['batch_no']?.toString() ?? '',
      materialName: json['material_name']?.toString() ?? '',
      materialUnit: json['material_unit']?.toString() ?? 'KG',
      availableQty: _toDouble(json['available_qty']) ?? 0,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// BBSU lot selection (confirmed assignment)
// ─────────────────────────────────────────────
class BbsuSelection {
  final String bbsuId;
  final String bbsuNo;
  final double qty;

  const BbsuSelection({
    required this.bbsuId,
    required this.bbsuNo,
    required this.qty,
  });

  factory BbsuSelection.fromJson(Map<String, dynamic> json) {
    return BbsuSelection(
      bbsuId: json['bbsuId']?.toString() ?? '',
      bbsuNo: json['bbsuNo']?.toString() ?? '',
      qty:    _toDouble(json['qty']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'bbsuId': bbsuId,
    'bbsuNo': bbsuNo,
    'qty':    qty,
  };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// Raw material row
// ─────────────────────────────────────────────
class SmeltingRawMaterial {
  final String? id;
  final String rawMaterialId;
  final String? bbsuBatchId;
  final String? bbsuBatchNo;
  final List<BbsuSelection> bbsuSelections;
  final double rawMaterialQty;
  final double rawMaterialYieldPct;
  final double expectedOutputQty;

  const SmeltingRawMaterial({
    this.id,
    required this.rawMaterialId,
    this.bbsuBatchId,
    this.bbsuBatchNo,
    this.bbsuSelections = const [],
    required this.rawMaterialQty,
    required this.rawMaterialYieldPct,
    required this.expectedOutputQty,
  });

  factory SmeltingRawMaterial.fromJson(Map<String, dynamic> json) {
    final rawSel = json['bbsu_selections'];
    final sels = rawSel is List
        ? rawSel.map((s) => BbsuSelection.fromJson(s)).toList()
        : <BbsuSelection>[];
    return SmeltingRawMaterial(
      id:                  json['id']?.toString(),
      rawMaterialId:       json['raw_material_id']?.toString() ?? '',
      bbsuBatchId:         json['bbsu_batch_id']?.toString(),
      bbsuBatchNo:         json['bbsu_batch_no']?.toString(),
      bbsuSelections:      sels,
      rawMaterialQty:      _toDouble(json['raw_material_qty']) ?? 0,
      rawMaterialYieldPct: _toDouble(json['raw_material_yield_pct']) ?? 0,
      expectedOutputQty:   _toDouble(json['expected_output_qty']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'raw_material_id':       rawMaterialId,
    'bbsu_batch_id':         bbsuBatchId,
    'bbsu_batch_no':         bbsuBatchNo,
    'bbsu_selections':       bbsuSelections.map((s) => s.toJson()).toList(),
    'raw_material_qty':      rawMaterialQty,
    'raw_material_yield_pct': rawMaterialYieldPct,
    'expected_output_qty':   expectedOutputQty,
  };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// Flux / Chemical row
// ─────────────────────────────────────────────
class SmeltingFluxChemical {
  final String? id;
  final String chemicalId;
  final String? bbsuBatchId;
  final String? bbsuBatchNo;
  final List<BbsuSelection> bbsuSelections;
  final double qty;

  const SmeltingFluxChemical({
    this.id,
    required this.chemicalId,
    this.bbsuBatchId,
    this.bbsuBatchNo,
    this.bbsuSelections = const [],
    required this.qty,
  });

  factory SmeltingFluxChemical.fromJson(Map<String, dynamic> json) {
    final rawSel = json['bbsu_selections'] ?? json['flux_bbsu_selections'];
    final sels = rawSel is List
        ? rawSel.map((s) => BbsuSelection.fromJson(s)).toList()
        : <BbsuSelection>[];
    return SmeltingFluxChemical(
      id:             json['id']?.toString(),
      chemicalId:     json['chemical_id']?.toString() ?? '',
      bbsuBatchId:    json['bbsu_batch_id']?.toString(),
      bbsuBatchNo:    json['bbsu_batch_no']?.toString(),
      bbsuSelections: sels,
      qty:            _toDouble(json['qty']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'chemical_id':     chemicalId,
    'bbsu_batch_id':   bbsuBatchId,
    'bbsu_batch_no':   bbsuBatchNo,
    'bbsu_selections': bbsuSelections.map((s) => s.toJson()).toList(),
    'qty':             qty,
  };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// Process detail (one of 9 fixed rows)
// ─────────────────────────────────────────────
const kSmeltingProcessNames = [
  'CHARGING',
  'ROCKING',
  'SMELTING 1',
  'SMELTING 2',
  'SMELTING 3',
  'SMELTING 4',
  'TAPPING',
  'SLAG PROCESS',
  'SLAG TAPPING',
];

const kFiringOptions = ['Low', 'Medium', 'High'];

class SmeltingProcessDetail {
  final String processName;
  final String? startTime;
  final String? endTime;
  final int totalTime;
  final String? firingMode;

  const SmeltingProcessDetail({
    required this.processName,
    this.startTime,
    this.endTime,
    this.totalTime = 0,
    this.firingMode,
  });

  factory SmeltingProcessDetail.fromJson(Map<String, dynamic> json) {
    return SmeltingProcessDetail(
      processName: json['process_name']?.toString() ?? '',
      startTime:   json['start_time']?.toString(),
      endTime:     json['end_time']?.toString(),
      totalTime:   (_toDouble(json['total_time']) ?? 0).toInt(),
      firingMode:  json['firing_mode']?.toString(),
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Map<String, dynamic> toJson() => {
    'process_name': processName,
    'start_time':   startTime,
    'end_time':     endTime,
    'total_time':   totalTime,
    'firing_mode':  firingMode,
  };
}

// ─────────────────────────────────────────────
// Temperature record row
// ─────────────────────────────────────────────
class SmeltingTempRecord {
  final String? id;
  final String? recordTime;
  final double? insideTempBeforeCharging;
  final String? processGasChamberTemp;
  final String? shellTemp;
  final String? bagHouseTemp;

  const SmeltingTempRecord({
    this.id,
    this.recordTime,
    this.insideTempBeforeCharging,
    this.processGasChamberTemp,
    this.shellTemp,
    this.bagHouseTemp,
  });

  factory SmeltingTempRecord.fromJson(Map<String, dynamic> json) {
    return SmeltingTempRecord(
      id:                       json['id']?.toString(),
      recordTime:               json['record_time']?.toString(),
      insideTempBeforeCharging: _toDouble(json['inside_temp_before_charging']),
      processGasChamberTemp:    json['process_gas_chamber_temp']?.toString(),
      shellTemp:                json['shell_temp']?.toString(),
      bagHouseTemp:             json['bag_house_temp']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'record_time':                 recordTime,
    'inside_temp_before_charging': insideTempBeforeCharging,
    'process_gas_chamber_temp':    processGasChamberTemp,
    'shell_temp':                  shellTemp,
    'bag_house_temp':              bagHouseTemp,
  };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// Full smelting record (form / detail)
// ─────────────────────────────────────────────
class SmeltingRecord {
  final String? id;
  final String batchNo;
  final String date;
  final String rotaryNo;
  final String? chargeNo;
  final String? startTime;
  final String? endTime;
  final double? lpgConsumption;
  final double? o2Consumption;
  final double? idFanInitial;
  final double? idFanFinal;
  final double? idFanConsumption;
  final double? rotaryPowerInitial;
  final double? rotaryPowerFinal;
  final double? rotaryPowerConsumption;
  // Output — simplified: single material + qty (no block window)
  final String? outputMaterial;
  final double? outputQty;
  final List<SmeltingRawMaterial> rawMaterials;
  final List<SmeltingFluxChemical> fluxChemicals;
  final List<SmeltingProcessDetail> processDetails;
  final List<SmeltingTempRecord> temperatureRecords;
  final String? status;

  const SmeltingRecord({
    this.id,
    required this.batchNo,
    required this.date,
    required this.rotaryNo,
    this.chargeNo,
    this.startTime,
    this.endTime,
    this.lpgConsumption,
    this.o2Consumption,
    this.idFanInitial,
    this.idFanFinal,
    this.idFanConsumption,
    this.rotaryPowerInitial,
    this.rotaryPowerFinal,
    this.rotaryPowerConsumption,
    this.outputMaterial,
    this.outputQty,
    this.rawMaterials = const [],
    this.fluxChemicals = const [],
    this.processDetails = const [],
    this.temperatureRecords = const [],
    this.status,
  });

  bool get isSubmitted {
    final code = int.tryParse(status ?? '0') ?? 0;
    return code >= 1 || status == 'submitted';
  }

  factory SmeltingRecord.fromJson(Map<String, dynamic> json) {
    return SmeltingRecord(
      id:                     json['id']?.toString(),
      batchNo:                json['batch_no']?.toString() ?? '',
      date:                   json['date']?.toString() ?? '',
      rotaryNo:               json['rotary_no']?.toString() ?? '',
      chargeNo:               json['charge_no']?.toString() ?? '',
      startTime:              json['start_time']?.toString(),
      endTime:                json['end_time']?.toString(),
      lpgConsumption:         _toDouble(json['lpg_consumption']),
      o2Consumption:          _toDouble(json['o2_consumption']),
      idFanInitial:           _toDouble(json['id_fan_initial']),
      idFanFinal:             _toDouble(json['id_fan_final']),
      idFanConsumption:       _toDouble(json['id_fan_consumption']),
      rotaryPowerInitial:     _toDouble(json['rotary_power_initial']),
      rotaryPowerFinal:       _toDouble(json['rotary_power_final']),
      rotaryPowerConsumption: _toDouble(json['rotary_power_consumption']),
      outputMaterial:         json['output_material']?.toString(),
      outputQty:              _toDouble(json['output_qty']),
      rawMaterials:   (json['raw_materials'] as List? ?? [])
          .map((r) => SmeltingRawMaterial.fromJson(r)).toList(),
      fluxChemicals:  (json['flux_chemicals'] as List? ?? [])
          .map((f) => SmeltingFluxChemical.fromJson(f)).toList(),
      processDetails: (json['process_details'] as List? ?? [])
          .map((p) => SmeltingProcessDetail.fromJson(p)).toList(),
      temperatureRecords: (json['temperature_records'] as List? ?? [])
          .map((t) => SmeltingTempRecord.fromJson(t)).toList(),
      status: json['status']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'batch_no':                batchNo,
    'date':                    date,
    'rotary_no':               rotaryNo,
    'charge_no':                chargeNo,
    'start_time':              startTime,
    'end_time':                endTime,
    'lpg_consumption':         lpgConsumption,
    'o2_consumption':          o2Consumption,
    'id_fan_initial':          idFanInitial,
    'id_fan_final':            idFanFinal,
    'id_fan_consumption':      idFanConsumption,
    'rotary_power_initial':    rotaryPowerInitial,
    'rotary_power_final':      rotaryPowerFinal,
    'rotary_power_consumption': rotaryPowerConsumption,
    'output_material':         outputMaterial,
    'output_qty':              outputQty,
    'raw_materials':           rawMaterials.map((r) => r.toJson()).toList(),
    'flux_chemicals':          fluxChemicals.map((f) => f.toJson()).toList(),
    'process_details':         processDetails.map((p) => p.toJson()).toList(),
    'temperature_records':     temperatureRecords.map((t) => t.toJson()).toList(),
  };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// Summary (list screen)
// ─────────────────────────────────────────────
class SmeltingSummary {
  final String id;
  final String batchNo;
  final String date;
  final String rotaryNo;
  final String? chargeNo;
  final String? startTime;
  final String? endTime;
  final String? outputMaterialName;
  final double? outputQty;
  final String statusLabel;
  final int statusCode;
  final String syncStatus;

  const SmeltingSummary({
    required this.id,
    required this.batchNo,
    required this.date,
    required this.rotaryNo,
    this.chargeNo,
    this.startTime,
    this.endTime,
    this.outputMaterialName,
    this.outputQty,
    required this.statusLabel,
    required this.statusCode,
    this.syncStatus = 'synced',
  });

  factory SmeltingSummary.fromJson(Map<String, dynamic> json) {
    final code = int.tryParse(json['status']?.toString() ?? '0') ?? 0;
    final isSubmitted = code >= 1 || json['status'] == 'submitted';
    return SmeltingSummary(
      id:                 json['id']?.toString() ?? '',
      batchNo:            json['batch_no']?.toString() ?? '',
      date:               json['date']?.toString() ?? '',
      rotaryNo:           json['rotary_no']?.toString() ?? '',
      chargeNo:           json['charge_no']?.toString() ?? '',
      startTime:          json['start_time']?.toString(),
      endTime:            json['end_time']?.toString(),
      outputMaterialName: json['output_material_name']?.toString(),
      outputQty:          _toDouble(json['output_qty']),
      statusLabel:        isSubmitted ? 'Submitted' : 'Draft',
      statusCode:         code,
      syncStatus:         'synced',
    );
  }

  factory SmeltingSummary.fromLocal(Map<String, dynamic> row) {
    return SmeltingSummary(
      id:          row['server_id']?.toString()
          ?? 'local_${row['local_id']}',
      batchNo:     row['batch_no']?.toString() ?? '',
      date:        row['doc_date']?.toString() ?? '',
      rotaryNo:    row['rotary_no']?.toString() ?? '',
      chargeNo:    row['charge_no']?.toString() ?? '',
      startTime:   row['start_time']?.toString(),
      endTime:     row['end_time']?.toString(),
      outputQty:   _toDouble(row['output_qty']),
      statusLabel: row['status_label']?.toString() ?? 'Draft',
      statusCode:  (row['status_code'] as num?)?.toInt() ?? 0,
      syncStatus:  row['sync_status']?.toString() ?? 'pending',
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// List / Save result wrappers
// ─────────────────────────────────────────────
class SmeltingListResult {
  final List<SmeltingSummary> records;
  final int total;
  final String? errorMsg;

  bool get hasError => errorMsg != null;

  SmeltingListResult({required this.records, required this.total})
      : errorMsg = null;

  SmeltingListResult.error(this.errorMsg)
      : records = [],
        total   = 0;
}

class SmeltingSaveResult {
  final bool success;
  final String? newId;
  final String? errorMsg;
  final Map<String, dynamic> fieldErrors;

  const SmeltingSaveResult({
    required this.success,
    this.newId,
    this.errorMsg,
    this.fieldErrors = const {},
  });

  factory SmeltingSaveResult.error(String message,
      {Map<String, dynamic> errors = const {}}) {
    return SmeltingSaveResult(
      success:     false,
      errorMsg:    message,
      fieldErrors: errors,
    );
  }
}