import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../core/failures.dart';
import '../../utils/app_colors.dart';
import '../../widgets/dialogs.dart';
import '../support/help_support_screen.dart';

/// Signs out after confirming and returns to Login.
Future<void> confirmSignOut(BuildContext context) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Log out?',
    message: 'You can sign in again at any time.',
    confirmLabel: 'Log out',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await context.services.session.signOut();
  } on AppFailure catch (failure) {
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    return;
  }
  navigator.pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
}

/// The only ways out of a blocked account screen: Help, Demo controls and
/// Log out (plan 3.8.8).
class BlockedAccountActions extends StatelessWidget {
  const BlockedAccountActions({super.key, this.helpRequest});

  /// Prefills a support ticket when Help is opened.
  final HelpRequest? helpRequest;

  @override
  Widget build(BuildContext context) {
    final hasDemo = context.services.demo != null;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      children: [
        TextButton.icon(
          onPressed: () => Navigator.pushNamed(
            context,
            AppRoutes.help,
            arguments: helpRequest,
          ),
          icon: const Icon(Icons.support_agent_rounded, size: 18),
          label: const Text('Help'),
        ),
        if (hasDemo)
          TextButton.icon(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.demoControls),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Demo controls'),
          ),
        TextButton.icon(
          onPressed: () => confirmSignOut(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Log out'),
        ),
      ],
    );
  }
}
