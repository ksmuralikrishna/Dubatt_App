// ─────────────────────────────────────────────────────────────────────────────
// acid_testing_model.dart
// Data models for the Acid Testing module.
//
// Matches Laravel fields:
//   acid_testings table  → AcidTestingRecord  (form / detail)
//   acid_testings table  → AcidTestingSummary (list screen)
//   acid_testing_details → AcidTestingDetail  (pallet rows)
//   receiving_records    → LotOption          (lot SDD dropdown)
// ─────────────────────────────────────────────────────────────────────────────

// ── ULAB types ───────────────────────────────────────────────────────────────

class UlabOption {
  final int id;
  final String name;

  const UlabOption({required this.id, required this.name});

  /// Whether this ULAB type requires acid columns
  /// (id == 5 == ACID_PRESENT in the Blade)
  bool get isAcidPresent => id == 5;
}

const kUlabOptions = [
  UlabOption(id: 1000024, name: 'USED GEL BATTERY/ABS'),
  UlabOption(id: 1000025, name: 'USED TRACTION BATTERY'),
  UlabOption(id: 1000026, name: 'ULAB - MC BATTERY (DRY)'),
  UlabOption(id: 1000028, name: 'ULAB - INDUSTRIAL'),
  UlabOption(id: 5,       name: 'ACID PRESENT'),
];

// ── Lot option (SDD searchable dropdown) ─────────────────────────────────────

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

// ── Pallet / detail row ───────────────────────────────────────────────────────

class AcidTestingDetail {
  final String? id;
  final String palletNo;
  final int ulabType;          // matches ULAB_OPTIONS ids in Blade
  final double grossWeight;
  final double? netWeight;     // auto-calc: gross - avgPalletForeign
  final double? initialWeight; // acid columns — only when ulabType == 5
  final double? drainedWeight;
  final double? weightDiff;    // auto-calc: initial - drained
  final double? acidPct;       // auto-calc: (diff / initial) * 100

  const AcidTestingDetail({
    this.id,
    required this.palletNo,
    required this.ulabType,
    required this.grossWeight,
    this.netWeight,
    this.initialWeight,
    this.drainedWeight,
    this.weightDiff,
    this.acidPct,
  });

  bool get isAcidPresent => ulabType == 5;

  factory AcidTestingDetail.fromJson(Map<String, dynamic> json) {
    // Blade maps ACID_PRESENT id < 1000024 back to 5
    int ulab = _toInt(json['ulab_type']) ?? 1000024;
    if (ulab < 1000024 && ulab != 5) ulab = 5;

    return AcidTestingDetail(
      id:            json['id']?.toString(),
      palletNo:      json['pallet_no']?.toString() ?? '',
      ulabType:      ulab,
      grossWeight:   _toDouble(json['gross_weight']) ?? 0,
      netWeight:     _toDouble(json['net_weight']),
      initialWeight: _toDouble(json['initial_weight']),
      drainedWeight: _toDouble(json['drained_weight']),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'pallet_no':      palletNo,
    'ulab_type':      ulabType,
    'gross_weight':   grossWeight,
    'net_weight':     netWeight,
    'initial_weight': initialWeight,
    'drained_weight': drainedWeight,
    'remarks':        ulabType.toString(), // mirrors Blade: remarks = ulab
  };

  AcidTestingDetail copyWith({
    String? id,
    String? palletNo,
    int? ulabType,
    double? grossWeight,
    double? netWeight,
    double? initialWeight,
    double? drainedWeight,
    double? weightDiff,
    double? acidPct,
  }) {
    return AcidTestingDetail(
      id:            id            ?? this.id,
      palletNo:      palletNo      ?? this.palletNo,
      ulabType:      ulabType      ?? this.ulabType,
      grossWeight:   grossWeight   ?? this.grossWeight,
      netWeight:     netWeight     ?? this.netWeight,
      initialWeight: initialWeight ?? this.initialWeight,
      drainedWeight: drainedWeight ?? this.drainedWeight,
      weightDiff:    weightDiff    ?? this.weightDiff,
      acidPct:       acidPct       ?? this.acidPct,
    );
  }

  // ── Computed values ────────────────────────────────────────────────────────

  /// net = gross - avgPalletForeign
  double calcNet(double avgPalletForeign) =>
      grossWeight > 0 ? (grossWeight - avgPalletForeign).clamp(0, double.infinity) : 0;

  /// diff = initial - drained  (acid rows only)
  double get calcDiff =>
      (isAcidPresent && (initialWeight ?? 0) > 0)
          ? ((initialWeight! - (drainedWeight ?? 0)).clamp(0, double.infinity))
          : 0;

  /// acid% = (diff / initial) * 100  (acid rows only)
  double get calcAcidPct =>
      (isAcidPresent && (initialWeight ?? 0) > 0)
          ? (calcDiff / initialWeight!) * 100
          : 0;

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}

// ── Acid category (result banner) ─────────────────────────────────────────────

enum AcidCategory { high, normal, low, dry, none }

extension AcidCategoryExt on AcidCategory {
  String get label {
    switch (this) {
      case AcidCategory.high:   return 'High Acid';
      case AcidCategory.normal: return 'Normal';
      case AcidCategory.low:    return 'Low Acid';
      case AcidCategory.dry:    return 'Dry / Empty';
      case AcidCategory.none:   return '';
    }
  }

