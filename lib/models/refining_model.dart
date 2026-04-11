// ─────────────────────────────────────────────────────────────────────────────
// refining_model.dart
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────
// Material option (shared for all dropdowns)
// ─────────────────────────────────────────────
class RefiningMaterialOption {
  final String id;
  final String name;
  final String? unit;

  const RefiningMaterialOption({
    required this.id,
    required this.name,
    this.unit,
  });

  factory RefiningMaterialOption.fromJson(Map<String, dynamic> json) {
    return RefiningMaterialOption(
      id:   json['id']?.toString() ?? '',
      name: json['secondary_name']?.toString()
          ?? json['name']?.toString()
          ?? '',
      unit: json['unit']?.toString(),
    );
  }
}

// ─────────────────────────────────────────────
// Smelting lot option
// Fetched from /refining/smelting-lots/:materialId
// Cached per materialId in refining_smelting_lot_cache
// ─────────────────────────────────────────────
class RefiningSmeltingLot {
  final int materialId;
  final String smeltingBatchId;
  final String batchNo;
  final String secondaryName; // material description
  final String materialUnit;
  final double availableQty;

  const RefiningSmeltingLot({
    required this.materialId,
    required this.smeltingBatchId,
    required this.batchNo,
    required this.secondaryName,
    required this.materialUnit,
    required this.availableQty,
  });

