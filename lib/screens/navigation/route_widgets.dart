import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../controllers/navigation_controller.dart';
import '../../core/formatters.dart';
import '../../models/route.dart';
import '../../utils/app_colors.dart';
import '../../widgets/state_views.dart';

IconData maneuverIcon(Maneuver maneuver) => switch (maneuver) {
  Maneuver.depart => Icons.straight_rounded,
  Maneuver.left => Icons.turn_left_rounded,
  Maneuver.right => Icons.turn_right_rounded,
  Maneuver.straight => Icons.straight_rounded,
  Maneuver.arrive => Icons.flag_rounded,
};

/// Route summary over the map: skeleton while calculating, then
/// "8 min · 2.3 km · Arrive by 3:42 PM". Tapping lists the steps as text.
class RouteChip extends StatelessWidget {
  const RouteChip({super.key, required this.navigation});

  final NavigationController navigation;

  @override
  Widget build(BuildContext context) {
    final nav = navigation;
    final textTheme = Theme.of(context).textTheme;
    final leg = nav.leg;
    final Widget content;
    final summary = nav.summary;

    if (leg == null || nav.status == RouteStatus.idle) {
      return const SizedBox.shrink();
    } else if (nav.status == RouteStatus.calculating) {
      content = Semantics(
        label: 'Calculating route',
        liveRegion: true,
        child: const ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 150, height: 14),
              SizedBox(height: 6),
              SkeletonBox(width: 90, height: 10),
            ],
          ),
        ),
      );
    } else if (nav.status == RouteStatus.recalculating) {
      content = Semantics(
        liveRegion: true,
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Recalculating route…',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      final unavailable = nav.status == RouteStatus.unavailable;
      content = Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nav.arrived ? 'Arrived at ${leg.name}' : summary ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  unavailable
                      ? 'Route unavailable · straight-line estimate'
                      : 'To ${leg.name} · demo route',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: unavailable
                        ? AppColors.warning
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (unavailable)
            TextButton(onPressed: nav.retry, child: const Text('Retry'))
          else
            const Icon(Icons.list_rounded, color: AppColors.textSecondary),
        ],
      );
    }

    final canShowSteps = !nav.isPlanning && nav.route != null;
    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: canShowSteps ? () => showRouteSteps(context, nav) : null,
        child: Semantics(
          button: canShowSteps,
          hint: canShowSteps ? 'Shows turn-by-turn directions' : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Turn-by-turn directions as a list: the text version of the route.
Future<void> showRouteSteps(BuildContext context, NavigationController nav) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: nav,
        builder: (context, _) {
          final steps = nav.route?.steps ?? const <RouteStep>[];
          final ahead = nav.upcomingSteps.toSet();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.5,
            maxChildSize: 0.9,
            builder: (context, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: [
                Text(
                  'Directions to ${nav.leg?.name ?? 'destination'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (nav.summary case final summary?) Text(summary),
                const SizedBox(height: AppSpacing.sm),
                for (final step in steps)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: ahead.contains(step),
                    leading: Icon(maneuverIcon(step.maneuver)),
                    title: Text(step.instruction),
                    trailing: Text(formatStepDistance(step.distanceFromStartM)),
                  ),
              ],
            ),
          );
        },
      ),
    );

/// GPS lost, permission denied and location off, each with its fix.
class LocationBanners extends StatelessWidget {
  const LocationBanners({super.key, required this.navigation});

  final NavigationController navigation;

  @override
  Widget build(BuildContext context) {
    final nav = navigation;
    final device = context.services.device;
    final lastFix = nav.lastFixAt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (nav.permissionDenied)
          _MapBanner(
            icon: Icons.location_disabled_rounded,
            message:
                'Location access is off. Your position on the map is not '
                'updating.',
            actionLabel: 'Open settings',
            onAction: device.requestLocationPermission,
          )
        else if (nav.serviceOff)
          _MapBanner(
            icon: Icons.location_off_rounded,
            message: 'Location is turned off on this phone.',
            actionLabel: 'Turn on',
            onAction: device.enableLocationService,
          )
        else if (nav.gpsLost)
          _MapBanner(
            icon: Icons.gps_off_rounded,
            message:
                'GPS signal lost. Showing your last known position'
                '${lastFix == null ? '' : ' from ${formatTime(lastFix)}'}.',
          ),
      ],
    );
  }
}

class _MapBanner extends StatelessWidget {
  const _MapBanner({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: AppColors.textDark,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (label != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFB9F6CA),
                  ),
                  child: Text(label),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