  String get rule {
    switch (this) {
      case AcidCategory.high:   return 'Avg Acid % > 30%';
      case AcidCategory.normal: return '15% ≤ Avg Acid % ≤ 30%';
      case AcidCategory.low:    return '5% ≤ Avg Acid % < 15%';
      case AcidCategory.dry:    return 'Avg Acid % < 5%';
      case AcidCategory.none:   return '';
    }
  }
}

AcidCategory acidCategoryFromPct(double? pct) {
  if (pct == null) return AcidCategory.none;
  if (pct > 30)    return AcidCategory.high;
  if (pct >= 15)   return AcidCategory.normal;
  if (pct >= 5)    return AcidCategory.low;
  return AcidCategory.dry;
}

// ── Full record (form / detail) ───────────────────────────────────────────────

class AcidTestingRecord {
  final String? id;
  final String testDate;
  final String lotNumber;
  final String? supplierId;
  final String? supplierName;
  final String? vehicleNumber;
  final double avgPalletWeight;
  final double foreignMaterialWeight;
  final double avgPalletAndForeignWeight; // auto-calc
  final double? receivedQty;             // inhouse_weight (from lot)
  final double? invoiceQty;
  final List<AcidTestingDetail> details;
  final String? status;                  // '0' = draft, '1' = submitted

  const AcidTestingRecord({
    this.id,
    required this.testDate,
    required this.lotNumber,
    this.supplierId,
    this.supplierName,
    this.vehicleNumber,
    this.avgPalletWeight = 0,
    this.foreignMaterialWeight = 0,
    this.avgPalletAndForeignWeight = 0,
    this.receivedQty,
    this.invoiceQty,
    this.details = const [],
    this.status,
  });

  bool get isSubmitted => (int.tryParse(status ?? '0') ?? 0) >= 1;

