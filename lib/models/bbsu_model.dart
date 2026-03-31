// ─────────────────────────────────────────────────────────────────────────────
// bbsu_model.dart
// Data models for the Battery Breaking & Separation Unit (BBSU) module.
//
// Matches Laravel Blade fields:
//   Primary  : batch_no, doc_date, category, start_time, end_time
//   Input    : lot_no, quantity, acid_percentage  (multiple rows)
//   Output   : 9 fixed material codes → qty, yield_pct
//   Power    : initial_power, final_power, total_power_consumption
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────
// BBSU category options (matches Blade <select>)
// ─────────────────────────────────────────────
enum BbsuCategory { bbsu, manualCutting }

extension BbsuCategoryExt on BbsuCategory {
  String get value {
    switch (this) {
      case BbsuCategory.bbsu:          return 'BBSU';
      case BbsuCategory.manualCutting: return 'MANUAL_CUTTING';
    }
  }

  String get label {
    switch (this) {
      case BbsuCategory.bbsu:          return 'BBSU';
      case BbsuCategory.manualCutting: return 'Manual Cutting';
    }
  }

  static BbsuCategory fromValue(String v) {
    switch (v) {
      case 'MANUAL_CUTTING': return BbsuCategory.manualCutting;
      default:               return BbsuCategory.bbsu;
    }
  }
}

// ─────────────────────────────────────────────
// 9 fixed output materials
// Hardcoded — always works offline.
// Order matches Blade OUTPUT_KEYS array exactly.
// ─────────────────────────────────────────────
class BbsuOutputMaterial {
  final String code; // material_code (e.g. '1007')
  final String key;  // internal key  (e.g. 'metallic')
  final String name; // display name

  const BbsuOutputMaterial({
    required this.code,
    required this.key,
    required this.name,
  });
}

const kBbsuOutputMaterials = [
  BbsuOutputMaterial(code: '1007', key: 'metallic',       name: 'Metallic'),
  BbsuOutputMaterial(code: '1008', key: 'paste',          name: 'Paste'),
  BbsuOutputMaterial(code: '1019', key: 'fines',          name: 'Fines'),
  BbsuOutputMaterial(code: '1005', key: 'pp_chips',       name: 'PP Chips'),
  BbsuOutputMaterial(code: '1023', key: 'abs_chips',      name: 'ABS Chips'),
  BbsuOutputMaterial(code: '1006', key: 'separator',      name: 'Separator'),
  BbsuOutputMaterial(code: '1055', key: 'battery_plates', name: 'Battery Plates'),
  BbsuOutputMaterial(code: '1057', key: 'terminals',      name: 'Terminals'),
  BbsuOutputMaterial(code: '1267', key: 'acid',           name: 'Acid'),
];

// ─────────────────────────────────────────────
// Lot option for BBSU lot dropdown
// Fetched from /bbsu-batches/acid-test-lot-numbers
// Cached to bbsu_lot_cache in SQLite.
// ─────────────────────────────────────────────
class BbsuLotOption {
  final String lotNumber;
  final String? supplierName;
  final double? receivedQty; // used offline for qty assignment
  final double? acidPct;     // avg acid % from acid testing

  const BbsuLotOption({
    required this.lotNumber,
    this.supplierName,
    this.receivedQty,
    this.acidPct,
  });

