import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/formatters.dart';
import '../../models/trip.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/primary_button.dart';

/// The trip ended before pickup: why, and what the rider is paid for it
/// (plan 3.8.3).
class TripCancelledView extends StatelessWidget {
  const TripCancelledView({
    super.key,
    required this.trip,
    required this.busy,
    required this.onDone,
  });

  final DeliveryTrip trip;
  final bool busy;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final cancellation = trip.cancellation!;
    final textTheme = Theme.of(context).textTheme;
    final ids = trip.tasks.map((t) => t.displayId).join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('Order cancelled')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            const Icon(Icons.cancel_outlined, size: 56, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              liveRegion: true,
              child: Text(
                cancellation.reason,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$ids · cancelled by ${cancellation.by.label}',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppCard(
              title: 'Your pay for this trip',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cancellation.compensationPaise > 0)
                    _PayLine(
                      label: 'For your trip to the store',
                      paise: cancellation.compensationPaise,
                    ),
                  if (cancellation.waitingPaise > 0)
                    _PayLine(
                      label: 'Waiting pay',
                      paise: cancellation.waitingPaise,
                    ),
                  if (cancellation.totalPaise == 0)
                    Text(
                      'No compensation: you had travelled less than '
                      '${DeliveryTrip.compensationMinTravelM} m.',
                      style: textTheme.bodyMedium,
                    )
                  else
                    Text('Added to your earnings.', style: textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              "You'll get new offers once you leave.",
              textAlign: TextAlign.center,
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: PrimaryButton(
          label: cancellation.atStore
              ? "I'm leaving the store"
              : 'Back to Home',
          isLoading: busy,
          onPressed: onDone,
        ),
      ),
    );
  }
}

class _PayLine extends StatelessWidget {
  const _PayLine({required this.label, required this.paise});

  final String label;
  final int paise;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Text(label, style: textTheme.bodyMedium)),
          Text(formatPaise(paise), style: textTheme.titleSmall),
        ],
      ),
    );
  }
}
