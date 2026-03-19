import 'dart:convert';

// ─────────────────────────────────────────────
// Dropdown options
// ─────────────────────────────────────────────
class MaterialOption {
  final String id;
  final String name;
  final String? code;
  final String? unit;

  const MaterialOption({
    required this.id,
    required this.name,
    this.code,
    this.unit,
  });

  factory MaterialOption.fromJson(Map<String, dynamic> json) {
    return MaterialOption(
      id:   json['id']?.toString() ?? '',
      name: json['material_name']?.toString() ?? '',
      code: json['material_code']?.toString(),
      unit: json['unit']?.toString(),
    );
  }
}

class SupplierOption {
  final String id;
  final String name;
  final String? code;

  const SupplierOption({
    required this.id,
    required this.name,
    this.code,
  });

  factory SupplierOption.fromJson(Map<String, dynamic> json) {
    return SupplierOption(
      id:   json['id']?.toString() ?? '',
      name: json['supplier_name']?.toString() ?? '',
      code: json['supplier_code']?.toString(),
    );
  }
}

// ─────────────────────────────────────────────
// Receiving record (form / detail)
// ─────────────────────────────────────────────
class ReceivingRecord {
  final String? id;
  final String lotNo;
  final String docDate;
  final String? supplierId;
  final String? materialId;
  final double? invoiceQty;
  final double? receiveQty;
  final String? unit;
  final String? vehicleNo;
  final String? remarks;

  const ReceivingRecord({
    this.id,
    required this.lotNo,
    required this.docDate,
    this.supplierId,
    this.materialId,
    this.invoiceQty,
    this.receiveQty,
    this.unit,
    this.vehicleNo,
    this.remarks,
  });

  factory ReceivingRecord.fromJson(Map<String, dynamic> json) {
    // supplier may be a nested object or plain id
    final rawSupplier = json['supplier'];
    String? supplierId;
    if (rawSupplier is Map) {
      supplierId = rawSupplier['id']?.toString();
    } else {
      supplierId = json['supplier_id']?.toString();
    }

    // material may be a nested object or plain id
    final rawMaterial = json['material'];
    String? materialId;
    if (rawMaterial is Map) {
      materialId = rawMaterial['id']?.toString();
    } else {
      materialId = json['material_id']?.toString();
    }

    return ReceivingRecord(
      id:         json['id']?.toString(),
      lotNo:      json['lot_no']?.toString() ?? '',
      docDate:    json['receipt_date']?.toString() ?? '',
      supplierId: supplierId,
      materialId: materialId,
      invoiceQty: _toDouble(json['invoice_qty']),
      receiveQty: _toDouble(json['received_qty']),
      unit:       json['unit']?.toString(),
      vehicleNo:  json['vehicle_number']?.toString(),
      remarks:    json['remarks']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'receipt_date':   docDate,
    'lot_no':         lotNo,
    'supplier_id':    supplierId,
    'vehicle_number': vehicleNo,
    'material_id':    materialId,
    'invoice_qty':    invoiceQty,
    'received_qty':   receiveQty,
    'unit':           unit,
    'remarks':        remarks,
  };

  ReceivingRecord copyWith({
    String? id,
    String? lotNo,
    String? docDate,
    String? supplierId,
    String? materialId,
    double? invoiceQty,
    double? receiveQty,
    String? unit,
    String? vehicleNo,
    String? remarks,
  }) {
    return ReceivingRecord(
      id:         id         ?? this.id,
      lotNo:      lotNo      ?? this.lotNo,
      docDate:    docDate    ?? this.docDate,
      supplierId: supplierId ?? this.supplierId,
      materialId: materialId ?? this.materialId,
      invoiceQty: invoiceQty ?? this.invoiceQty,
      receiveQty: receiveQty ?? this.receiveQty,
      unit:       unit       ?? this.unit,
      vehicleNo:  vehicleNo  ?? this.vehicleNo,
      remarks:    remarks    ?? this.remarks,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

// ─────────────────────────────────────────────
// Receiving summary (list screen)
// ─────────────────────────────────────────────
class ReceivingSummary {
  final String id;
  final String lotNo;
  final String receiptDate;
  final String materialName;
  final String materialCategory;
  final String supplierName;
  final double receivedQty;
  final String unit;
  final String statusLabel;
  final int statusCode;
  final String syncStatus; // ✅ 'synced' | 'pending'

  const ReceivingSummary({
    required this.id,
    required this.lotNo,
    required this.receiptDate,
    required this.materialName,
    required this.materialCategory,
    required this.supplierName,
    required this.receivedQty,
    required this.unit,
    required this.statusLabel,
    required this.statusCode,
    this.syncStatus = 'synced',
  });

  // ✅ From API response — always synced
  factory ReceivingSummary.fromJson(Map<String, dynamic> json) {
    final supplier = json['supplier'] as Map<String, dynamic>?;
    final material = json['material'] as Map<String, dynamic>?;

    return ReceivingSummary(
      id:               json['id']?.toString() ?? '',
      lotNo:            json['lot_no']?.toString() ?? '',
      receiptDate:      json['receipt_date']?.toString() ?? '',
      materialName:     material?['material_name']?.toString() ?? '-',
      materialCategory: material?['category']?.toString() ?? '-',
      supplierName:     supplier?['supplier_name']?.toString() ?? '-',
      receivedQty:      _toDouble(json['received_qty']) ?? 0.0,
      unit:             json['unit']?.toString() ?? '',
      statusLabel:      json['status_label']?.toString() ?? 'Pending',
      statusCode:       (json['status'] as num?)?.toInt() ?? 0,
      syncStatus:       'synced',
    );
  }

  // ✅ From local SQLite row
  // Used for both cached server records AND offline-created records.
  // syncStatus field tells the UI whether to show the orange pending dot.
  factory ReceivingSummary.fromLocal(Map<String, dynamic> row) {
    return ReceivingSummary(
      // Use server_id when available, otherwise prefix with 'local_'
      id:               row['server_id']?.toString() ??
          'local_${row['local_id']}',
      lotNo:            row['lot_no']?.toString() ?? '',
      receiptDate:      row['receipt_date']?.toString() ?? '',
      materialName:     row['material_name']?.toString() ?? '-',
      materialCategory: '-',
      supplierName:     row['supplier_name']?.toString() ?? '-',
      receivedQty:      _toDouble(row['received_qty']) ?? 0.0,
      unit:             row['unit']?.toString() ?? '',
      statusLabel:      row['status_label']?.toString() ?? 'Pending',
      statusCode:       (row['status_code'] as num?)?.toInt() ?? 0,
      syncStatus:       row['sync_status']?.toString() ?? 'pending',
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

// ─────────────────────────────────────────────
// Save result
// ─────────────────────────────────────────────
class SaveResult {
  final bool success;
  final String? newId;
  final String? errorMsg;
  final Map<String, dynamic> fieldErrors;

  const SaveResult({
    required this.success,
    this.newId,
    this.errorMsg,
    this.fieldErrors = const {},
  });

  factory SaveResult.error(String message,
      {Map<String, dynamic> errors = const {}}) {
    return SaveResult(
      success:     false,
      errorMsg:    message,
      fieldErrors: errors,
    );
  }
}

// ─────────────────────────────────────────────
// List result wrapper
// ─────────────────────────────────────────────
class ReceivingListResult {
  final List<ReceivingSummary> records;
  final int total;
  final String? errorMsg;

  bool get hasError => errorMsg != null;

  ReceivingListResult({required this.records, required this.total})
      : errorMsg = null;

  ReceivingListResult.error(this.errorMsg)
      : records = [],
        total   = 0;
}