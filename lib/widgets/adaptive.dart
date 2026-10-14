import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../utils/app_colors.dart';

abstract final class Breakpoints {
  /// Navigation rail instead of the bottom bar.
  static const double rail = 600;

  /// List and detail side by side.
  static const double twoPane = 840;

  static bool useRail(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= rail;

  static bool useTwoPane(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= twoPane;
}

/// A list on the start side and its detail filling the rest.
class TwoPane extends StatelessWidget {
  const TwoPane({
    super.key,
    required this.list,
    required this.detail,
    this.listWidth = 400,
  });

  final Widget list;
  final Widget detail;
  final double listWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: listWidth, child: list),
        const VerticalDivider(width: 1, color: AppColors.border),
        Expanded(child: detail),
      ],
    );
  }
}

/// Keeps single-column content readable on wide screens.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({
    super.key,
    required this.child,
    this.maxWidth = AppSpacing.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
