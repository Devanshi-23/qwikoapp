import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../utils/app_colors.dart';

/// Icon, value and label; used on the dashboard, history and earnings. With
/// [onTap] it opens the detail behind the number.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.valueColor = AppColors.textDark,
    this.semanticValue,
    this.onTap,
  });

  /// Shown while data is loading.
  static const String placeholder = '–';

  final String value;
  final String label;
  final IconData? icon;
  final Color valueColor;

  /// Spoken instead of [value], for example "1,295 rupees".
  final String? semanticValue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final loading = value == placeholder;

    return Semantics(
      label: '$label: ${loading ? 'loading' : semanticValue ?? value}',
      button: onTap != null,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: icon == null
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Row(
                    children: [
                      Icon(icon, color: AppColors.primary, size: 22),
                      const Spacer(),
                      if (onTap != null)
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textGrey,
                          size: 18,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
