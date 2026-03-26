// ─────────────────────────────────────────────
// Acid Testing Models
// ─────────────────────────────────────────────

// ── List summary ────────────────────────────────────────────────
class AcidTestingSummary {
  final String id;
  final String lotNumber;
  final String testDate;
  final String supplierName;
  final String vehicleNumber;
  final double avgPalletWeight;
  final double foreignMaterialWeight;
  final double avgPalletAndForeignWeight;
  final double receivedQty;
  final String statusLabel;
  final int statusCode;
  final String syncStatus;

  const AcidTestingSummary({
    required this.id,
    required this.lotNumber,
    required this.testDate,
    required this.supplierName,
    required this.vehicleNumber,
    required this.avgPalletWeight,
    required this.foreignMaterialWeight,
    required this.avgPalletAndForeignWeight,
    required this.receivedQty,
    required this.statusLabel,
    required this.statusCode,
    this.syncStatus = 'synced',
  });

  // ── From API list/detail response
  factory AcidTestingSummary.fromJson(Map<String, dynamic> json) {
    final supplier = json['supplier'] as Map<String, dynamic>?;
    return AcidTestingSummary(
      id:                          json['id']?.toString() ?? '',
      lotNumber:                   json['lot_number']?.toString() ?? '',
      testDate:                    json['test_date']?.toString() ?? '',
      supplierName:                supplier?['supplier_name']?.toString() ?? '-',
      vehicleNumber:               json['vehicle_number']?.toString() ?? '-',
      avgPalletWeight:             _toDouble(json['avg_pallet_weight']) ?? 0,
      foreignMaterialWeight:       _toDouble(json['foreign_material_weight']) ?? 0,
      avgPalletAndForeignWeight:   _toDouble(json['avg_pallet_and_foreign_weight']) ?? 0,
      receivedQty:                 _toDouble(json['received_qty']) ?? 0,
      statusLabel:                 json['status_label']?.toString() ?? 'Pending',
      statusCode:                  (json['status'] as num?)?.toInt() ?? 0,
      syncStatus:                  'synced',
    );
  }

