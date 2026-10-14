import 'package:flutter/material.dart';

import '../../app/app_links.dart';
import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_services.dart';
import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/announcement.dart';
import '../../models/availability.dart';
import '../../models/money.dart';
import '../../models/zone.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/incentive_progress_card.dart';
import '../../widgets/media_image.dart';
import '../../widgets/money_text.dart';
import '../../widgets/order_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/state_views.dart';
import '../activity/activity_log_screen.dart';
import '../orders/open_active_order.dart';
import 'availability_card.dart';
import 'dashboard_cards.dart';

/// The Home tab: status and availability, what to do now, and today's
/// numbers.
class DashboardView extends StatefulWidget {
  const DashboardView({super.key, required this.onOpenTab});

  /// Switches the bottom navigation tab (1 Orders, 2 Earnings, 3 Profile).
  final ValueChanged<int> onOpenTab;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late final AppServices _services = context.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _services.earnings.ensureLoaded();
      _services.history.ensureLoaded();
      _services.notifications.ensureLoaded();
      _services.wallet.ensureLoaded();
      _services.incentives.ensureLoaded();
      _services.zones.ensureLoaded();
      _services.availability.loadActivity();
    });
  }

  Future<void> _refresh() => Future.wait([
    _services.earnings.refresh(),
    _services.history.refresh(),
    _services.notifications.refresh(),
    _services.wallet.refresh(),
    _services.incentives.refresh(),
    _services.zones.refresh(),
    _services.availability.loadActivity(),
  ]);

  void _showMessage(String text, {Color? color}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on AppFailure catch (failure) {
      if (mounted) _showMessage(failure.message);
    }
  }

  Future<void> _toggleOnline(bool value) async {
    final availability = _services.availability;
    if (!value) {
      final risk = _services.incentives.rewardAtRisk;
      if (risk != null) {
        final orders = risk.orders == 1 ? '1 order' : '${risk.orders} orders';
        final confirmed = await showConfirmDialog(
          context,
          title: 'Go offline?',
          message:
              "You're $orders away from ${formatPaise(risk.rewardPaise)}. "
              'Go offline anyway?',
          confirmLabel: 'Go offline',
          cancelLabel: 'Stay online',
        );
        if (!confirmed || !mounted) return;
      }
    }
    try {
      value ? await availability.goOnline() : await availability.goOffline();
    } on AppFailure catch (failure) {
      if (mounted) _showMessage(failure.message);
      return;
    }
    if (!mounted) return;
    _showMessage(
      value
          ? 'You are online. New orders will appear here.'
          : 'You are offline. You will not receive orders.',
      color: value ? AppColors.primary : AppColors.textDark,
    );
  }

  Future<void> _takeBreak() async {
    final length = await showAppBottomSheet<Duration>(
      context,
      title: 'Take a break',
      subtitle: "Offers pause during your break. You'll stay online.",
      builder: (context) => Column(
        children: [
          for (final length in breakLengths)
            ListTile(
              leading: const Icon(Icons.coffee_outlined),
              title: Text('${length.inMinutes} minutes'),
              onTap: () => Navigator.pop(context, length),
            ),
        ],
      ),
    );
    if (length == null || !mounted) return;
    await _guard(() async {
      await _services.availability.startBreak(length);
      if (mounted) {
        _showMessage(
          'Break started. Offers paused for ${length.inMinutes} min.',
        );
      }
    });
  }

  Future<void> _endBreak() => _guard(() async {
    await _services.availability.endBreak();
    if (mounted) _showMessage("Break ended. You'll receive orders again.");
  });

  Future<void> _fixBlocker(OnlineBlocker blocker) async {
    final navigator = Navigator.of(context);
    switch (blocker.type) {
      case OnlineBlockerType.accountSuspended ||
          OnlineBlockerType.verificationPending:
        final profile = _services.profile.profile;
        if (profile != null) AppRoutes.goToAccountHome(navigator, profile);
      case OnlineBlockerType.documentExpired:
        navigator.pushNamed(AppRoutes.documents);
      case OnlineBlockerType.cashLimitReached:
        navigator.pushNamed(AppRoutes.cashInHand);
      case OnlineBlockerType.locationPermissionOff:
        await _askLocationPermission();
      case OnlineBlockerType.locationServiceOff:
        await _services.device.enableLocationService();
        if (mounted) _showMessage('Location turned on (simulated).');
      case OnlineBlockerType.networkOffline:
        if (_services.demo != null) {
          navigator.pushNamed(AppRoutes.demoControls);
        } else {
          _showMessage("Still offline. Check mobile data or Wi-Fi.");
        }
    }
  }

  /// Stands in for the system permission prompt.
  Future<void> _askLocationPermission() async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Allow Qwiko Partner to access this device\'s location?',
        ),
        content: const SimulatedLabel(text: 'Simulated system prompt'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Don't allow"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('While using the app'),
          ),
        ],
      ),
    );
    if (allowed != true || !mounted) return;
    await _services.device.requestLocationPermission();
    if (mounted) _showMessage('Location access allowed.');
  }

  void _moveToZone(DeliveryZone zone) {
    try {
      _services.availability.moveToZone(zone.id, zone.center);
    } on AppFailure catch (failure) {
      _showMessage(failure.message);
      return;
    }
    _showMessage("You're now in ${zone.name}. Offers come from here.");
  }

  void _openIncentive(Incentive incentive) {
    final now = _services.clock.now();
    showAppBottomSheet<void>(
      context,
      title: incentive.title,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IncentiveProgressCard(incentive: incentive, now: now),
          const SizedBox(height: AppSpacing.md),
          Text(incentive.terms, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  void _openAnnouncement(Announcement announcement) {
    final link = announcement.link;
    if (link == null) return;
    openAppLink(Navigator.of(context), _services, link);
  }

  Future<void> _dismissAnnouncement(Announcement announcement) => _guard(
    () => _services.notifications.dismissAnnouncement(announcement.id),
  );

  @override
  Widget build(BuildContext context) {
    final s = _services;
    return ListenableBuilder(
      listenable: Listenable.merge([
        s.profile,
        s.availability,
        s.offers,
        s.trip,
        s.earnings,
        s.history,
        s.notifications,
        s.wallet,
        s.incentives,
        s.zones,
      ]),
      builder: (context, _) => RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            ..._buildStatusSection(),
            const SizedBox(height: 24),
            const SectionHeader("Today's summary"),
            _buildSummary(),
            ..._buildCashInHand(),
            ..._buildIncentive(),
            ..._buildDemandNudge(),
            ..._buildAnnouncements(),
            const SizedBox(height: 24),
            ..._buildRecentDeliveries(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final textTheme = Theme.of(context).textTheme;
    final firstName = _services.profile.profile?.firstName ?? 'Rider';
    final unread = _services.notifications.unreadCount;
    final photo = mediaImageProvider(_services.profile.profile?.photo);

    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Open profile',
          child: GestureDetector(
            onTap: () => widget.onOpenTab(3),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primaryLight,
              backgroundImage: photo,
              child: photo == null
                  ? const Icon(Icons.person_rounded, color: AppColors.primary)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $firstName 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                'Ready to deliver today?',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const DemoBadge(),
        IconButton(
          tooltip: 'Safety',
          onPressed: () => Navigator.pushNamed(context, AppRoutes.safety),
          icon: const Icon(Icons.shield_outlined, color: AppColors.error),
        ),
        IconButton(
          tooltip: unread > 0
              ? 'Notifications, $unread unread'
              : 'Notifications',
          onPressed: () =>
              Navigator.pushNamed(context, AppRoutes.notifications),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            backgroundColor: AppColors.error,
            child: const Icon(
              Icons.notifications_none_rounded,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }

  /// Notice, active order, availability (or blockers) and the offer area.
  List<Widget> _buildStatusSection() {
    final availability = _services.availability;
    final trip = _services.trip.trip;
    final offer = _services.offers.offer;
    final notice = availability.notice;
    final blockers = availability.blockers;
    final zoneName =
        _services.zones.byId(availability.zoneId)?.name ?? 'Your zone';

    return [
      if (notice != null) ...[
        NoticeCard(
          message: notice,
          onClose: () => setState(availability.clearNotice),
        ),
        const SizedBox(height: 12),
      ],
      if (trip != null) ...[
        ActiveOrderBanner(trip: trip, onTap: () => openActiveOrder(context)),
        const SizedBox(height: 12),
      ],
      if (!availability.isOnline && blockers.isNotEmpty)
        OnlineBlockersCard(blockers: blockers, onFix: _fixBlocker)
      else
        AvailabilityCard(
          status: availability.status,
          onlineToday: availability.onlineToday,
          zoneName: zoneName,
          busy: availability.isBusy,
          hasTrip: trip != null,
          breakRemaining: availability.breakRemaining,
          onToggle: _toggleOnline,
          onTakeBreak: _takeBreak,
          onEndBreak: _endBreak,
        ),
      if (trip == null && offer == null && availability.receivesOffers) ...[
        const SizedBox(height: 16),
        const WaitingForOffers(),
      ],
    ];
  }

  Widget _buildSummary() {
    final earnings = _services.earnings;
    final availability = _services.availability;
    if (!earnings.isReady) {
      final error = earnings.error;
      if (error != null) {
        return ErrorState(
          message: error,
          onRetry: earnings.load,
          compact: true,
        );
      }
      return const Column(
        children: [
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 88)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 88)),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 88)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 88)),
            ],
          ),
        ],
      );
    }
    final percent = availability.acceptance.percent;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.currency_rupee_rounded,
                label: 'Earnings',
                value: formatPaise(earnings.todayPaise),
                semanticValue: spokenPaise(earnings.todayPaise),
                onTap: () => widget.onOpenTab(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                icon: Icons.shopping_bag_outlined,
                label: 'Orders',
                value: '${earnings.todayOrders}',
                onTap: () => widget.onOpenTab(1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.timer_outlined,
                label: 'Online',
                value: formatDuration(availability.onlineToday),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.activityLog,
                  arguments: ActivityFilter.sessions,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                icon: Icons.thumb_up_alt_outlined,
                label: 'Acceptance',
                value: percent == null ? 'No offers' : '$percent%',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.performance),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildCashInHand() {
    final wallet = _services.wallet;
    if (!wallet.isReady || wallet.cash.balancePaise <= 0) return const [];
    final cash = wallet.cash;
    final over = cash.balancePaise >= cash.limitPaise;
    final textTheme = Theme.of(context).textTheme;

    return [
      const SizedBox(height: 12),
      AppCard(
        borderColor: over ? AppColors.error : AppColors.border,
        onTap: () => Navigator.pushNamed(context, AppRoutes.cashInHand),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              Icons.payments_outlined,
              color: over ? AppColors.error : AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cash in hand', style: textTheme.bodySmall),
                  MoneyText(
                    cash.balancePaise,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: over ? AppColors.error : AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Text(
                'Limit ${formatPaise(cash.limitPaise)}',
                textAlign: TextAlign.end,
                style: textTheme.bodySmall,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textGrey),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildIncentive() {
    final incentives = _services.incentives;
    final incentive = incentives.todayMilestone;
    if (!incentives.isReady) {
      final error = incentives.error;
      return [
        const SizedBox(height: 24),
        const SectionHeader("Today's incentive"),
        error == null
            ? const SkeletonBox(height: 140)
            : ErrorState(
                message: error,
                onRetry: incentives.load,
                compact: true,
              ),
      ];
    }
    if (incentive == null) return const [];
    return [
      const SizedBox(height: 24),
      const SectionHeader("Today's incentive"),
      IncentiveProgressCard(
        incentive: incentive,
        now: _services.clock.now(),
        onTap: () => _openIncentive(incentive),
      ),
    ];
  }

  List<Widget> _buildDemandNudge() {
    final availability = _services.availability;
    if (_services.trip.hasTrip) return const [];
    final zone = _services.zones.hottestNearby(
      availability.zoneId,
      availability.position,
    );
    if (zone == null) return const [];
    return [
      const SizedBox(height: 16),
      DemandNudgeCard(
        zone: zone,
        distanceM: availability.position.distanceMetersTo(zone.center),
        onViewMap: () => Navigator.pushNamed(context, AppRoutes.demandMap),
        onMove: () => _moveToZone(zone),
      ),
    ];
  }

  List<Widget> _buildAnnouncements() {
    final announcements = _services.notifications.announcements;
    return [
      for (final announcement in announcements) ...[
        const SizedBox(height: 12),
        AnnouncementCard(
          key: ValueKey(announcement.id),
          announcement: announcement,
          onDismiss: () => _dismissAnnouncement(announcement),
          onOpen: announcement.link == null
              ? null
              : () => _openAnnouncement(announcement),
        ),
      ],
    ];
  }

  List<Widget> _buildRecentDeliveries() {
    final history = _services.history;
    final recent = history.recent;
    final now = _services.clock.now();
    final error = history.error;

    return [
      SectionHeader(
        'Recent deliveries',
        actionLabel: 'See all',
        onAction: () => widget.onOpenTab(1),
      ),
      if (recent.isEmpty && !history.isReady && error != null)
        ErrorState(message: error, onRetry: history.load, compact: true)
      else if (recent.isEmpty && !history.isReady)
        const SkeletonList(count: 3)
      else if (recent.isEmpty)
        const EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'No deliveries yet',
          message: 'Your completed deliveries will show up here.',
          boxed: true,
        ),
      for (final order in recent)
        OrderCard(
          order: order,
          when: formatDateTime(order.lastUpdatedAt, now: now),
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.orderDetails,
            arguments: order.orderId,
          ),
        ),
    ];
  }
}
