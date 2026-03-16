import 'dart:convert';
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
      id: json['id']?.toString() ?? '',
      name: json['material_name']?.toString() ?? '',  // ✅ was 'name', API returns 'material_name'
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
      id: json['id']?.toString() ?? '',
      name: json['supplier_name']?.toString() ?? '',  // ✅ API returns 'supplier_name'
      code: json['supplier_code']?.toString(),
    );
  }
}
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
    final supplier = json['supplier'];
    String? supplierId;
    if (supplier is Map) {
      supplierId = supplier['id']?.toString();       // ✅ extract id from nested object
    } else {
      supplierId = json['supplier_id']?.toString();  // ✅ fallback to supplier_id
    }

    return ReceivingRecord(
      id:         json['id']?.toString(),
      lotNo:      json['lot_no']?.toString() ?? '',
      docDate:    json['receipt_date']?.toString() ?? '',  // ✅ API uses receipt_date
      supplierId: supplierId,
      materialId: json['material_id']?.toString()
          ?? (json['material'] as Map?)?['id']?.toString(),
      invoiceQty: _toDouble(json['invoice_qty']),
      receiveQty: _toDouble(json['received_qty']),         // ✅ API uses received_qty
      unit:       json['unit']?.toString(),
      vehicleNo:  json['vehicle_number']?.toString(),      // ✅ API uses vehicle_number
      remarks:    json['remarks']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'receipt_date': docDate,
    'lot_no': lotNo,
    'supplier_id': supplierId,
    'vehicle_number': vehicleNo,
    'material_id': materialId,
    'invoice_qty': invoiceQty,
    'received_qty': receiveQty,
    'unit': unit,
    'remarks': remarks,
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
      id: id ?? this.id,
      lotNo: lotNo ?? this.lotNo,
      docDate: docDate ?? this.docDate,
      supplierId: supplierId ?? this.supplierId,
      materialId: materialId ?? this.materialId,
      invoiceQty: invoiceQty ?? this.invoiceQty,
      receiveQty: receiveQty ?? this.receiveQty,
      unit: unit ?? this.unit,
      vehicleNo: vehicleNo ?? this.vehicleNo,
      remarks: remarks ?? this.remarks,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

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

  factory SaveResult.fromJson(Map<String, dynamic> json) {
    return SaveResult(
      success: json['success'] as bool? ?? false,
      newId: json['id']?.toString() ?? json['new_id']?.toString(),
      errorMsg: json['message']?.toString() ?? json['error']?.toString(),
      fieldErrors: json['errors'] as Map<String, dynamic>? ?? {},
    );
  }

  factory SaveResult.error(String message, {Map<String, dynamic> errors = const {}}) {
    return SaveResult(
      success: false,
      errorMsg: message,
      fieldErrors: errors,
    );
  }
}

class ReceivingSummary {
  final String id;
  final String lotNo;
  final String receiptDate;
  final String materialName;
  final String materialCategory;
  final String supplierName;
  final double receivedQty;
  final String unit;
  final String statusLabel;  // "Pending", "Approved", "In Progress"
  final int statusCode;      // 0, 1, 2

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
  });

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
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}