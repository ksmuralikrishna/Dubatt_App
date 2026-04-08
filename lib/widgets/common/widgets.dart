import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import 'package:flutter/services.dart';


// ─────────────────────────────────────────────
// MesCard
// ─────────────────────────────────────────────
class MesCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? bg;
  final double radius;

  const MesCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.bg,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(22),
      decoration: AppTheme.cardDecoration(bg: bg, radius: radius),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────
// MesSectionHead — green-light card header bar
// ─────────────────────────────────────────────
class MesSectionHead extends StatelessWidget {
  final IconData icon;
  final String title;

  const MesSectionHead({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
      decoration: const BoxDecoration(
        color: AppColors.greenLight,
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.green),
          const SizedBox(width: 10),
          Text(
            title.toUpperCase(),
            style: AppTextStyles.label(color: AppColors.green),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// MesTextField
// ─────────────────────────────────────────────
class MesTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final IconData? prefixIcon;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int? maxLines;
  final String? errorText;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? badge;
  final Color? badgeColor;
  final List<TextInputFormatter>? inputFormatters;

  const MesTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.prefixIcon,
    this.readOnly = false,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.errorText,
    this.obscureText = false,
    this.suffixIcon,
    this.badge,
    this.badgeColor,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTextStyles.label()),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          onChanged: onChanged,
          keyboardType: keyboardType,
          maxLines: maxLines,
          obscureText: obscureText,
          style: GoogleFonts.outfit(fontSize: 13.5, color: AppColors.textDark),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 14, color: AppColors.textMuted)
                : null,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: readOnly ? const Color(0xFFf0f4f2) : AppColors.greenXLight,
            errorText: errorText,
            errorStyle: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.error),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// MesButton — primary green button
// ─────────────────────────────────────────────
class MesButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final double? width;
  final bool small;

  const MesButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.width,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = isLoading
        ? const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: Colors.white),
                const SizedBox(width: 7),
              ],
              Text(label,
                  style: GoogleFonts.outfit(
                    fontSize: small ? 13 : 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  )),
            ],
          );

    final btn = ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.green.withOpacity(0.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        padding: EdgeInsets.symmetric(
          horizontal: small ? 15 : 18,
          vertical: small ? 10 : 12,
        ),
        elevation: 0,
      ),
      child: content,
    );

    return width != null ? SizedBox(width: width, child: btn) : btn;
  }
}

// ─────────────────────────────────────────────
// MesOutlineButton
// ─────────────────────────────────────────────
class MesOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool small;

  const MesOutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textMid,
        side: const BorderSide(color: AppColors.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        backgroundColor: AppColors.white,
        padding: EdgeInsets.symmetric(
          horizontal: small ? 15 : 18,
          vertical: small ? 8 : 10,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15),
            const SizedBox(width: 7),
          ],
          Text(label,
              style: GoogleFonts.outfit(
                fontSize: small ? 13 : 13.5,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// MesStatusBadge
// ─────────────────────────────────────────────
class MesStatusBadge extends StatelessWidget {
  final String status;

  const MesStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg, tx;
    String label;

    switch (status.toLowerCase()) {
      case 'submitted':
        bg = AppColors.badgeSubmit; tx = AppColors.badgeSubmitTx;
        label = 'Submitted';
        break;
      case 'pending':
        bg = AppColors.badgePending; tx = AppColors.badgePendTx;
        label = 'Pending';
        break;
      default:
        bg = AppColors.badgeDraft; tx = AppColors.badgeDraftTx;
        label = 'Draft';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 11.5, fontWeight: FontWeight.w700, color: tx,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// MesPageHeader
// ─────────────────────────────────────────────
class MesPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? badge;
  final List<Widget> actions;

  const MesPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.display()),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: AppTextStyles.body()),
                ],
                if (badge != null) ...[
                  const SizedBox(height: 8),
                  badge!,
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Wrap(spacing: 10, children: actions),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// SEARCHABLE DROPDOWN - Reusable Widget
// ============================================================

/// A searchable dropdown that opens a modal with search functionality
class SearchableDropdown<T> extends StatelessWidget {
  final T? value;
  final List<T> items;
  final String Function(T) displayString;
  final String hint;
  final bool enabled;
  final ValueChanged<T?> onChanged;

  const SearchableDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.displayString,
    required this.onChanged,
    this.hint = 'Select…',
    this.enabled = true,
  });

  String get _selectedName => value != null
      ? displayString(value!)
      : '';

  Future<void> _open(BuildContext context) async {
    if (!enabled) return;

    // Unfocus to hide keyboard
    FocusScope.of(context).unfocus();

    final result = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SearchableDropdownModal<T>(
        items: items,
        selectedValue: value,
        displayString: displayString,
      ),
    );
    if (result != null && result != value) {
      onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = _selectedName.isNotEmpty;
    return GestureDetector(
      onTap: enabled ? () => _open(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? AppColors.greenXLight : const Color(0xFFF0F4F2),
          border: Border.all(color: AppColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              hasValue ? _selectedName : hint,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: hasValue ? AppColors.textDark : AppColors.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (enabled)
            const Icon(Icons.search, size: 16, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}

/// Modal for searchable dropdown
class SearchableDropdownModal<T> extends StatefulWidget {
  final List<T> items;
  final T? selectedValue;
  final String Function(T) displayString;

  const SearchableDropdownModal({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.displayString,
  });

  @override
  State<SearchableDropdownModal<T>> createState() => _SearchableDropdownModalState<T>();
}

class _SearchableDropdownModalState<T> extends State<SearchableDropdownModal<T>> {
  final _searchCtrl = TextEditingController();
  late List<T> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? widget.items
          : widget.items
          .where((item) => widget.displayString(item).toLowerCase().contains(q))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.88,
        minChildSize: 0.4,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              decoration: const BoxDecoration(
                color: AppColors.greenLight,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(children: [
                const Icon(Icons.search, size: 16, color: AppColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Select Item',
                      style: AppTextStyles.subheading(color: AppColors.green)),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                ),
              ]),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                controller: _searchCtrl,
                autofocus: false,
                style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? GestureDetector(
                    onTap: () => _searchCtrl.clear(),
                    child: const Icon(Icons.clear, size: 16, color: AppColors.textMuted),
                  )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.greenXLight,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(color: AppColors.border, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(color: AppColors.border, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(color: AppColors.green, width: 1.5),
                  ),
                ),
              ),
            ),
            // Results count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${_filtered.length} result(s)',
                    style: AppTextStyles.caption()),
              ),
            ),
            // List
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.search_off_outlined,
                        size: 40, color: AppColors.borderLight),
                    const SizedBox(height: 8),
                    Text('No items match your search.',
                        style: AppTextStyles.caption()),
                  ],
                ),
              )
                  : ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 8),
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: _filtered.length,
                separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.borderLight),
                itemBuilder: (_, i) {
                  final item = _filtered[i];
                  final isSelected = item == widget.selectedValue;
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(item),
                    child: Container(
                      color: isSelected
                          ? AppColors.greenXLight : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            widget.displayString(item),
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w700 : FontWeight.w400,
                              color: isSelected
                                  ? AppColors.green : AppColors.textDark,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle,
                              size: 16, color: AppColors.green),
                      ]),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 10 : 0),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Responsive helpers
// ─────────────────────────────────────────────
class Responsive {
  static bool isMobile(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width < 600;
  static bool isTablet(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= 600;
  static bool isLargeTablet(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= 900;
  static double hPad(BuildContext ctx) =>
      isMobile(ctx) ? 16.0 : 24.0;
}