  factory BbsuLotOption.fromJson(Map<String, dynamic> json) {
    return BbsuLotOption(
      lotNumber:    json['lot_number']?.toString() ?? '',
      supplierName: json['supplier_name']?.toString(),
      receivedQty:  _toDouble(json['received_qty']),
      acidPct:      _toDouble(json['avg_acid_pct']),
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
// Input lot row (one row in the Input Lots table)
// ─────────────────────────────────────────────
class BbsuInputDetail {
  final String? id;
  final String lotNo;
  final double quantity;
  final double acidPercentage;

  const BbsuInputDetail({
    this.id,
    required this.lotNo,
    required this.quantity,
    required this.acidPercentage,
  });

  factory BbsuInputDetail.fromJson(Map<String, dynamic> json) {
    return BbsuInputDetail(
      id:             json['id']?.toString(),
      lotNo:          json['lot_no']?.toString() ?? '',
      quantity:       _toDouble(json['quantity']) ?? 0,
      acidPercentage: _toDouble(json['acid_percentage']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'lot_no':          lotNo,
    'quantity':        quantity,
    'acid_percentage': acidPercentage,
  };

  BbsuInputDetail copyWith({
    String? id,
    String? lotNo,
    double? quantity,
    double? acidPercentage,
  }) {
    return BbsuInputDetail(
      id:             id             ?? this.id,
      lotNo:          lotNo          ?? this.lotNo,
      quantity:       quantity       ?? this.quantity,
      acidPercentage: acidPercentage ?? this.acidPercentage,
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
// Output material row (one of 9 fixed materials)
// ─────────────────────────────────────────────
class BbsuOutputDetail {
  final String materialCode;
  final double qty;
  final double yieldPct; // auto-calc: (qty / total_input) * 100

  const BbsuOutputDetail({
    required this.materialCode,
    required this.qty,
    required this.yieldPct,
  });

  factory BbsuOutputDetail.fromJson(Map<String, dynamic> json) {
    return BbsuOutputDetail(
      materialCode: json['material_code']?.toString() ?? '',
      qty:          _toDouble(json['qty']) ?? 0,
      yieldPct:     _toDouble(json['yield_pct']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'qty': qty,
  };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// Power consumption section
// ─────────────────────────────────────────────
class BbsuPowerConsumption {
  final double initialPower;
  final double finalPower;
  final double totalPowerConsumption; // auto-calc: final - initial

  const BbsuPowerConsumption({
    required this.initialPower,
    required this.finalPower,
    required this.totalPowerConsumption,
  });

  factory BbsuPowerConsumption.fromJson(Map<String, dynamic> json) {
    return BbsuPowerConsumption(
      initialPower:           _toDouble(json['initial_power']) ?? 0,
      finalPower:             _toDouble(json['final_power']) ?? 0,
      totalPowerConsumption:  _toDouble(json['total_power_consumption']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'initial_power':            initialPower,
    'final_power':              finalPower,
    'total_power_consumption':  totalPowerConsumption,
  };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────
// Full BBSU record (form / detail)
// ─────────────────────────────────────────────
class BbsuRecord {
  final String? id;
  final String batchNo;
  final String docDate;
  final String category;
  final String startTime;
  final String endTime;
  final List<BbsuInputDetail> inputDetails;
  final Map<String, BbsuOutputDetail> outputMaterials; // keyed by material_code
  final BbsuPowerConsumption? powerConsumption;
  final String? status; // '0' = draft, '1' = submitted

  const BbsuRecord({
    this.id,
    required this.batchNo,
    required this.docDate,
    required this.category,
    required this.startTime,
    required this.endTime,
    this.inputDetails = const [],
    this.outputMaterials = const {},
    this.powerConsumption,
    this.status,
  });

  bool get isSubmitted => (int.tryParse(status ?? '0') ?? 0) >= 1;
  bool get isDraft     => !isSubmitted;

  factory BbsuRecord.fromJson(Map<String, dynamic> json) {
    // Input details
    final rawInputs = json['input_details'] as List? ?? [];
    final inputs = rawInputs
        .map((d) => BbsuInputDetail.fromJson(d))
        .toList();

    // Output materials — array of { material_code, qty, yield_pct }
    final rawOutputs = json['output_materials'] as List? ?? [];
    final outputs = <String, BbsuOutputDetail>{};
    for (final o in rawOutputs) {
      final code = o['material_code']?.toString() ?? '';
      if (code.isNotEmpty) {
        outputs[code] = BbsuOutputDetail.fromJson(o);
      }
    }

    // Power
    BbsuPowerConsumption? power;
    if (json['power_consumption'] != null) {
      power = BbsuPowerConsumption.fromJson(
          json['power_consumption'] as Map<String, dynamic>);
    }

    return BbsuRecord(
      id:               json['id']?.toString(),
      batchNo:          json['batch_no']?.toString() ?? '',
      docDate:          json['doc_date']?.toString() ?? '',
      category:         json['category']?.toString() ?? 'BBSU',
      startTime:        json['start_time']?.toString() ?? '',
      endTime:          json['end_time']?.toString() ?? '',
      inputDetails:     inputs,
      outputMaterials:  outputs,
      powerConsumption: power,
      status:           json['status']?.toString(),
    );
  }

  /// Builds the full nested payload for POST/PUT.
  /// output_material is keyed by material_code with { qty } value.
  Map<String, dynamic> toJson() {
    final outputMat = <String, dynamic>{};
    for (final mat in kBbsuOutputMaterials) {
      final detail = outputMaterials[mat.code];
      outputMat[mat.code] = {'qty': detail?.qty ?? 0};
    }

    return {
      if (id != null) 'id': id,
      'batch_no':   batchNo,
      'doc_date':   docDate,
      'category':   category,
      'start_time': startTime,
      'end_time':   endTime,
      'input_details':   inputDetails.map((d) => d.toJson()).toList(),
      'output_material': outputMat,
      'power_consumption': powerConsumption?.toJson() ?? {
        'initial_power': 0,
        'final_power':   0,
        'total_power_consumption': 0,
      },
    };
  }

  BbsuRecord copyWith({
    String? id,
    String? batchNo,
    String? docDate,
    String? category,
    String? startTime,
    String? endTime,
    List<BbsuInputDetail>? inputDetails,
    Map<String, BbsuOutputDetail>? outputMaterials,
    BbsuPowerConsumption? powerConsumption,
    String? status,
  }) {
    return BbsuRecord(
      id:               id               ?? this.id,
      batchNo:          batchNo          ?? this.batchNo,
      docDate:          docDate          ?? this.docDate,
      category:         category         ?? this.category,
      startTime:        startTime        ?? this.startTime,
      endTime:          endTime          ?? this.endTime,
      inputDetails:     inputDetails     ?? this.inputDetails,
      outputMaterials:  outputMaterials  ?? this.outputMaterials,
      powerConsumption: powerConsumption ?? this.powerConsumption,
      status:           status           ?? this.status,
    );
  }
}

// ─────────────────────────────────────────────
// Summary (list screen)
// ─────────────────────────────────────────────
class BbsuSummary {
  final String id;
  final String batchNo;
  final String docDate;
  final String startTime;
  final String endTime;
  final String category;
  final String statusLabel; // 'Draft' | 'Submitted'
  final int statusCode;     // 0 = draft, 1 = submitted
  final String syncStatus;  // 'synced' | 'pending'

  const BbsuSummary({
    required this.id,
    required this.batchNo,
    required this.docDate,
    required this.startTime,
    required this.endTime,
    required this.category,
    required this.statusLabel,
    required this.statusCode,
    this.syncStatus = 'synced',
  });

  factory BbsuSummary.fromJson(Map<String, dynamic> json) {
    final code = (json['status'] as num?)?.toInt() ?? 0;
    return BbsuSummary(
      id:          json['id']?.toString() ?? '',
      batchNo:     json['batch_no']?.toString() ?? '',
      docDate:     json['doc_date']?.toString() ?? '',
      startTime:   json['start_time']?.toString() ?? '',
      endTime:     json['end_time']?.toString() ?? '',
      category:    json['category']?.toString() ?? '',
      statusLabel: code >= 1 ? 'Submitted' : 'Draft',
      statusCode:  code,
      syncStatus:  'synced',
    );
  }

  factory BbsuSummary.fromLocal(Map<String, dynamic> row) {
    return BbsuSummary(
      id:          row['server_id']?.toString() ?? 'local_${row['local_id']}',
      batchNo:     row['batch_no']?.toString() ?? '',
      docDate:     row['doc_date']?.toString() ?? '',
      startTime:   row['start_time']?.toString() ?? '',
      endTime:     row['end_time']?.toString() ?? '',
      category:    row['category']?.toString() ?? '',
      statusLabel: row['status_label']?.toString() ?? 'Draft',
      statusCode:  (row['status_code'] as num?)?.toInt() ?? 0,
      syncStatus:  row['sync_status']?.toString() ?? 'pending',
    );
  }
}

// ─────────────────────────────────────────────
// List result wrapper
// ─────────────────────────────────────────────
class BbsuListResult {
  final List<BbsuSummary> records;
  final int total;
  final String? errorMsg;

  bool get hasError => errorMsg != null;

  BbsuListResult({required this.records, required this.total})
      : errorMsg = null;

  BbsuListResult.error(this.errorMsg)
      : records = [],
        total   = 0;
}

// ─────────────────────────────────────────────
// Save result
// ─────────────────────────────────────────────
class BbsuSaveResult {
  final bool success;
  final String? newId;
  final String? errorMsg;
  final Map<String, dynamic> fieldErrors;

  const BbsuSaveResult({
    required this.success,
    this.newId,
    this.errorMsg,
    this.fieldErrors = const {},
  });

  factory BbsuSaveResult.error(String message,
      {Map<String, dynamic> errors = const {}}) {
    return BbsuSaveResult(
      success:     false,
      errorMsg:    message,
      fieldErrors: errors,
    );
  }
}