import 'package:dubatt_app/services/connectivity_service.dart';
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
  final int? localId;
  final bool isLocalOnly;

  const ReceivingFormScreen({
    super.key,
    this.recordId,
    this.localId,
    this.isLocalOnly = false,
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
  bool _isLoading    = true;
  bool _isSaving     = false;
  bool _isSubmitting = false; // ✅ separate loading state for submit
  bool _isSubmitted  = false;
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

    _materials = await ReceivingService().getMaterials();
    _suppliers = await ReceivingService().getSuppliers();

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

    _currentId            = record.id;
    _lotCtrl.text         = record.lotNo;
    _dateCtrl.text        = _formatDate(record.docDate);
    _selectedSupplier     = record.supplierId;
    _selectedMaterial     = record.materialId;
    _invoiceQtyCtrl.text  = record.invoiceQty?.toString() ?? '';
    _receiveQtyCtrl.text  = record.receiveQty?.toString() ?? '';
    _selectedUnit         = record.unit ?? 'KG';
    _vehicleCtrl.text     = record.vehicleNo ?? '';
    _remarksCtrl.text     = record.remarks ?? '';
    _isSubmitted          = record.status != "0";
  }
  String _formatDate(String isoDateString) {
    try {
      // Parse the ISO string to DateTime
      DateTime dateTime = DateTime.parse(isoDateString);
      // Format as YYYY-MM-DD
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoDateString; // Fallback to original if parsing fails
    }
  }
  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_dateCtrl.text) ?? DateTime.now();
    final picked  = await showDatePicker(
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
    if (picked != null) {
      _dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }
  String? _validate() {
    if (_dateCtrl.text.trim().isEmpty)       return 'Receipt date is required.';
    if (_lotCtrl.text.trim().isEmpty)        return 'Lot number is required.';
    if (_vehicleCtrl.text.trim().isEmpty)    return 'Vehicle number is required.';
    if (_selectedSupplier == null)           return 'Supplier is required.';
    if (_selectedMaterial == null)           return 'Material is required.';
    if (_invoiceQtyCtrl.text.trim().isEmpty) return 'Invoice quantity is required.';
    if (_receiveQtyCtrl.text.trim().isEmpty) return 'Received quantity is required.';
    return null;
  }

  Map<String, dynamic> _buildPayload() => {
    'receipt_date':  _dateCtrl.text.trim(),
    'lot_no':        _lotCtrl.text.trim(),
    'vehicle_number': _vehicleCtrl.text.trim(),
    'supplier_id':   _selectedSupplier,
    'material_id':   _selectedMaterial,
    'invoice_qty':   double.tryParse(_invoiceQtyCtrl.text) ?? 0,
    'received_qty':  double.tryParse(_receiveQtyCtrl.text) ?? 0,
    'unit':          _selectedUnit,
    'remarks':       _remarksCtrl.text.trim(),
  };

  // ── Save ────────────────────────────────────────────────────────
  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      _showSnack(error, error: true);
      return;
    }
    setState(() {
      _isSaving    = true;
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

  // ── Submit ──────────────────────────────────────────────────────
  Future<void> _submit() async {
    // Block submit when offline — submit needs a live API call
    if (!ConnectivityService().isOnline) {
      _showSnack(
        'You are offline. Please connect to submit.',
        error: true,
      );
      return;
    }

    if (_currentId == null) {
      _showSnack('Save the record before submitting.', error: true);
      return;
    }

    // Confirm dialog before submitting
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Submit record?',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        content: Text(
          'Once submitted, this record cannot be edited.',
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: AppColors.textMid,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Submit',
              style: GoogleFonts.outfit(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    final error = await ReceivingService().submit(_currentId!);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (error == null) {
      _showSnack('Record submitted successfully.');
      // Pop back to list after successful submit
      Navigator.of(context).pop();
    } else {
      _showSnack(error, error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
            ),
          ),
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
            ? const Center(
            child: CircularProgressIndicator(color: AppColors.green))
            : SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 100),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Page header ──────────────────────────────
                MesPageHeader(
                  title: _isSubmitted
                      ? 'Receiving Record'  // ✅ Changed for submitted records
                      : (widget.isCreate
                      ? 'Create Receiving Record'
                      : 'Edit Receiving Record'),
                  subtitle: _isSubmitted
                      ? 'This record has been submitted and cannot be edited'  // ✅ New subtitle
                      : (widget.isCreate
                      ? 'Fill in the details'
                      : 'Lot: ${_lotCtrl.text}'),
                  actions: [
                    MesOutlineButton(
                      label: 'Back',
                      icon: Icons.arrow_back,
                      small: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                // ── Offline banner ───────────────────────────
                StreamBuilder<bool>(
                  stream: ConnectivityService().onlineStream,
                  initialData: ConnectivityService().isOnline,
                  builder: (_, snap) {
                    final online = snap.data ?? true;
                    if (online) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                            color: const Color(0xFFF59E0B)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_off,
                              size: 16,
                              color: Color(0xFFF59E0B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You are offline. Record will sync '
                                  'when connection restores.',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: const Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),

                // ── Form card ────────────────────────────────
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
                            prefixIcon:
                            Icons.calendar_today_outlined,
                            errorText: _fieldErrors['doc_date'],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SUPPLIER', style: AppTextStyles.label()),
                          const SizedBox(height: 5),
                          SearchableDropdown<String>(
                            value: _selectedSupplier,
                            items: _suppliers.map((s) => s.id).toList(),
                            displayString: (id) => _suppliers.firstWhere(
                                  (s) => s.id == id,
                              orElse: () => SupplierOption(id: '', name: '—'),
                            ).name,
                            hint: 'Select supplier…',
                            enabled: true,
                            onChanged: (v) => setState(() => _selectedSupplier = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MATERIAL', style: AppTextStyles.label()),
                          const SizedBox(height: 5),
                          SearchableDropdown<String>(
                            value: _selectedMaterial,
                            items: _materials.map((m) => m.id).toList(),
                            displayString: (id) => _materials.firstWhere(
                                  (m) => m.id == id,
                              orElse: () => MaterialOption(id: '', name: '—'),
                            ).name,
                            hint: 'Select material…',
                            enabled: true,
                            onChanged: (v) => setState(() => _selectedMaterial = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      MesTextField(
                        label: 'Invoice Quantity',
                        controller: _invoiceQtyCtrl,
                        keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                      const SizedBox(height: 16),
                      MesTextField(
                        label: 'Receive Quantity',
                        controller: _receiveQtyCtrl,
                        keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedUnit,
                        items: _units
                            .map((u) => DropdownMenuItem(
                          value: u,
                          child: Text(u),
                        ))
                            .toList(),
                        onChanged: (v) => setState(
                                () => _selectedUnit = v ?? 'KG'),
                        decoration: InputDecoration(
                          labelText: 'Unit',
                          prefixIcon: const Icon(
                              Icons.straighten_outlined),
                          border: OutlineInputBorder(
                              borderRadius:
                              BorderRadius.circular(9)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      MesTextField(
                        label: 'Vehicle Number',
                        controller: _vehicleCtrl,
                        prefixIcon:
                        Icons.local_shipping_outlined,
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

                // ── Action buttons ───────────────────────────
                // Edit mode: Save + Submit side by side
                // Create mode: Save only
                if (_isSubmitted)
                  const SizedBox.shrink()  // Hide all buttons when submitted
                else if (!widget.isCreate)
                  Row(
                    children: [
                      // Save button
                      Expanded(
                        child: MesButton(
                          label: 'Save',
                          icon: Icons.save_outlined,
                          isLoading: _isSaving,
                          onPressed:
                          _isSubmitting ? null : _save,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Submit button — only in edit mode
                      Expanded(
                        child: _SubmitButton(
                          isLoading: _isSubmitting,
                          onPressed: _isSaving ? null : _submit,
                        ),
                      ),
                    ],
                  )
                else
                  MesButton(
                    label: 'Create Record',
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

// ─────────────────────────────────────────────
// Submit button widget
// Styled distinctly from the green Save button
// ─────────────────────────────────────────────
class _SubmitButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const _SubmitButton({
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        )
            : const Icon(Icons.check_circle_outline,
            size: 18, color: Colors.white),
        label: Text(
          isLoading ? 'Submitting...' : 'Submit',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0891B2), // teal/blue
          disabledBackgroundColor:
          const Color(0xFF0891B2).withOpacity(0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}