  // ── From local SQLite row (offline)
  factory AcidTestingSummary.fromLocal(Map<String, dynamic> row) {
    return AcidTestingSummary(
      id:                        row['server_id']?.toString() ?? 'local_${row['local_id']}',
      lotNumber:                 row['lot_number']?.toString() ?? '',
      testDate:                  row['test_date']?.toString() ?? '',
      supplierName:              row['supplier_name']?.toString() ?? '-',
      vehicleNumber:             row['vehicle_number']?.toString() ?? '-',
      avgPalletWeight:           _toDouble(row['avg_pallet_weight']) ?? 0,
      foreignMaterialWeight:     _toDouble(row['foreign_material_weight']) ?? 0,
      avgPalletAndForeignWeight: _toDouble(row['avg_pallet_and_foreign_weight']) ?? 0,
      receivedQty:               _toDouble(row['received_qty']) ?? 0,
      statusLabel:               row['status_label']?.toString() ?? 'Pending',
      statusCode:                (row['status_code'] as num?)?.toInt() ?? 0,
      syncStatus:                row['sync_status']?.toString() ?? 'pending',
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ── Single record (form) ────────────────────────────────────────
class AcidTestingRecord {
  final String? id;
  final String lotNumber;
  final String testDate;
  final String? supplierId;
  final String? supplierName;
  final String? vehicleNumber;
  final double? avgPalletWeight;
  final double? foreignMaterialWeight;
  final double? avgPalletAndForeignWeight;
  final double? invoiceQty;
  final double? receivedQty;
  final int statusCode;
  final String statusLabel;
  final List<AcidTestingDetail> details;

  const AcidTestingRecord({
    this.id,
    required this.lotNumber,
    required this.testDate,
    this.supplierId,
    this.supplierName,
    this.vehicleNumber,
    this.avgPalletWeight,
    this.foreignMaterialWeight,
    this.avgPalletAndForeignWeight,
    this.invoiceQty,
    this.receivedQty,
    this.statusCode = 0,
    this.statusLabel = 'Pending',
    this.details = const [],
  });

  factory AcidTestingRecord.fromJson(Map<String, dynamic> json) {
    final supplier = json['supplier'] as Map<String, dynamic>?;
    final rawDetails = json['details'] as List<dynamic>? ?? [];
    return AcidTestingRecord(
      id:                        json['id']?.toString(),
      lotNumber:                 json['lot_number']?.toString() ?? '',
      testDate:                  json['test_date']?.toString() ?? '',
      supplierId:                json['supplier_id']?.toString()
          ?? supplier?['id']?.toString(),
      supplierName:              supplier?['supplier_name']?.toString(),
      vehicleNumber:             json['vehicle_number']?.toString(),
      avgPalletWeight:           _toDouble(json['avg_pallet_weight']),
      foreignMaterialWeight:     _toDouble(json['foreign_material_weight']),
      avgPalletAndForeignWeight: _toDouble(json['avg_pallet_and_foreign_weight']),
      invoiceQty:                _toDouble(json['invoice_qty']),
      receivedQty:               _toDouble(json['received_qty']),
      statusCode:                (json['status'] as num?)?.toInt() ?? 0,
      statusLabel:               json['status_label']?.toString() ?? 'Pending',
      details: rawDetails
          .map((d) => AcidTestingDetail.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ── Pallet row detail ───────────────────────────────────────────
class AcidTestingDetail {
  final String? id;
  final String palletNo;
  final String ulabType;     // '1000024', '1000025', '1000026', '1000028', '5'
  final double grossWeight;
  final double netWeight;
  final double? initialWeight;
  final double? drainedWeight;
  final double? weightDifference;
  final double? avgAcidPct;
  final String? remarks;

  // Whether acid columns are enabled — ulab_type == '5'
  bool get isAcidPresent => ulabType == '5';

  const AcidTestingDetail({
    this.id,
    required this.palletNo,
    required this.ulabType,
    required this.grossWeight,
    required this.netWeight,
    this.initialWeight,
    this.drainedWeight,
    this.weightDifference,
    this.avgAcidPct,
    this.remarks,
  });

  factory AcidTestingDetail.fromJson(Map<String, dynamic> json) {
    return AcidTestingDetail(
      id:               json['id']?.toString(),
      palletNo:         json['pallet_no']?.toString() ?? '',
      ulabType:         json['ulab_type']?.toString() ?? '1000024',
      grossWeight:      _toDouble(json['gross_weight']) ?? 0,
      netWeight:        _toDouble(json['net_weight']) ?? 0,
      initialWeight:    _toDouble(json['initial_weight']),
      drainedWeight:    _toDouble(json['drained_weight']),
      weightDifference: _toDouble(json['weight_difference']),
      avgAcidPct:       _toDouble(json['avg_acid_pct']),
      remarks:          json['remarks']?.toString(),
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ── Lot option (from /available-lots) ──────────────────────────
class LotOption {
  final String lotNo;
  final String supplierName;
  final String? supplierId;
  final String? vehicleNumber;
  final double? receivedQty;
  final double? invoiceQty;
  final String? receiptDate;

  const LotOption({
    required this.lotNo,
    required this.supplierName,
    this.supplierId,
    this.vehicleNumber,
    this.receivedQty,
    this.invoiceQty,
    this.receiptDate,
  });

  factory LotOption.fromJson(Map<String, dynamic> json) {
    return LotOption(
      lotNo:         json['lot_no']?.toString() ?? '',
      supplierName:  json['supplier_name']?.toString() ?? '',
      supplierId:    json['supplier_id']?.toString(),
      vehicleNumber: json['vehicle_number']?.toString(),
      receivedQty:   _toDouble(json['received_qty']),
      invoiceQty:    _toDouble(json['invoice_qty']),
      receiptDate:   json['receipt_date']?.toString(),
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ── ULAB type options ───────────────────────────────────────────
class UlabOption {
  final String id;
  final String name;
  const UlabOption({required this.id, required this.name});
}

const kUlabOptions = [
  UlabOption(id: '1000024', name: 'USED GEL BATTERY/ABS'),
  UlabOption(id: '1000025', name: 'USED TRACTION BATTERY'),
  UlabOption(id: '1000026', name: 'ULAB - MC BATTERY (DRY)'),
  UlabOption(id: '1000028', name: 'ULAB - INDUSTRIAL'),
  UlabOption(id: '5',       name: 'ACID PRESENT'),
];

// ── Result wrappers ─────────────────────────────────────────────
class AcidTestingListResult {
  final List<AcidTestingSummary> records;
  final int total;
  final String? errorMsg;

  bool get hasError => errorMsg != null;

  AcidTestingListResult({required this.records, required this.total})
      : errorMsg = null;

  AcidTestingListResult.error(this.errorMsg)
      : records = [],
        total   = 0;
}

class AcidTestingSaveResult {
  final bool success;
  final String? newId;
  final String? errorMsg;
  final Map<String, dynamic> fieldErrors;

  const AcidTestingSaveResult({
    required this.success,
    this.newId,
    this.errorMsg,
    this.fieldErrors = const {},
  });

  factory AcidTestingSaveResult.error(String message,
      {Map<String, dynamic> errors = const {}}) {
    return AcidTestingSaveResult(
      success:     false,
      errorMsg:    message,
      fieldErrors: errors,
    );
  }
}