import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../core/formatters.dart';
import '../models/geo_point.dart';
import '../models/trip.dart';
import '../utils/app_colors.dart';
import 'money_text.dart';
import 'route_preview.dart';
import 'stop_tile.dart';

IconData offerTagIcon(OfferTag tag) => switch (tag) {
  OfferTag.heavy => Icons.fitness_center_rounded,
  OfferTag.fragile => Icons.wine_bar_outlined,
  OfferTag.coldChain => Icons.ac_unit_rounded,
  OfferTag.pharmacy => Icons.medication_outlined,
};

/// Everything a rider needs to judge an offer: pay with breakdown, route,
/// stops, size, payment and handling tags. Drops show the locality only
/// until the offer is accepted.
class OfferDetails extends StatelessWidget {
  const OfferDetails({
    super.key,
    required this.offer,
    required this.rider,
    this.trailing,
    this.warning,
  });

  final DeliveryOffer offer;

  /// Rider position, for the route preview.
  final GeoPoint rider;

  /// Shown next to the pay, for example a countdown.
  final Widget? trailing;

  /// Shown under the pay, for example why the offer can't be accepted.
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final trailing = this.trailing;
    final warning = this.warning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Pill(
                    offer.isBatched
                        ? 'BATCHED · ${offer.drops.length} DROPS'
                        : 'NEW ORDER',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  MoneyText(
                    offer.payout.totalPaise,
                    prefix: 'Earn ',
                    style: textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        _PayBreakdown(offer: offer),
        if (warning != null) _Warning(warning),
        const SizedBox(height: AppSpacing.md),
        RoutePreview(
          rider: rider,
          store: offer.pickup.location,
          storeLabel: offer.pickup.name,
          drops: [for (final drop in offer.drops) drop.location],
        ),
        const SizedBox(height: AppSpacing.lg),
        StopTile(
          kind: StopKind.pickup,
          distanceM: offer.distanceToPickupM,
          title: offer.pickup.name,
          subtitle: offer.pickup.address,
          subtitleMaxLines: 2,
        ),
        for (final (index, drop) in offer.drops.indexed) ...[
          const StopConnector(),
          StopTile(
            kind: StopKind.drop,
            label: offer.isBatched ? 'Drop ${index + 1}' : 'Drop',
            title: drop.address,
            subtitle: 'Full address after you accept',
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _Fact(
              Icons.route_rounded,
              '${formatDistance(offer.tripDistanceM)} trip',
            ),
            _Fact(Icons.schedule_rounded, '~${offer.estimatedMinutes} min'),
            _Fact(
              Icons.shopping_bag_outlined,
              '${offer.itemCount} items · ${offer.bagSize.label}',
            ),
            offer.isCod
                ? _Fact(
                    Icons.payments_outlined,
                    'Collect cash ${formatPaise(offer.codAmountPaise)}',
                    color: AppColors.warning,
                  )
                : const _Fact(Icons.verified_outlined, 'Paid online'),
          ],
        ),
        for (final tag in offer.tags) ...[
          const SizedBox(height: AppSpacing.sm),
          _TagNote(tag),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _PayBreakdown extends StatelessWidget {
  const _PayBreakdown({required this.offer});

  final DeliveryOffer offer;

  @override
  Widget build(BuildContext context) {
    final payout = offer.payout;
    final orders = offer.orders.length;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
        title: Text(
          'Pay breakdown',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
        ),
        children: [
          _PayRow(
            orders > 1 ? 'Base pay ($orders orders)' : 'Base pay',
            payout.basePaise,
          ),
          _PayRow('Distance pay', payout.distancePaise),
          if (payout.surgePaise > 0) _PayRow('Surge', payout.surgePaise),
          if (payout.batchBonusPaise > 0)
            _PayRow('Batch bonus', payout.batchBonusPaise),
          const Divider(height: AppSpacing.lg),
          _PayRow('Total', payout.totalPaise, bold: true),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const ExcludeSemantics(
                child: Icon(
                  Icons.volunteer_activism_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tip possible: customers can add one after delivery.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PayRow extends StatelessWidget {
  const _PayRow(this.label, this.paise, {this.bold = false});

  final String label;
  final int paise;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: AppColors.textDark,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(child: Text(label, style: style)),
            MoneyText(paise, style: style),
          ],
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(
            child: Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text, {this.color = AppColors.textDark});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.neutralLight,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 16, color: color)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagNote extends StatelessWidget {
  const _TagNote(this.tag);

  final OfferTag tag;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(offerTagIcon(tag), size: 18, color: AppColors.info),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${tag.label}: ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: tag.instruction),
                ],
              ),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}
