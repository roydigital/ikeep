import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.isDark,
    required this.isPrimary,
    required this.icon,
    required this.label,
    this.onPressed,
    this.trailing,
    this.isLoading = false,
    this.minHeight = 58,
    this.labelMaxLines = 2,
  });

  final bool isDark;
  final bool isPrimary;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Widget? trailing;
  final bool isLoading;
  final double minHeight;
  final int labelMaxLines;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final foregroundColor = _foregroundColor(isEnabled);
    final buttonBackground = _buttonBackground(isEnabled);
    final borderColor = _borderColor(isEnabled);
    // In dark mode, the blue-tinted gradient reads well on dark surfaces.
    // In light mode, starting from a light blue (#5B9CF6 @ 80%) produces
    // near-white contrast against the white onPrimary text — use solid
    // purples instead so the button is clearly visible on light cards.
    final primaryStart = isDark
        ? Color.lerp(AppColors.info, AppColors.primaryLight, 0.20)!
        : AppColors.primaryLight;
    final primaryMid = isDark
        ? Color.lerp(AppColors.info, AppColors.primary, 0.42)!
        : AppColors.primary;
    final gradient = isPrimary && isEnabled
        ? LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [primaryStart, primaryMid, AppColors.primaryDark],
            stops: [0.0, 0.52, 1.0],
          )
        : null;

    // Shadow must live on a DecoratedBox OUTSIDE the Material clip boundary,
    // otherwise ClipRRect swallows the shadow.
    final shadow = isPrimary && isEnabled
        ? BoxShadow(
            color: AppColors.primary.withValues(alpha: isDark ? 0.38 : 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        : null;

    final buttonContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _iconTileColor(isEnabled),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _iconTileBorderColor(isEnabled)),
            ),
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foregroundColor,
                      ),
                    )
                  : Icon(icon, size: 18, color: foregroundColor),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: labelMaxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: DecoratedBox(
        // Outer DecoratedBox only carries the drop shadow (must be outside the
        // Material clip so the shadow isn't cropped by the rounded corners).
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: shadow != null ? [shadow] : null,
        ),
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            // Ink paints its decoration BEFORE InkWell's ripple layer, which
            // is the only reliable way to show a gradient under ink effects.
            decoration: BoxDecoration(
              gradient: gradient,
              color: gradient == null ? buttonBackground : null,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
            ),
            child: InkWell(
              onTap: onPressed,
              child: buttonContent,
            ),
          ),
        ),
      ),
    );
  }

  Color _foregroundColor(bool isEnabled) {
    if (!isEnabled) {
      return isDark ? AppColors.textDisabledDark : AppColors.textDisabledLight;
    }
    if (isPrimary) {
      return AppColors.onPrimary;
    }
    return isDark ? AppColors.primaryLight : AppColors.primary;
  }

  Color _buttonBackground(bool isEnabled) {
    if (!isEnabled) {
      return isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;
    }
    if (isPrimary) {
      return Colors.transparent;
    }
    return isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
  }

  Color _borderColor(bool isEnabled) {
    if (!isEnabled) {
      return isDark ? AppColors.borderDark : AppColors.borderLight;
    }
    if (isPrimary) {
      return Colors.white.withValues(alpha: isDark ? 0.12 : 0.10);
    }
    return AppColors.primary.withValues(alpha: isDark ? 0.28 : 0.18);
  }

  Color _iconTileColor(bool isEnabled) {
    if (!isEnabled) {
      return isDark
          ? AppColors.backgroundDark.withValues(alpha: 0.32)
          : Colors.white.withValues(alpha: 0.50);
    }
    if (isPrimary) {
      return Colors.white.withValues(alpha: 0.18);
    }
    return AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.10);
  }

  Color _iconTileBorderColor(bool isEnabled) {
    if (!isEnabled) {
      return Colors.transparent;
    }
    if (isPrimary) {
      return Colors.white.withValues(alpha: 0.14);
    }
    return AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.08);
  }
}
