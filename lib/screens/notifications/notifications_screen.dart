import 'package:flutter/material.dart';

import '../../app/app_links.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../controllers/loadable_controller.dart';
import '../../controllers/notifications_controller.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/notification.dart';
import '../../utils/app_colors.dart';
import '../../widgets/adaptive.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/state_views.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationsController _controller =
      context.services.notifications;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.ensureLoaded();
    });
  }

  Future<void> _attempt(Future<void> Function() action) async {
    try {
      await action();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  void _dismiss(AppNotification notification) {
    _attempt(() => _controller.dismiss(notification.id));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Notification removed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _attempt(() => _controller.restore(notification)),
          ),
        ),
      );
  }

  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final twoPane = Breakpoints.useTwoPane(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => AppScaffold(
        title: 'Notifications',
        maxWidth: twoPane ? double.infinity : AppSpacing.maxContentWidth,
        actions: [
          if (_controller.unreadCount > 0)
            IconButton(
              onPressed: () => _attempt(_controller.markAllRead),
              tooltip: 'Mark all read',
              color: AppColors.primary,
              icon: const Icon(Icons.done_all_rounded),
            ),
        ],
        body: twoPane ? _buildTwoPane() : _buildBody(),
      ),
    );
  }

  void _open(AppNotification n) {
    if (!n.isRead) _attempt(() => _controller.markRead(n.id));
    if (Breakpoints.useTwoPane(context)) {
      setState(() => _selectedId = n.id);
      return;
    }
    _follow(n);
  }

  void _follow(AppNotification n) {
    final link = n.deepLink;
    if (link != null) {
      openAppLink(Navigator.of(context), context.services, link);
    }
  }

  Widget _buildBody() {
    final all = _controller.items;
    if (all.isEmpty) return _buildList(all);
    return Column(
      children: [
        _buildFilters(),
        Expanded(child: _buildList(_controller.visibleItems)),
      ],
    );
  }

  Widget _buildTwoPane() {
    final selected = _controller.items
        .where((n) => n.id == _selectedId)
        .firstOrNull;
    return TwoPane(
      list: _buildBody(),
      detail: selected == null
          ? const Center(
              child: EmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'Select a notification',
                message: 'Its full message shows here.',
              ),
            )
          : _buildPreview(selected),
    );
  }

  Widget _buildPreview(AppNotification n) {
    final (icon, color) = _styleFor(n.category);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(
              n.category.label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          n.title,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          timeAgo(n.at, now: context.services.clock.now()),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Text(
          n.body,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 15,
            height: 1.5,
          ),
        ),
        if (n.deepLink != null) ...[
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _follow(n),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFilters() {
    final filter = _controller.filter;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        children: [
          for (final category in <NotificationCategory?>[
            null,
            ...NotificationCategory.values,
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category?.label ?? 'All'),
                selected: filter == category,
                onSelected: (_) => _controller.setFilter(category),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList(List<AppNotification> items) {
    if (_controller.status == LoadStatus.error && items.isEmpty) {
      return Center(
        child: ErrorState(
          message: _controller.error!,
          onRetry: _controller.load,
        ),
      );
    }
    if (!_controller.isReady && items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SkeletonList(count: 5),
      );
    }
    final filter = _controller.filter;
    if (items.isEmpty && filter != null) {
      return Center(
        child: EmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: 'No ${filter.label.toLowerCase()} notifications',
          message: 'Try another category.',
          actionLabel: 'Show all',
          onAction: () => _controller.setFilter(null),
        ),
      );
    }
    if (items.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.notifications_off_outlined,
          title: 'No notifications yet',
          message: 'Order updates, payouts and alerts will appear here.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final n = items[index];
          return Dismissible(
            key: ValueKey(n.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.white,
              ),
            ),
            onDismissed: (_) => _dismiss(n),
            child: _buildTile(n),
          );
        },
      ),
    );
  }

  (IconData, Color) _styleFor(NotificationCategory category) =>
      switch (category) {
        NotificationCategory.offer => (
          Icons.delivery_dining_rounded,
          AppColors.primary,
        ),
        NotificationCategory.earnings => (
          Icons.account_balance_wallet_rounded,
          const Color(0xFF0C7634),
        ),
        NotificationCategory.incentive => (
          Icons.local_fire_department_rounded,
          const Color(0xFFF59E0B),
        ),
        NotificationCategory.account => (
          Icons.verified_rounded,
          const Color(0xFF2F80ED),
        ),
        NotificationCategory.safety => (
          Icons.health_and_safety_rounded,
          AppColors.error,
        ),
        NotificationCategory.system => (
          Icons.info_outline_rounded,
          AppColors.textSecondary,
        ),
      };

  Widget _buildTile(AppNotification n) {
    final (icon, color) = _styleFor(n.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: n.isRead ? Colors.white : const Color(0xFFF3FAF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: n.isRead
              ? AppColors.border
              : AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap:
            n.isRead && n.deepLink == null && !Breakpoints.useTwoPane(context)
            ? null
            : () => _open(n),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontSize: 14,
                              fontWeight: n.isRead
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!n.isRead)
                          Container(
                            height: 8,
                            width: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.body,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeAgo(n.at, now: context.services.clock.now()),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
