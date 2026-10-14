import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/formatters.dart';
import '../../models/announcement.dart';
import '../../models/trip.dart';
import '../../models/zone.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../orders/active_order_screen.dart';

/// "Resume order #QW1031 · Picking up" while a trip is in progress.
class ActiveOrderBanner extends StatelessWidget {
  const ActiveOrderBanner({super.key, required this.trip, required this.onTap});

  final DeliveryTrip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final task = trip.currentTask;
    final step = trip.cancellation != null
        ? 'Cancelled, see compensation'
        : switch (stepFor(task.status)) {
            DeliveryStep.toStore => 'Going to store',
            DeliveryStep.atStore => 'Picking up',
            DeliveryStep.toCustomer => 'Delivering',
            DeliveryStep.atCustomer => 'At customer',
            DeliveryStep.returning => 'Returning to store',
            DeliveryStep.done => 'Update waiting',
          };
    final extra = trip.tasks.length > 1 ? ' (${trip.tasks.length} orders)' : '';

    return Semantics(
      button: true,
      label: 'Resume order ${task.displayId}, $step$extra',
      excludeSemantics: true,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                const Icon(Icons.delivery_dining_rounded, color: Colors.white),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Resume order ${task.displayId} · $step$extra',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Points the rider to a busier zone nearby.
class DemandNudgeCard extends StatelessWidget {
  const DemandNudgeCard({
    super.key,
    required this.zone,
    required this.distanceM,
    required this.onViewMap,
    required this.onMove,
  });

  final DeliveryZone zone;
  final int distanceM;
  final VoidCallback onViewMap;

  /// Null while a trip is in progress.
  final VoidCallback? onMove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      borderColor: AppColors.warning,
      color: AppColors.warningLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  '${zone.demand.label} in ${zone.name} · '
                  '${zone.surgeMultiplier.toStringAsFixed(1)}× · '
                  '${formatDistance(distanceM)} away',
                  style: textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              TextButton.icon(
                onPressed: onViewMap,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('View on map'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  minimumSize: const Size(48, 44),
                ),
              ),
              TextButton.icon(
                onPressed: onMove,
                icon: const Icon(Icons.near_me_outlined, size: 18),
                label: const Text('Move to zone'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  minimumSize: const Size(48, 44),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({
    super.key,
    required this.announcement,
    required this.onDismiss,
    this.onOpen,
  });

  final Announcement announcement;
  final VoidCallback onDismiss;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (icon, color, background) = switch (announcement.kind) {
      AnnouncementKind.weather => (
        Icons.thunderstorm_outlined,
        AppColors.info,
        AppColors.infoLight,
      ),
      AnnouncementKind.incentive => (
        Icons.emoji_events_outlined,
        AppColors.primary,
        AppColors.primaryLight,
      ),
      AnnouncementKind.info => (
        Icons.campaign_outlined,
        AppColors.textSecondary,
        AppColors.neutralLight,
      ),
    };
    final linkLabel = announcement.linkLabel;

    return AppCard(
      color: background,
      borderColor: background,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(announcement.title, style: textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(announcement.body, style: textTheme.bodySmall),
                if (linkLabel != null && onOpen != null)
                  TextButton(
                    onPressed: onOpen,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 40),
                      foregroundColor: color,
                    ),
                    child: Text(linkLabel),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss ${announcement.title}',
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

/// One-off message from the availability controller, such as being taken
/// offline by a new blocker.
class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: AppCard(
        color: AppColors.infoLight,
        borderColor: AppColors.infoLight,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.info),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// Online with no offer yet: a radar sweep (static when the platform asks
/// for reduced motion) and tips for getting more orders.
class WaitingForOffers extends StatefulWidget {
  const WaitingForOffers({super.key});

  static const tips = [
    'Stay close to stores in busy zones.',
    'Keep mobile data and location on.',
    'Accept offers quickly to keep your acceptance rate up.',
  ];

  @override
  State<WaitingForOffers> createState() => _WaitingForOffersState();
}

class _WaitingForOffersState extends State<WaitingForOffers>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0.6;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: 96,
              width: 96,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) =>
                    CustomPaint(painter: _RadarPainter(_controller.value)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: true,
            child: Text(
              'Looking for orders near you…',
              textAlign: TextAlign.center,
              style: textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final tip in WaitingForOffers.tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 16,
                    color: AppColors.accentDark,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(tip, style: textTheme.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1;
      canvas.drawCircle(
        center,
        maxRadius * t,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.accent.withValues(alpha: 1 - t),
      );
    }
    canvas.drawCircle(center, 8, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