  factory AcidTestingRecord.fromJson(Map<String, dynamic> json) {
    final supplier = json['supplier'] as Map<String, dynamic>?;
    final rawDetails = json['details'] as List? ?? [];

    return AcidTestingRecord(
      id:                          json['id']?.toString(),
      testDate:                    json['test_date']?.toString() ?? '',
      lotNumber:                   json['lot_number']?.toString() ?? '',
      supplierId:                  json['supplier_id']?.toString()
          ?? supplier?['id']?.toString(),
      supplierName:                supplier?['supplier_name']?.toString(),
      vehicleNumber:               json['vehicle_number']?.toString(),
      avgPalletWeight:             _toDouble(json['avg_pallet_weight']) ?? 0,
      foreignMaterialWeight:       _toDouble(json['foreign_material_weight']) ?? 0,
      avgPalletAndForeignWeight:   _toDouble(json['avg_pallet_and_foreign_weight']) ?? 0,
      receivedQty:                 _toDouble(json['received_qty']),
      invoiceQty:                  _toDouble(json['invoice_qty']),
      details:                     rawDetails
          .map((d) => AcidTestingDetail.fromJson(d))
          .toList(),
      status:                      json['status']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'test_date':                    testDate,
    'lot_number':                   lotNumber,
    'supplier_id':                  supplierId,
    'vehicle_number':               vehicleNumber,
    'avg_pallet_weight':            avgPalletWeight,
    'foreign_material_weight':      foreignMaterialWeight,
    'avg_pallet_and_foreign_weight': avgPalletAndForeignWeight,
    'received_qty':                 receivedQty,
    'invoice_qty':                  invoiceQty,
    'details':                      details.map((d) => d.toJson()).toList(),
  };

  AcidTestingRecord copyWith({
    String? id,
    String? testDate,
    String? lotNumber,
    String? supplierId,
    String? supplierName,
    String? vehicleNumber,
    double? avgPalletWeight,
    double? foreignMaterialWeight,
    double? avgPalletAndForeignWeight,
    double? receivedQty,
    double? invoiceQty,
    List<AcidTestingDetail>? details,
    String? status,
  }) {
    return AcidTestingRecord(
      id:                          id                          ?? this.id,
      testDate:                    testDate                    ?? this.testDate,
      lotNumber:                   lotNumber                   ?? this.lotNumber,
      supplierId:                  supplierId                  ?? this.supplierId,
      supplierName:                supplierName                ?? this.supplierName,
      vehicleNumber:               vehicleNumber               ?? this.vehicleNumber,
      avgPalletWeight:             avgPalletWeight             ?? this.avgPalletWeight,
      foreignMaterialWeight:       foreignMaterialWeight       ?? this.foreignMaterialWeight,
      avgPalletAndForeignWeight:   avgPalletAndForeignWeight   ?? this.avgPalletAndForeignWeight,
      receivedQty:                 receivedQty                 ?? this.receivedQty,
      invoiceQty:                  invoiceQty                  ?? this.invoiceQty,
      details:                     details                     ?? this.details,
      status:                      status                      ?? this.status,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ── Summary (list screen) ─────────────────────────────────────────────────────

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
  final String statusLabel; // 'Draft' | 'Submitted'
  final int statusCode;     // 0 = draft, 1 = submitted
  final String syncStatus;  // 'synced' | 'pending'
  final int palletCount;

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
    this.palletCount = 0,
  });

  // ── From API response ──────────────────────────────────────────────────────
  factory AcidTestingSummary.fromJson(Map<String, dynamic> json) {
    final supplier = json['supplier'] as Map<String, dynamic>?;
    final details  = json['details']  as List? ?? [];
    final code     = (json['status'] as num?)?.toInt() ?? 0;

    return AcidTestingSummary(
      id:                          json['id']?.toString() ?? '',
      lotNumber:                   json['lot_number']?.toString() ?? '',
      testDate:                    json['test_date']?.toString() ?? '',
      supplierName:                supplier?['supplier_name']?.toString() ?? '—',
      vehicleNumber:               json['vehicle_number']?.toString() ?? '—',
      avgPalletWeight:             _toDouble(json['avg_pallet_weight']) ?? 0,
      foreignMaterialWeight:       _toDouble(json['foreign_material_weight']) ?? 0,
      avgPalletAndForeignWeight:   _toDouble(json['avg_pallet_and_foreign_weight']) ?? 0,
      receivedQty:                 _toDouble(json['received_qty']) ?? 0,
      statusLabel:                 code >= 1 ? 'Submitted' : 'Draft',
      statusCode:                  code,
      syncStatus:                  'synced',
      palletCount:                 details.length,
    );
  }

  // ── From local SQLite row ──────────────────────────────────────────────────
  factory AcidTestingSummary.fromLocal(Map<String, dynamic> row) {
    return AcidTestingSummary(
      id:                          row['server_id']?.toString()
          ?? 'local_${row['local_id']}',
      lotNumber:                   row['lot_number']?.toString() ?? '',
      testDate:                    row['test_date']?.toString() ?? '',
      supplierName:                row['supplier_name']?.toString() ?? '—',
      vehicleNumber:               row['vehicle_number']?.toString() ?? '—',
      avgPalletWeight:             _toDouble(row['avg_pallet_weight']) ?? 0,
      foreignMaterialWeight:       _toDouble(row['foreign_material_weight']) ?? 0,
      avgPalletAndForeignWeight:   _toDouble(row['avg_pallet_and_foreign_weight']) ?? 0,
      receivedQty:                 _toDouble(row['received_qty']) ?? 0,
      statusLabel:                 row['status_label']?.toString() ?? 'Draft',
      statusCode:                  (row['status_code'] as num?)?.toInt() ?? 0,
      syncStatus:                  row['sync_status']?.toString() ?? 'pending',
      palletCount:                 0, // not stored in summary cache
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ── List result wrapper ───────────────────────────────────────────────────────

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

// ── Save result (shared with receiving) ──────────────────────────────────────
// Re-export SaveResult from receiving_model.dart is not possible in Dart,
// so we define a parallel one here for acid testing saves.

class AcidSaveResult {
  final bool success;
  final String? newId;
  final String? errorMsg;
  final Map<String, dynamic> fieldErrors;

  const AcidSaveResult({
    required this.success,
    this.newId,
    this.errorMsg,
    this.fieldErrors = const {},
  });

  factory AcidSaveResult.error(String message,
      {Map<String, dynamic> errors = const {}}) {
    return AcidSaveResult(
      success:     false,
      errorMsg:    message,
      fieldErrors: errors,
    );
  }
}