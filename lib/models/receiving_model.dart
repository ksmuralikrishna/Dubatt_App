import 'dart:convert';
class MaterialOption {
  final String id;
  final String name;

  const MaterialOption({
    required this.id,
    required this.name,
  });

  factory MaterialOption.fromJson(Map<String, dynamic> json) {
    return MaterialOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
  };
}

class ReceivingRecord {
  final String? id;
  final String lotNo;
  final String docDate;
  final String? supplier;
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
    this.supplier,
    this.materialId,
    this.invoiceQty,
    this.receiveQty,
    this.unit,
    this.vehicleNo,
    this.remarks,
  });

  factory ReceivingRecord.fromJson(Map<String, dynamic> json) {
    // Handle nested items array if present
    final items = json['items'] as List<dynamic>?;
    final firstItem = items?.isNotEmpty == true ? items!.first as Map<String, dynamic> : null;

    return ReceivingRecord(
      id: json['id']?.toString(),
      lotNo: json['lot_no']?.toString() ?? '',
      docDate: json['doc_date']?.toString() ?? '',
      supplier: json['supplier']?.toString(),
      materialId: firstItem?['material_id']?.toString() ?? json['material_id']?.toString(),
      invoiceQty: _toDouble(firstItem?['invoice_qty'] ?? json['invoice_qty']),
      receiveQty: _toDouble(firstItem?['receive_qty'] ?? json['receive_qty']),
      unit: firstItem?['unit']?.toString() ?? json['unit']?.toString(),
      vehicleNo: json['vehicle_no']?.toString(),
      remarks: json['remarks']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'lot_no': lotNo,
    'doc_date': docDate,
    'supplier': supplier,
    'vehicle_no': vehicleNo,
    'remarks': remarks,
    'items': [
      {
        'material_id': materialId,
        'invoice_qty': invoiceQty,
        'receive_qty': receiveQty,
        'unit': unit,
      }
    ],
  };

  ReceivingRecord copyWith({
    String? id,
    String? lotNo,
    String? docDate,
    String? supplier,
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
      supplier: supplier ?? this.supplier,
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
  final String docDate;
  final String category;
  final String supplier;
  final double qty;
  final String status;
  final String syncStatus;

  const ReceivingSummary({
    required this.id,
    required this.lotNo,
    required this.docDate,
    required this.category,
    required this.supplier,
    required this.qty,
    required this.status,
    required this.syncStatus,
  });

  factory ReceivingSummary.fromJson(Map<String, dynamic> json) {
    return ReceivingSummary(
      id: json['id']?.toString() ?? '',
      lotNo: json['lot_no']?.toString() ?? '',
      docDate: json['doc_date']?.toString() ?? '',
      category: json['category']?.toString() ?? 'General',
      supplier: json['supplier']?.toString() ?? json['supplier_name']?.toString() ?? '-',
      qty: _toDouble(json['total_qty'] ?? json['receive_qty'] ?? json['invoice_qty']) ?? 0.0,
      status: json['status']?.toString() ?? 'draft',
      syncStatus: json['sync_status']?.toString() ?? 'synced',
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}