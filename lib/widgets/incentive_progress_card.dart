import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../models/money.dart';
import '../utils/app_colors.dart';
import 'app_card.dart';
import 'status_badge.dart';

/// Tiered progress towards an incentive, with the next reward and time left.
class IncentiveProgressCard extends StatelessWidget {
  const IncentiveProgressCard({
    super.key,
    required this.incentive,
    required this.now,
    this.onTap,
  });

  final Incentive incentive;
  final DateTime now;
  final VoidCallback? onTap;

  static IconData iconFor(IncentiveType type) => switch (type) {
    IncentiveType.dailyMilestone => Icons.flag_rounded,
    IncentiveType.peakHours => Icons.bolt_rounded,
    IncentiveType.weeklyTarget => Icons.calendar_month_rounded,
    IncentiveType.rainBonus => Icons.water_drop_rounded,
  };

  String _span(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes < 1 ? 1 : d.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    final tiers = incentive.tiers;
    final goal = tiers.isEmpty ? 1 : tiers.last.target;
    final progress = incentive.progress;
    // Per-order bonuses have no goal; the bar shows how much of the window
    // has passed.
    final window = incentive.windowEnd.difference(incentive.windowStart);
    final fraction = incentive.isPerOrder
        ? (window.inSeconds == 0
                  ? 1.0
                  : now.difference(incentive.windowStart).inSeconds /
                        window.inSeconds)
              .clamp(0.0, 1.0)
        : (progress / goal).clamp(0.0, 1.0);
    final next = incentive.nextTier;
    final textTheme = Theme.of(context).textTheme;

    final timing = switch (incentive.status) {
      IncentiveStatus.upcoming =>
        'Starts ${formatDate(incentive.windowStart, now: now)}, '
            '${formatTime(incentive.windowStart)}',
      IncentiveStatus.active =>
        'Ends in ${_span(incentive.windowEnd.difference(now))}',
      IncentiveStatus.achieved || IncentiveStatus.missed =>
        'Ended ${formatDate(incentive.windowEnd, now: now)}',
    };
    final nextStep = incentive.isPerOrder
        ? '${formatPaise(tiers.isEmpty ? 0 : tiers.first.rewardPaise)} per '
              'order · ${formatPaise(incentive.earnedPaise)} earned'
        : next == null
        ? 'Top reward unlocked'
        : '${next.target - progress} more orders for '
              '${formatPaise(next.rewardPaise)}';

    final progressText = incentive.isPerOrder
        ? '$progress orders'
        : '$progress / $goal orders';
    return Semantics(
      label:
          '${incentive.title}. ${incentiveStatusStyle(incentive.status).label}. '
          '$progressText. $nextStep. $timing.',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(iconFor(incentive.type), color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(incentive.title, style: textTheme.titleSmall),
                      StatusBadge.incentive(incentive.status, dense: true),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: AppColors.border,
                color: incentive.status == IncentiveStatus.missed
                    ? AppColors.textGrey
                    : AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            if (!incentive.isPerOrder)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tier in tiers) _TierChip(tier, progress: progress),
                ],
              ),
            const SizedBox(height: 10),
            Text(
              '$progressText  •  $nextStep',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(timing, style: textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip(this.tier, {required this.progress});

  final IncentiveTier tier;
  final int progress;

  @override
  Widget build(BuildContext context) {
    final done = progress >= tier.target;
    final color = done ? AppColors.primary : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: done ? AppColors.primaryLight : AppColors.neutralLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${tier.target} · ${formatPaise(tier.rewardPaise)}',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
