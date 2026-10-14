import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/order.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/primary_button.dart';

/// Shown once every order of a trip has reached an end state: what each
/// order paid, today's totals, the next incentive, quick feedback, and
/// "Continue" or "Go offline".
class DeliveryCompleteScreen extends StatefulWidget {
  const DeliveryCompleteScreen({super.key, required this.tasks});

  final List<DeliveryTask> tasks;

  static const List<String> feedbackOptions = [
    'Store was quick',
    'Store was slow',
    'Customer was helpful',
    'Address was hard to find',
  ];

  @override
  State<DeliveryCompleteScreen> createState() => _DeliveryCompleteScreenState();
}

class _DeliveryCompleteScreenState extends State<DeliveryCompleteScreen> {
  final Set<String> _feedback = {};
  bool _feedbackSent = false;
  bool _goingOffline = false;

  int get _total => widget.tasks.fold(0, (sum, t) => sum + t.earnedPaise);

  bool get _allDelivered =>
      widget.tasks.every((t) => t.status == OrderStatus.delivered);

  Future<void> _goOffline() async {
    setState(() => _goingOffline = true);
    try {
      await context.services.availability.goOffline();
      if (mounted) Navigator.pop(context);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _goingOffline = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final services = context.services;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const SizedBox(height: AppSpacing.lg),
            Icon(
              _allDelivered
                  ? Icons.check_circle_rounded
                  : Icons.assignment_turned_in_rounded,
              size: 72,
              color: AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _allDelivered ? 'Delivered!' : 'Trip complete',
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall,
            ),
            Text(
              'You earned ${formatPaise(_total)}',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final task in widget.tasks) ...[
              _OrderPay(task: task),
              const SizedBox(height: AppSpacing.md),
            ],
            ListenableBuilder(
              listenable: Listenable.merge([
                services.earnings,
                services.incentives,
              ]),
              builder: (context, _) {
                final milestone = services.incentives.todayMilestone;
                final next = milestone?.nextTier;
                return AppCard(
                  title: 'Today',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Line(
                        'Earnings',
                        formatPaise(services.earnings.todayPaise),
                      ),
                      _Line('Orders', '${services.earnings.todayOrders}'),
                      if (milestone != null && next != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        LinearProgressIndicator(
                          value: milestone.progress / next.target,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${next.target - milestone.progress} more '
                          '${next.target - milestone.progress == 1 ? 'order' : 'orders'} '
                          'for ${formatPaise(next.rewardPaise)}',
                          style: textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              title: 'How did it go? (optional)',
              child: _feedbackSent
                  ? const Text('Thanks! Your feedback helps stores improve.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            for (final option
                                in DeliveryCompleteScreen.feedbackOptions)
                              FilterChip(
                                label: Text(option),
                                selected: _feedback.contains(option),
                                onSelected: (on) => setState(
                                  () => on
                                      ? _feedback.add(option)
                                      : _feedback.remove(option),
                                ),
                              ),
                          ],
                        ),
                        if (_feedback.isNotEmpty)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => _feedbackSent = true),
                              child: const Text('Send feedback'),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: 'Go offline',
              variant: ButtonVariant.outlined,
              isLoading: _goingOffline,
              onPressed: _goOffline,
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderPay extends StatelessWidget {
  const _OrderPay({required this.task});

  final DeliveryTask task;

  @override
  Widget build(BuildContext context) {
    final pay = task.payout;
    return AppCard(
      title: '${task.displayId} · ${task.status.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (task.status == OrderStatus.delivered) ...[
            _Line('Order pay', formatPaise(pay.orderPayPaise)),
            if (pay.surgePaise > 0) _Line('Surge', formatPaise(pay.surgePaise)),
            if (pay.batchBonusPaise > 0)
              _Line('Batch bonus', formatPaise(pay.batchBonusPaise)),
          ],
          if (pay.compensationPaise > 0)
            _Line('Compensation', formatPaise(pay.compensationPaise)),
          if (pay.waitingPaise > 0)
            _Line('Waiting pay', formatPaise(pay.waitingPaise)),
          if (task.proof case final proof?
              when proof.cashCollectedPaise + proof.upiCollectedPaise > 0)
            _Line(
              'Collected',
              [
                if (proof.cashCollectedPaise > 0)
                  '${formatPaise(proof.cashCollectedPaise)} cash',
                if (proof.upiCollectedPaise > 0)
                  '${formatPaise(proof.upiCollectedPaise)} UPI',
              ].join(' + '),
            ),
          const Divider(),
          _Line('Total', formatPaise(task.earnedPaise), bold: true),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.titleSmall
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(value, style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}
