import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../widgets/common/app_shell.dart';
import '../../models/receiving_model.dart';
import '../../services/receiving_service.dart';

class ReceivingFormScreen extends StatefulWidget {
  final String? recordId;
  final VoidCallback onLogout;

  const ReceivingFormScreen({
    super.key,
    this.recordId,
    required this.onLogout,
  });

  bool get isCreate => recordId == null;

  @override
  State<ReceivingFormScreen> createState() => _ReceivingFormScreenState();
}

class _ReceivingFormScreenState extends State<ReceivingFormScreen> {
  // Controllers
  final _lotCtrl        = TextEditingController();
  final _dateCtrl       = TextEditingController();
  final _supplierCtrl   = TextEditingController();
  final _vehicleCtrl    = TextEditingController();
  final _invoiceQtyCtrl = TextEditingController();
  final _receiveQtyCtrl = TextEditingController();
  final _remarksCtrl    = TextEditingController();

  // Dropdowns
  List<MaterialOption> _materials = [];
  List<SupplierOption> _suppliers = [];
  String? _selectedMaterial;
  String? _selectedSupplier;
  String _selectedUnit = 'KG';
  final _units = ['KG', 'MT', 'L', 'PCS'];

  // State
  bool _isLoading = true;
  bool _isSaving  = false;
  Map<String, String> _fieldErrors = {};
  String? _currentId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _lotCtrl.dispose();
    _dateCtrl.dispose();
    _supplierCtrl.dispose();
    _vehicleCtrl.dispose();
    _invoiceQtyCtrl.dispose();
    _receiveQtyCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);

    // Load dropdowns
    _materials = await ReceivingService().getMaterials();
    _suppliers = await ReceivingService().getSuppliers();

    // --- ADD THESE PRINT STATEMENTS ---
    print('--- DROPDOWN DATA CHECK ---');
    print('Materials count: ${_materials.length}');
    print('Materials: ${_materials.map((m) => '${m.name} (${m.id})').toList()}');

    print('Suppliers count: ${_suppliers.length}');
    print('Suppliers: ${_suppliers.map((s) => '${s.name} (${s.id})').toList()}');
    print('---------------------------');
    if (widget.isCreate) {
      final lotNo = await ReceivingService().generateLotNo();
      _dateCtrl.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    } else {
      await _loadRecord();
    }

    setState(() => _isLoading = false);
  }

  Future<void> _loadRecord() async {
    final record = await ReceivingService().getOne(widget.recordId!);
    if (record == null) {
      _showSnack('Failed to load record.', error: true);
      return;
    }

    _currentId = record.id;
    _lotCtrl.text = record.lotNo;
    _dateCtrl.text = record.docDate;
    _selectedSupplier = record.supplierId;
    _selectedMaterial = record.materialId;
    _invoiceQtyCtrl.text = record.invoiceQty?.toString() ?? '';
    _receiveQtyCtrl.text = record.receiveQty?.toString() ?? '';
    _selectedUnit = record.unit ?? 'KG';

    _vehicleCtrl.text = record.vehicleNo ?? '';
    _remarksCtrl.text = record.remarks ?? '';


  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_dateCtrl.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.green,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AppColors.textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) _dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
  }

  Map<String, dynamic> _buildPayload() => {
    'receipt_date': _dateCtrl.text.trim(),
    'lot_no': _lotCtrl.text.trim(),
    'vehicle_number': _vehicleCtrl.text.trim(),
    'supplier_id': _selectedSupplier,
    'material_id': _selectedMaterial,
    'invoice_qty': double.tryParse(_invoiceQtyCtrl.text) ?? 0,
    'received_qty': double.tryParse(_receiveQtyCtrl.text) ?? 0,
    'unit': _selectedUnit,
    'remarks': _remarksCtrl.text.trim(),
  };

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _fieldErrors = {};
    });

    final result = await ReceivingService().save(
      _buildPayload(),
      id: _currentId,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.success) {
      _showSnack('Record saved successfully.');
      if (widget.isCreate && result.newId != null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ReceivingFormScreen(
            recordId: result.newId,
            onLogout: widget.onLogout,
          ),
        ));
      }
    } else if (result.fieldErrors.isNotEmpty) {
      _fieldErrors = result.fieldErrors.map(
            (k, v) => MapEntry(k, (v is List ? v.first : v).toString()),
      );
      _showSnack(result.errorMsg ?? 'Please fix the errors.', error: true);
    } else {
      _showSnack(result.errorMsg ?? 'Save failed.', error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 13))),
        ],
      ),
      backgroundColor: error ? AppColors.error : AppColors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.hPad(context);
    return AppShell(
      currentRoute: '/receiving',
      onLogout: widget.onLogout,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.green))
            : SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 100),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MesPageHeader(
                  title: widget.isCreate ? 'Create Receiving Record' : 'Edit Receiving Record',
                  subtitle: widget.isCreate ? 'Fill in the details' : 'Lot: ${_lotCtrl.text}',
                  actions: [
                    MesOutlineButton(
                      label: 'Back',
                      icon: Icons.arrow_back,
                      small: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                MesCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      MesTextField(
                        label: 'Lot Number',
                        controller: _lotCtrl,
                        prefixIcon: Icons.tag,
                        errorText: _fieldErrors['lot_no'],
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _pickDate,
                        child: AbsorbPointer(
                          child: MesTextField(
                            label: 'Date',
                            controller: _dateCtrl,
                            readOnly: true,
                            prefixIcon: Icons.calendar_today_outlined,
                            errorText: _fieldErrors['doc_date'],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedSupplier,
                        items: _suppliers.map((s) => DropdownMenuItem(   // ✅ correct list + type
                            value: s.id, child: Text(s.name))).toList(),
                        onChanged: (v) => setState(() => _selectedSupplier = v),
                        decoration: InputDecoration(
                          labelText: 'Supplier',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedMaterial,
                        hint: const Text('Select Material'),
                        items: _materials.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))).toList(),
                        onChanged: (v) => setState(() => _selectedMaterial = v),
                        decoration: InputDecoration(
                          labelText: 'Material',
                          prefixIcon: const Icon(Icons.inventory_2_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      MesTextField(
                        label: 'Invoice Quantity',
                        controller: _invoiceQtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 16),
                      MesTextField(
                        label: 'Receive Quantity',
                        controller: _receiveQtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedUnit,
                        items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                        onChanged: (v) => setState(() => _selectedUnit = v ?? 'KG'),
                        decoration: InputDecoration(
                          labelText: 'Unit',
                          prefixIcon: const Icon(Icons.straighten_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      MesTextField(
                        label: 'Vehicle Number',
                        controller: _vehicleCtrl,
                        prefixIcon: Icons.local_shipping_outlined,
                      ),
                      const SizedBox(height: 16),
                      MesTextField(
                        label: 'Remarks',
                        controller: _remarksCtrl,
                        prefixIcon: Icons.note_outlined,
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                MesButton(
                  label: widget.isCreate ? 'Create Record' : 'Save',
                  icon: Icons.save_outlined,
                  isLoading: _isSaving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}