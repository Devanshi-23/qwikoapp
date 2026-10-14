import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../utils/app_colors.dart';
import 'connectivity_banner.dart';
import 'demo_labels.dart';

/// Standard screen frame: optional app bar with the `DEMO` pill, the
/// connectivity banner, safe area and a max content width for tablets and
/// the web.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions = const [],
    this.showDemoBadge = false,
    this.bottomNavigationBar,
    this.bottomBar,
    this.floatingActionButton,
    this.backgroundColor = AppColors.background,
    this.maxWidth = AppSpacing.maxContentWidth,
  });

  final Widget body;

  /// Without a title there is no app bar, and the body starts below the
  /// status bar.
  final String? title;
  final List<Widget> actions;
  final bool showDemoBadge;
  final Widget? bottomNavigationBar;

  /// Pinned under the body, above the keyboard (for primary actions).
  final Widget? bottomBar;
  final Widget? floatingActionButton;
  final Color backgroundColor;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final bottomBar = this.bottomBar;

    Widget constrained(Widget child) => LayoutBuilder(
      builder: (context, constraints) {
        final extra = constraints.maxWidth - maxWidth;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: extra > 0 ? extra / 2 : 0),
          child: child,
        );
      },
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title),
              actions: [
                ...actions,
                if (showDemoBadge) const DemoBadge(),
                const SizedBox(width: 8),
              ],
            ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        top: title == null,
        bottom: bottomNavigationBar == null,
        child: Column(
          children: [
            const ConnectivityBanner(),
            Expanded(child: constrained(body)),
            if (bottomBar != null)
              constrained(
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.sm,
                    AppSpacing.xl,
                    AppSpacing.lg,
                  ),
                  child: bottomBar,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
