import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../models/money.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/incentive_progress_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/state_views.dart';

/// Active, upcoming and finished incentives with their terms.
class IncentivesScreen extends StatefulWidget {
  const IncentivesScreen({super.key, this.openId});

  /// Incentive whose terms open first, from a link.
  final String? openId;

  @override
  State<IncentivesScreen> createState() => _IncentivesScreenState();
}

class _IncentivesScreenState extends State<IncentivesScreen> {
  late final _incentives = context.services.incentives;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _incentives.ensureLoaded();
      final open = _incentives.incentives
          .where((i) => i.id == widget.openId)
          .firstOrNull;
      if (open != null && mounted) showIncentiveTerms(context, open);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = context.services.clock.now();
    return AppScaffold(
      title: 'Incentives',
      showDemoBadge: true,
      body: ListenableBuilder(
        listenable: _incentives,
        builder: (context, _) {
          if (!_incentives.isReady) {
            final error = _incentives.error;
            return error == null
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: SkeletonList(count: 3),
                  )
                : ErrorState(message: error, onRetry: _incentives.load);
          }
          List<Incentive> withStatus(Set<IncentiveStatus> statuses) => [
            for (final incentive in _incentives.incentives)
              if (statuses.contains(incentive.status)) incentive,
          ];
          final sections = [
            ('Active now', withStatus({IncentiveStatus.active})),
            ('Upcoming', withStatus({IncentiveStatus.upcoming})),
            (
              'Finished',
              withStatus({IncentiveStatus.achieved, IncentiveStatus.missed}),
            ),
          ];
          return RefreshIndicator(
            onRefresh: _incentives.refresh,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                if (_incentives.incentives.isEmpty)
                  const EmptyState(
                    icon: Icons.local_fire_department_outlined,
                    title: 'No incentives right now',
                    message: 'New incentives show up here and on Home.',
                    boxed: true,
                  ),
                for (final (title, items) in sections)
                  if (items.isNotEmpty) ...[
                    SectionHeader(title),
                    for (final incentive in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: IncentiveProgressCard(
                          incentive: incentive,
                          now: now,
                          onTap: () => showIncentiveTerms(context, incentive),
                        ),
                      ),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

Future<void> showIncentiveTerms(BuildContext context, Incentive incentive) =>
    showAppBottomSheet<void>(
      context,
      title: incentive.title,
      subtitle: 'Terms',
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IncentiveProgressCard(
            incentive: incentive,
            now: context.services.clock.now(),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(incentive.terms, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Rewards are added to your earnings as soon as you reach them '
            'and paid out with your balance.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
