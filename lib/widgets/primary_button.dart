import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../utils/app_colors.dart';

enum ButtonVariant { filled, outlined, destructive }

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.variant = ButtonVariant.filled,
    this.height = 54,
  });

  final String label;

  /// `null` disables the button; pair it with a `DisabledReason`.
  final VoidCallback? onPressed;

  /// Shows a spinner and disables the button. The label stays in place
  /// (invisible) so the width is stable and screen readers still hear it.
  final bool isLoading;
  final IconData? icon;
  final ButtonVariant variant;

  /// At least 52 for primary actions.
  final double height;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final filled = variant == ButtonVariant.filled;
    final foreground = switch (variant) {
      ButtonVariant.filled => Colors.white,
      ButtonVariant.outlined => AppColors.primary,
      ButtonVariant.destructive => AppColors.error,
    };
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md + 2),
    );

    final content = Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: isLoading ? 0 : 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isLoading)
          ExcludeSemantics(
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.3,
                color: foreground,
              ),
            ),
          ),
      ],
    );

    final onPressed = isLoading ? null : this.onPressed;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: filled
          ? ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withValues(
                  alpha: isLoading ? 0.85 : 0.45,
                ),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: shape,
              ),
              child: content,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: foreground,
                side: BorderSide(
                  color: onPressed == null && !isLoading
                      ? AppColors.border
                      : foreground,
                ),
                shape: shape,
              ),
              child: content,
            ),
    );
  }
}
