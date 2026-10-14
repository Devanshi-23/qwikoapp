import 'package:flutter/material.dart';

import '../app/app_routes.dart';
import '../utils/app_colors.dart';

/// Persistent `DEMO` pill. Tapping explains demo mode; long-pressing opens
/// the demo tools.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});

  static const String explanation =
      'Demo mode: orders, customers, payouts, calls, chats and maps are '
      'simulated. No data leaves this device.';

  void _explain(BuildContext context) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(explanation)));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Demo mode',
      hint: 'Double tap for details. Long press for demo tools.',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _explain(context),
        onLongPress: () => Navigator.pushNamed(context, AppRoutes.demoControls),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.5),
                ),
              ),
              child: const Text(
                'DEMO',
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline "Simulated" marker for calls, chats, payouts, QR codes and SOS.
class SimulatedLabel extends StatelessWidget {
  const SimulatedLabel({super.key, this.text = 'Simulated'});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.science_outlined, size: 14, color: AppColors.info),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.info,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Why a control is disabled and how to unblock it, shown under it.
class DisabledReason extends StatelessWidget {
  const DisabledReason(
    this.reason, {
    super.key,
    this.icon = Icons.info_outline,
  });

  final String reason;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(reason, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
