import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../models/partner.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/primary_button.dart';
import '../account/blocked_account_actions.dart';

class VerificationPendingScreen extends StatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  State<VerificationPendingScreen> createState() =>
      _VerificationPendingScreenState();
}

enum _Busy { none, checking, approving, rejecting }

class _VerificationPendingScreenState extends State<VerificationPendingScreen> {
  _Busy _busy = _Busy.none;

  /// Runs [action], then sends the partner wherever their new state belongs.
  Future<void> _run(
    _Busy busy,
    Future<PartnerProfile> Function() action, {
    required String stillPendingMessage,
  }) async {
    if (_busy != _Busy.none) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = busy);
    final PartnerProfile profile;
    try {
      profile = await action();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() => _busy = _Busy.none);
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    if (!mounted) return;
    setState(() => _busy = _Busy.none);
    switch (profile.verification) {
      case VerificationStatus.pending:
        messenger.showSnackBar(SnackBar(content: Text(stillPendingMessage)));
      case VerificationStatus.verified:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Your profile is verified! Welcome to Qwiko 🎉'),
          ),
        );
        AppRoutes.goToAccountHome(navigator, profile);
      case VerificationStatus.rejected ||
          VerificationStatus.newSignup ||
          VerificationStatus.suspended:
        AppRoutes.goToAccountHome(navigator, profile);
    }
  }

  void _checkStatus() => _run(
    _Busy.checking,
    context.services.profile.refreshVerification,
    stillPendingMessage: 'Still under review. Please check later.',
  );

  void _simulate({required bool approve}) {
    final services = context.services;
    _run(approve ? _Busy.approving : _Busy.rejecting, () {
      final demo = services.demo!;
      approve ? demo.approveVerification() : demo.rejectVerification();
      return services.session.refreshPartner();
    }, stillPendingMessage: 'Nothing to review yet.');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasDemo = context.services.demo != null;
    return AppScaffold(
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        children: [
          const Align(alignment: Alignment.centerRight, child: DemoBadge()),
          Center(
            child: Container(
              height: 120,
              width: 120,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.hourglass_top_rounded,
                size: 60,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Semantics(
            header: true,
            child: Text(
              'Profile under review',
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Thanks for signing up! Our team is checking your documents. '
            'This usually takes 24–48 hours. We will notify you once you are '
            'approved.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _Step(
            Icons.check_circle_rounded,
            'Account created',
            done: true,
          ),
          const _Step(
            Icons.check_circle_rounded,
            'Details submitted',
            done: true,
          ),
          const _Step(Icons.pending_rounded, 'Document verification'),
          const _Step(Icons.radio_button_unchecked_rounded, 'Start delivering'),
          const SizedBox(height: AppSpacing.xxl),
          PrimaryButton(
            label: 'Check status',
            isLoading: _busy == _Busy.checking,
            onPressed: _checkStatus,
          ),
          if (hasDemo) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              title: 'Demo: finish the review',
              trailing: const SimulatedLabel(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrimaryButton(
                    label: 'Simulate approval',
                    variant: ButtonVariant.outlined,
                    icon: Icons.verified_rounded,
                    isLoading: _busy == _Busy.approving,
                    onPressed: () => _simulate(approve: true),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PrimaryButton(
                    label: 'Simulate rejection',
                    variant: ButtonVariant.destructive,
                    icon: Icons.cancel_outlined,
                    isLoading: _busy == _Busy.rejecting,
                    onPressed: () => _simulate(approve: false),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Rejection marks your Aadhaar card as blurry so you can '
                    'try re-uploading.',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const BlockedAccountActions(),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.icon, this.label, {this.done = false});

  final IconData icon;
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      value: done ? 'Done' : 'Not done yet',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: done ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: done ? AppColors.textDark : AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
