import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/primary_button.dart';
import '../support/help_support_screen.dart';
import 'blocked_account_actions.dart';

/// Read-only screen for a suspended account: the reason, a way to contact
/// support and, in demo builds, a way to reinstate.
class AccountSuspendedScreen extends StatefulWidget {
  const AccountSuspendedScreen({super.key});

  @override
  State<AccountSuspendedScreen> createState() => _AccountSuspendedScreenState();
}

class _AccountSuspendedScreenState extends State<AccountSuspendedScreen> {
  bool _reinstating = false;

  HelpRequest _helpRequest(String? reason) => HelpRequest(
    category: 'Account suspended',
    message:
        'Hi, my account has been suspended'
        '${reason == null ? '' : ' with the reason: "$reason"'}. '
        'Please review my account.',
  );

  Future<void> _reinstate() async {
    final services = context.services;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _reinstating = true);
    try {
      services.demo?.reinstateAccount();
      final partner = await services.session.refreshPartner();
      messenger.showSnackBar(
        const SnackBar(content: Text('Account reinstated (simulated).')),
      );
      AppRoutes.goToAccountHome(navigator, partner);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() => _reinstating = false);
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = context.services;
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: services.profile,
      builder: (context, _) {
        final reason = services.profile.profile?.suspensionReason;
        final helpRequest = _helpRequest(reason);
        return AppScaffold(
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              const Align(alignment: Alignment.centerRight, child: DemoBadge()),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Container(
                  height: 96,
                  width: 96,
                  decoration: const BoxDecoration(
                    color: AppColors.errorLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.block_rounded,
                    size: 48,
                    color: AppColors.error,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Semantics(
                header: true,
                child: Text(
                  'Account suspended',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "You can't go online or accept orders until your account is "
                'reinstated.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                title: 'Reason',
                borderColor: AppColors.error.withValues(alpha: 0.4),
                child: Text(
                  reason ?? 'Contact support to find out why.',
                  style: textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Contact support',
                icon: Icons.support_agent_rounded,
                onPressed: () => Navigator.pushNamed(
                  context,
                  AppRoutes.help,
                  arguments: helpRequest,
                ),
              ),
              if (services.demo != null) ...[
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Simulate reinstatement',
                  variant: ButtonVariant.outlined,
                  isLoading: _reinstating,
                  onPressed: _reinstate,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Center(
                  child: SimulatedLabel(text: 'Demo only: skips the review'),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              BlockedAccountActions(helpRequest: helpRequest),
            ],
          ),
        );
      },
    );
  }
}
