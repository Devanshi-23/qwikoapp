import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../models/partner.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/section_header.dart';
import '../../widgets/state_views.dart';

class RatingsScreen extends StatelessWidget {
  const RatingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.services.profile;
    return AppScaffold(
      title: 'Ratings & feedback',
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final rating = controller.profile?.rating;
          if (rating == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (rating.count == 0) {
            return const Center(
              child: EmptyState(
                icon: Icons.star_outline_rounded,
                title: 'No ratings yet',
                message: 'Customers can rate you after each delivery.',
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _Summary(rating: rating),
              const SizedBox(height: 24),
              if (rating.recentCompliments.isNotEmpty) ...[
                const SectionHeader('What customers liked'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final compliment in rating.recentCompliments)
                      Chip(
                        avatar: const Icon(
                          Icons.thumb_up_alt_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        label: Text(compliment),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
              if (rating.tips.isNotEmpty) ...[
                const SectionHeader('Tips to improve'),
                for (final tip in rating.tips)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: Color(0xFFF59E0B),
                    ),
                    title: Text(tip),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.rating});

  final RatingSummary rating;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final max = rating.distribution.fold(1, (a, b) => a > b ? a : b);
    final average = Semantics(
      label:
          'Average rating ${rating.average.toStringAsFixed(1)} out of 5 '
          'from ${rating.count} ratings',
      excludeSemantics: true,
      child: Column(
        children: [
          Text(
            rating.average.toStringAsFixed(1),
            style: textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
          const SizedBox(height: 4),
          Text('${rating.count} ratings', style: textTheme.bodySmall),
        ],
      ),
    );
    final bars = Column(
      children: [
        for (var stars = 5; stars >= 1; stars--)
          _Bar(
            stars: stars,
            count: rating.distribution[stars - 1],
            fraction: rating.distribution[stars - 1] / max,
          ),
      ],
    );
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 360
            ? Column(children: [average, const SizedBox(height: 16), bars])
            : Row(
                children: [
                  average,
                  const SizedBox(width: 20),
                  Expanded(child: bars),
                ],
              ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.stars,
    required this.count,
    required this.fraction,
  });

  final int stars;
  final int count;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$stars star: $count ratings',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 14, child: Text('$stars')),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 40,
              child: Text(
                '$count',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
