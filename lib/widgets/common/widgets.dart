import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';


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
