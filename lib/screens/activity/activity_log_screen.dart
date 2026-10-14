import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../models/activity.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/section_header.dart';
import '../../widgets/state_views.dart';

enum ActivityFilter {
  all('All'),
  sessions('Sessions'),
  offers('Offers'),
  orders('Orders'),
  payouts('Money'),
  safety('SOS');

  const ActivityFilter(this.label);

  final String label;

  bool matches(ActivityType type) => switch (this) {
    ActivityFilter.all => true,
    ActivityFilter.sessions => type.isSession,
    ActivityFilter.offers => type.isOffer,
    ActivityFilter.orders =>
      type == ActivityType.delivered || type == ActivityType.cancelled,
    ActivityFilter.payouts =>
      type == ActivityType.payoutRequested ||
          type == ActivityType.cashDeposited,
    ActivityFilter.safety => type == ActivityType.sos,
  };
}

enum ActivityRange {
  week('Last 7 days', 7),
  today('Today', 1),
  yesterday('Yesterday', 2);

  const ActivityRange(this.label, this.days);

  final String label;
  final int days;

  bool contains(DateTime at, DateTime now) {
    final today = startOfDay(now);
    return switch (this) {
      ActivityRange.yesterday =>
        startOfDay(at) == today.subtract(const Duration(days: 1)),
      _ => !at.isBefore(today.subtract(Duration(days: days - 1))),
    };
  }
}

/// The last seven days of sessions, breaks, offer decisions, orders, money
/// and SOS events.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key, this.filter = ActivityFilter.all});

  final ActivityFilter filter;

  static IconData iconFor(ActivityType type) => switch (type) {
    ActivityType.wentOnline => Icons.power_settings_new_rounded,
    ActivityType.wentOffline => Icons.power_off_rounded,
    ActivityType.breakStarted ||
    ActivityType.breakEnded => Icons.coffee_rounded,
    ActivityType.offerAccepted => Icons.check_circle_outline_rounded,
    ActivityType.offerDeclined => Icons.cancel_outlined,
    ActivityType.offerMissed => Icons.timer_off_outlined,
    ActivityType.offerWithdrawn => Icons.person_off_outlined,
    ActivityType.delivered => Icons.inventory_2_outlined,
    ActivityType.cancelled => Icons.remove_shopping_cart_outlined,
    ActivityType.payoutRequested => Icons.account_balance_outlined,
    ActivityType.cashDeposited => Icons.payments_outlined,
    ActivityType.sos => Icons.sos_rounded,
  };

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  late ActivityFilter _filter = widget.filter;
  ActivityRange _range = ActivityRange.week;

  @override
  Widget build(BuildContext context) {
    final services = context.services;
    final availability = services.availability;

    return AppScaffold(
      title: 'Activity',
      body: ListenableBuilder(
        listenable: availability,
        builder: (context, _) {
          final now = services.clock.now();
          final events = availability.recentEvents
              .where(
                (e) => _filter.matches(e.type) && _range.contains(e.at, now),
              )
              .toList();
          final filtered =
              _filter != ActivityFilter.all || _range != ActivityRange.week;
          return RefreshIndicator(
            onRefresh: availability.loadActivity,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final filter in ActivityFilter.values)
                      ChoiceChip(
                        label: Text(filter.label),
                        selected: filter == _filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SegmentedButton<ActivityRange>(
                  segments: [
                    for (final range in ActivityRange.values)
                      ButtonSegment(value: range, label: Text(range.label)),
                  ],
                  selected: {_range},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      setState(() => _range = selection.single),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Online today: ${formatDuration(availability.onlineToday)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (events.isEmpty)
                  EmptyState(
                    icon: Icons.history_rounded,
                    title: filtered
                        ? 'No matching activity'
                        : 'Nothing here yet',
                    message: 'Activity from the last 7 days shows up here.',
                    actionLabel: filtered ? 'Clear filters' : null,
                    onAction: () => setState(() {
                      _filter = ActivityFilter.all;
                      _range = ActivityRange.week;
                    }),
                    boxed: true,
                  ),
                ..._buildGroups(events, now),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildGroups(List<ActivityEvent> events, DateTime now) {
    final widgets = <Widget>[];
    DateTime? day;
    for (final event in events) {
      final eventDay = startOfDay(event.at);
      if (eventDay != day) {
        day = eventDay;
        widgets.add(
          SectionHeader(
            formatDate(eventDay, now: now),
            padding: const EdgeInsets.only(top: AppSpacing.md, bottom: 4),
          ),
        );
      }
      widgets.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            ActivityLogScreen.iconFor(event.type),
            color: AppColors.primary,
          ),
          title: Text(event.type.label),
          subtitle: event.details.isEmpty ? null : Text(event.details),
          trailing: Text(
            formatTime(event.at),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return widgets;
  }
}
