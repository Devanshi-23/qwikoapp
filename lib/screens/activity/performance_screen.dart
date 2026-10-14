import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../controllers/history_controller.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/stat_tile.dart';

/// Acceptance, completion and on-time rates plus rating, each with how it
/// is calculated.
class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.services.history.ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = context.services;
    final availability = services.availability;

    return AppScaffold(
      title: 'Performance',
      body: ListenableBuilder(
        listenable: Listenable.merge([
          availability,
          services.profile,
          services.history,
        ]),
        builder: (context, _) {
          final stats = availability.acceptance;
          final week = services.history.lastWeek;
          final rating = services.profile.profile?.rating;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              _RateCard(
                title: 'Acceptance rate · last $performanceDays days',
                percent: stats.percent,
                emptyText: 'No offers yet',
                tiles: [
                  ('${stats.accepted}', 'Accepted'),
                  ('${stats.declined}', 'Declined'),
                  ('${stats.missed}', 'Missed'),
                ],
                explanation:
                    'Accepted offers divided by all offers you received '
                    '(accepted, declined and missed). Offers that time out '
                    'count as missed.',
              ),
              _RateCard(
                title: 'Completion rate · last $performanceDays days',
                percent: week?.completionPercent,
                emptyText: 'No orders yet',
                tiles: [
                  ('${week?.deliveredCount ?? 0}', 'Delivered'),
                  ('${week?.orderCount ?? 0}', 'Accepted'),
                ],
                explanation:
                    'Delivered orders divided by every order you accepted. '
                    'Cancelled and returned orders lower it.',
              ),
              _RateCard(
                title: 'On-time rate · last $performanceDays days',
                percent: week?.onTimePercent,
                emptyText: 'No deliveries yet',
                tiles: [
                  ('${week?.onTimeCount ?? 0}', 'On time'),
                  ('${week?.deliveredCount ?? 0}', 'Delivered'),
                ],
                explanation:
                    'Deliveries completed by the time promised to the '
                    'customer, divided by all deliveries.',
              ),
              if (rating != null)
                _RateCard(
                  title: 'Customer rating',
                  value: '${rating.average.toStringAsFixed(1)} ★',
                  explanation:
                      'Average of ${rating.count} ratings from customers.',
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({
    required this.title,
    required this.explanation,
    this.percent,
    this.value,
    this.emptyText = '',
    this.tiles = const [],
  });

  final String title;
  final String explanation;
  final int? percent;
  final String? value;
  final String emptyText;
  final List<(String, String)> tiles;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final percent = this.percent;
    return AppCard(
      title: title,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value ?? (percent == null ? emptyText : '$percent%'),
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          if (tiles.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                for (final (index, (tileValue, label)) in tiles.indexed) ...[
                  if (index > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: StatTile(value: tileValue, label: label),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(explanation, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}
