import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/primary_button.dart';

/// Shown on first launch: explains that this is a demo before sign-in.
class DemoIntroScreen extends StatelessWidget {
  const DemoIntroScreen({super.key});

  static const List<(IconData, String, String)> _points = [
    (
      Icons.phone_android_rounded,
      'Runs on your phone',
      'Orders, customers, maps and payouts are sample data. Nothing is sent '
          'to a server.',
    ),
    (
      Icons.science_outlined,
      'Look for the labels',
      'The DEMO pill and "Simulated" tags mark anything that would be real '
          'in the live app, like calls, chats and payments.',
    ),
    (
      Icons.tune_rounded,
      'Try every state',
      'Long-press the DEMO pill to open Demo controls: switch account states, '
          'go offline or reset the data.',
    ),
  ];

  Future<void> _continue(BuildContext context) async {
    final navigator = Navigator.of(context);
    final settings = context.services.settings;
    try {
      await settings.update(settings.settings.copyWith(introSeen: true));
    } catch (_) {
      // Seeing the intro again next time is harmless.
    }
    navigator.pushReplacementNamed(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppScaffold(
      backgroundColor: Colors.white,
      bottomBar: PrimaryButton(
        label: 'Get started',
        icon: Icons.arrow_forward_rounded,
        onPressed: () => _continue(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.xxxl,
          AppSpacing.xxl,
          AppSpacing.xxl,
        ),
        children: [
          Center(
            child: Container(
              height: 96,
              width: 96,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delivery_dining_rounded,
                size: 52,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Semantics(
            header: true,
            child: Text(
              'Welcome to the Qwiko partner demo',
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Explore the full delivery partner experience, from going online '
            'to getting paid.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          for (final (icon, title, body) in _points)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.infoLight,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(icon, color: AppColors.info),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(body, style: textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