  factory RefiningSmeltingLot.fromJson(Map<String, dynamic> json) {
    return RefiningSmeltingLot(
      materialId:  (json['material_id'] as num?)?.toInt() ?? 0,
      smeltingBatchId: json['smelting_batch_id']?.toString() ?? '',
      batchNo:         json['batch_no']?.toString() ?? '',
      secondaryName:   json['secondary_name']?.toString()
          ?? json['material_name']?.toString() ?? '',
      materialUnit:    json['material_unit']?.toString() ?? 'KG',
      availableQty:    _toDouble(json['available_qty']) ?? 0,
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
// Smelting lot selection (confirmed assignment)
// ─────────────────────────────────────────────
class SmeltingSelection {
  final String smtId;
  final String smtNo;
  final double qty;

  const SmeltingSelection({
    required this.smtId,
    required this.smtNo,
    required this.qty,
  });

  factory SmeltingSelection.fromJson(Map<String, dynamic> json) {
    return SmeltingSelection(
      smtId: json['smtId']?.toString() ?? '',
      smtNo: json['smtNo']?.toString() ?? '',
      qty:   _toDouble(json['qty']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'smtId': smtId,
    'smtNo': smtNo,
    'qty':   qty,
  };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// Output block (one ingot/block weight entry)
// Used for both Finished Goods and Dross rows
// ─────────────────────────────────────────────
class RefiningOutputBlock {
  final String? materialId;
  final int blockSlNo;
  final double blockWeight;

  const RefiningOutputBlock({
    this.materialId,
    required this.blockSlNo,
    required this.blockWeight,
  });

  factory RefiningOutputBlock.fromJson(Map<String, dynamic> json) {
    return RefiningOutputBlock(
      materialId:  json['material_id']?.toString(),
      blockSlNo:   (json['block_sl_no'] as num?)?.toInt() ?? 0,
      blockWeight: _toDouble(json['block_weight']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'material_id': materialId,
    'block_sl_no': blockSlNo,
    'block_weight': blockWeight,
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
class RefiningRawMaterial {
  final String? id;
  final String rawMaterialId;
  final double qty;
  final String? smeltingBatchId;
  final String? smeltingBatchNo;
  final List<SmeltingSelection> smeltingSelections;

  const RefiningRawMaterial({
    this.id,
    required this.rawMaterialId,
    required this.qty,
    this.smeltingBatchId,
    this.smeltingBatchNo,
    this.smeltingSelections = const [],
  });

  factory RefiningRawMaterial.fromJson(Map<String, dynamic> json) {
    final rawSel = json['smelting_selections'];
    final sels = rawSel is List
        ? rawSel.map((s) => SmeltingSelection.fromJson(s)).toList()
        : <SmeltingSelection>[];
    return RefiningRawMaterial(
      id:                  json['id']?.toString(),
      rawMaterialId:       json['raw_material_id']?.toString() ?? '',
      qty:                 _toDouble(json['qty']) ?? 0,
      smeltingBatchId:     json['smelting_batch_id']?.toString(),
      smeltingBatchNo:     json['smelting_batch_no']?.toString(),
      smeltingSelections:  sels,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'raw_material_id':    rawMaterialId,
    'qty':                qty,
    'smelting_batch_id':  smeltingBatchId,
    'smelting_batch_no':  smeltingBatchNo,
    'smelting_selections': smeltingSelections.map((s) => s.toJson()).toList(),
  };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// Chemical / Metal row
// ─────────────────────────────────────────────
class RefiningChemical {
  final String? id;
  final String chemicalId;
  final double qty;
  final String? smeltingBatchId;
  final String? smeltingBatchNo;
  final List<SmeltingSelection> smeltingSelections;

  const RefiningChemical({
    this.id,
    required this.chemicalId,
    required this.qty,
    this.smeltingBatchId,
    this.smeltingBatchNo,
    this.smeltingSelections = const [],
  });

  factory RefiningChemical.fromJson(Map<String, dynamic> json) {
    final rawSel = json['smelting_selections'];
    final sels = rawSel is List
        ? rawSel.map((s) => SmeltingSelection.fromJson(s)).toList()
        : <SmeltingSelection>[];
    return RefiningChemical(
      id:                  json['id']?.toString(),
      chemicalId:          json['chemical_id']?.toString() ?? '',
      qty:                 _toDouble(json['qty']) ?? 0,
      smeltingBatchId:     json['smelting_batch_id']?.toString(),
      smeltingBatchNo:     json['smelting_batch_no']?.toString(),
      smeltingSelections:  sels,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'chemical_id':         chemicalId,
    'qty':                 qty,
    'smelting_batch_id':   smeltingBatchId,
    'smelting_batch_no':   smeltingBatchNo,
    'smelting_selections': smeltingSelections.map((s) => s.toJson()).toList(),
  };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// Process detail row (dynamic — names from API)
// ─────────────────────────────────────────────
class RefiningProcessDetail {
  final String? id;
  final String refiningProcess;
  final String? startTime;
  final String? endTime;
  final int totalMins;

  const RefiningProcessDetail({
    this.id,
    required this.refiningProcess,
    this.startTime,
    this.endTime,
    this.totalMins = 0,
  });

  factory RefiningProcessDetail.fromJson(Map<String, dynamic> json) {
    return RefiningProcessDetail(
      id:              json['id']?.toString(),
      refiningProcess: json['refining_process']?.toString() ?? '',
      startTime:       json['start_time']?.toString(),
      endTime:         json['end_time']?.toString(),
      totalMins:       (json['total_mins'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'refining_process': refiningProcess,
    'start_time':       startTime,
    'end_time':         endTime,
  };
}

// ─────────────────────────────────────────────
// Finished Goods output row
// ─────────────────────────────────────────────
class RefiningFinishedGood {
  final String? id;
  final String materialId;
  final double totalQty;
  final List<RefiningOutputBlock> outputBlocks;

  const RefiningFinishedGood({
    this.id,
    required this.materialId,
    required this.totalQty,
    this.outputBlocks = const [],
  });

  factory RefiningFinishedGood.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['output_blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks.map((b) => RefiningOutputBlock.fromJson(b)).toList()
        : <RefiningOutputBlock>[];
    return RefiningFinishedGood(
      id:           json['id']?.toString(),
      materialId:   json['material_id']?.toString() ?? '',
      totalQty:     _toDouble(json['total_qty']) ?? 0,
      outputBlocks: blocks,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'material_id': materialId,
    'total_qty':   totalQty,
    'output_blocks': outputBlocks.map((b) => b.toJson()).toList(),
  };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// Dross output row
// ─────────────────────────────────────────────
class RefiningDross {
  final String? id;
  final String materialId;
  final double totalQty;
  final List<RefiningOutputBlock> outputBlocks;

  const RefiningDross({
    this.id,
    required this.materialId,
    required this.totalQty,
    this.outputBlocks = const [],
  });

  factory RefiningDross.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['output_blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks.map((b) => RefiningOutputBlock.fromJson(b)).toList()
        : <RefiningOutputBlock>[];
    return RefiningDross(
      id:           json['id']?.toString(),
      materialId:   json['material_id']?.toString() ?? '',
      totalQty:     _toDouble(json['total_qty']) ?? 0,
      outputBlocks: blocks,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'material_id': materialId,
    'total_qty':   totalQty,
    'output_blocks': outputBlocks.map((b) => b.toJson()).toList(),
  };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// Full refining record (form / detail)
// ─────────────────────────────────────────────
class RefiningRecord {
  final String? id;
  final String batchNo;
  final String? potNo;
  final String? materialId;
  final String date;

  // Consumption
  final double? lpgInitial;
  final double? lpgFinal;
  final double? lpg2Initial ;
  final double? lpg2Final  ;
  final double? lpgConsumption;
  final double? electricityInitial;
  final double? electricityFinal;
  final double? electricityConsumption;
  final double? oxygenFlowNm3;
  final double? oxygenFlowKg;
  final double? oxygenFlowTime;
  final double? oxygenConsumption;

  // Nested
  final List<RefiningRawMaterial>   rawMaterials;
  final List<RefiningChemical>      chemicals;
  final List<RefiningProcessDetail> processDetails;
  final List<RefiningFinishedGood>  finishedGoodsSummary;
  final List<RefiningDross>         drossSummary;

  final String? status;

  const RefiningRecord({
    this.id,
    required this.batchNo,
    this.potNo,
    this.materialId,
    required this.date,
    this.lpgInitial,
    this.lpgFinal,
    this.lpg2Initial ,
    this.lpg2Final,
    this.lpgConsumption,
    this.electricityInitial,
    this.electricityFinal,
    this.electricityConsumption,
    this.oxygenFlowNm3,
    this.oxygenFlowKg,
    this.oxygenFlowTime,
    this.oxygenConsumption,
    this.rawMaterials     = const [],
    this.chemicals        = const [],
    this.processDetails   = const [],
    this.finishedGoodsSummary = const [],
    this.drossSummary     = const [],
    this.status,
  });

  bool get isSubmitted {
    final code = int.tryParse(status ?? '0') ?? 0;
    return code >= 1 || status == 'submitted';
  }

  factory RefiningRecord.fromJson(Map<String, dynamic> json) {
    return RefiningRecord(
      id:                      json['id']?.toString(),
      batchNo:                 json['batch_no']?.toString() ?? '',
      potNo:                   json['pot_no']?.toString(),
      materialId:              json['material_id']?.toString(),
      date:                    json['date']?.toString() ?? '',
      lpgInitial:              _toDouble(json['lpg_initial']),
      lpgFinal:                _toDouble(json['lpg_final']),
      lpg2Initial:              _toDouble(json['lpg2_initial']),
      lpg2Final:                _toDouble(json['lpg2_final']),
      lpgConsumption:          _toDouble(json['lpg_consumption']),
      electricityInitial:      _toDouble(json['electricity_initial']),
      electricityFinal:        _toDouble(json['electricity_final']),
      electricityConsumption:  _toDouble(json['electricity_consumption']),
      oxygenFlowNm3:           _toDouble(json['oxygen_flow_nm3']),
      oxygenFlowKg:            _toDouble(json['oxygen_flow_kg']),
      oxygenFlowTime:          _toDouble(json['oxygen_flow_time']),
      oxygenConsumption:       _toDouble(json['oxygen_consumption']),
      rawMaterials: (json['raw_materials'] as List? ?? [])
          .map((r) => RefiningRawMaterial.fromJson(r)).toList(),
      chemicals: (json['chemicals'] as List? ?? [])
          .map((c) => RefiningChemical.fromJson(c)).toList(),
      processDetails: (json['process_details'] as List? ?? [])
          .map((p) => RefiningProcessDetail.fromJson(p)).toList(),
      finishedGoodsSummary: (json['finished_goods_summary'] as List? ?? [])
          .map((f) => RefiningFinishedGood.fromJson(f)).toList(),
      drossSummary: (json['dross_summary'] as List? ?? [])
          .map((d) => RefiningDross.fromJson(d)).toList(),
      status: json['status']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'batch_no':   batchNo,
    'pot_no':     potNo,
    'material_id': materialId,
    'date':       date,
    'lpg_initial':              lpgInitial,
    'lpg_final':                lpgFinal,
    'lpg_consumption':          lpgConsumption,
    'electricity_initial':      electricityInitial,
    'electricity_final':        electricityFinal,
    'electricity_consumption':  electricityConsumption,
    'oxygen_flow_nm3':          oxygenFlowNm3,
    'oxygen_flow_kg':           oxygenFlowKg,
    'oxygen_flow_time':         oxygenFlowTime,
    'oxygen_consumption':       oxygenConsumption,
    'raw_materials':            rawMaterials.map((r) => r.toJson()).toList(),
    'chemicals':                chemicals.map((c) => c.toJson()).toList(),
    'process_details':          processDetails.map((p) => p.toJson()).toList(),
    'finished_goods_summary':   finishedGoodsSummary.map((f) => f.toJson()).toList(),
    'dross_summary':            drossSummary.map((d) => d.toJson()).toList(),
    // Flattened blocks for API
    'finished_goods_blocks': finishedGoodsSummary
        .expand((f) => f.outputBlocks.map((b) => b.toJson())).toList(),
    'dross_blocks': drossSummary
        .expand((d) => d.outputBlocks.map((b) => b.toJson())).toList(),
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
// Columns: batch_no | pot_no | material | date |
//          lpg_consumption | electricity_consumption | status
// ─────────────────────────────────────────────
class RefiningSummary {
  final String id;
  final String batchNo;
  final String? potNo;
  final String? materialName;
  final String date;
  final double? lpgConsumption;
  final double? electricityConsumption;
  final String statusLabel;
  final int statusCode;
  final String syncStatus;

  const RefiningSummary({
    required this.id,
    required this.batchNo,
    this.potNo,
    this.materialName,
    required this.date,
    this.lpgConsumption,
    this.electricityConsumption,
    required this.statusLabel,
    required this.statusCode,
    this.syncStatus = 'synced',
  });

  factory RefiningSummary.fromJson(Map<String, dynamic> json) {
    final code        = (json['status'] as num?)?.toInt() ?? 0;
    final isSubmitted = code >= 1 || json['status'] == 'submitted';
    return RefiningSummary(
      id:                    json['id']?.toString() ?? '',
      batchNo:               json['batch_no']?.toString() ?? '',
      potNo:                 json['pot_no']?.toString(),
      materialName:          json['material']?['name']?.toString()
          ?? json['material_name']?.toString(),
      date:                  json['date']?.toString() ?? '',
      lpgConsumption:        _toDouble(json['lpg_consumption']),
      electricityConsumption: _toDouble(json['electricity_consumption']),
      statusLabel:           isSubmitted ? 'Submitted' : 'Draft',
      statusCode:            code,
      syncStatus:            'synced',
    );
  }

  factory RefiningSummary.fromLocal(Map<String, dynamic> row) {
    return RefiningSummary(
      id:                    row['server_id']?.toString()
          ?? 'local_${row['local_id']}',
      batchNo:               row['batch_no']?.toString() ?? '',
      potNo:                 row['pot_no']?.toString(),
      date:                  row['doc_date']?.toString() ?? '',
      lpgConsumption:        _toDouble(row['lpg_consumption']),
      electricityConsumption: _toDouble(row['electricity_consumption']),
      statusLabel:           row['status_label']?.toString() ?? 'Draft',
      statusCode:            (row['status_code'] as num?)?.toInt() ?? 0,
      syncStatus:            row['sync_status']?.toString() ?? 'pending',
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
// Result wrappers
// ─────────────────────────────────────────────
class RefiningListResult {
  final List<RefiningSummary> records;
  final int total;
  final String? errorMsg;

  bool get hasError => errorMsg != null;

  RefiningListResult({required this.records, required this.total})
      : errorMsg = null;

  RefiningListResult.error(this.errorMsg)
      : records = [],
        total   = 0;
}

class RefiningSaveResult {
  final bool success;
  final String? newId;
  final String? errorMsg;
  final Map<String, dynamic> fieldErrors;

  const RefiningSaveResult({
    required this.success,
    this.newId,
    this.errorMsg,
    this.fieldErrors = const {},
  });

  factory RefiningSaveResult.error(String message,
      {Map<String, dynamic> errors = const {}}) {
    return RefiningSaveResult(
      success:     false,
      errorMsg:    message,
      fieldErrors: errors,
    );
  }
}