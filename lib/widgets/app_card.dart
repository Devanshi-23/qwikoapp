import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../utils/app_colors.dart';

/// White rounded surface with the standard border. With [title], it becomes
/// a titled section card.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
    this.borderColor = AppColors.border,
    this.color = Colors.white,
  });

  final Widget child;
  final String? title;

  /// Shown at the end of the title row.
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color borderColor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final content = title == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              child,
            ],
          );

    return Container(
      width: double.infinity,
      margin: margin,
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: content),
        ),
      ),
    );
  }
}
