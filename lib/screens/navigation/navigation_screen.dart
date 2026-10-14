import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../controllers/navigation_controller.dart';
import '../../core/formatters.dart';
import '../../utils/app_colors.dart';
import '../../widgets/delivery_map.dart';
import 'route_widgets.dart';

/// In-app turn-by-turn for the current leg on the demo map: the next
/// manoeuvre, distance to it, ETA and arrival time. Cues are haptic only;
/// "Mute" silences them.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late final NavigationController _nav = context.services.navigation;
  String? _lastCue;

  @override
  void initState() {
    super.initState();
    _nav.addListener(_onChange);
  }

  @override
  void dispose() {
    _nav.removeListener(_onChange);
    super.dispose();
  }

  /// A new manoeuvre or arrival gets a haptic cue and an announcement.
  void _onChange() {
    final step = _nav.nextStep;
    final cue = _nav.arrived
        ? 'arrived:${_nav.leg?.key}'
        : step == null
        ? null
        : '${step.instruction}@${step.distanceFromStartM}';
    if (cue == null || cue == _lastCue) return;
    final first = _lastCue == null;
    _lastCue = cue;
    if (first || !mounted) return;
    if (!_nav.muted) HapticFeedback.mediumImpact();
    SemanticsService.sendAnnouncement(
      View.of(context),
      _nav.arrived
          ? 'Arrived at ${_nav.leg?.name ?? 'destination'}'
          : step!.instruction,
      Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _nav,
        builder: (context, _) {
          final leg = _nav.leg;
          if (leg == null) {
            return SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No active route.'),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
            );
          }
          final map = Stack(
            children: [
              Positioned.fill(child: DeliveryMap(model: _nav.mapModel)),
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: LocationBanners(navigation: _nav),
              ),
            ],
          );

          return SafeArea(
            child: OrientationBuilder(
              builder: (context, orientation) {
                if (orientation == Orientation.landscape) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: map),
                      SizedBox(
                        width: 340,
                        child: ListView(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          children: [
                            _ManeuverCard(nav: _nav),
                            const SizedBox(height: AppSpacing.md),
                            _TripBar(nav: _nav),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                final height = MediaQuery.sizeOf(context).height;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: height * 0.3),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: _ManeuverCard(nav: _nav),
                      ),
                    ),
                    Expanded(child: map),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: height * 0.4),
                      child: SingleChildScrollView(child: _TripBar(nav: _nav)),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ManeuverCard extends StatelessWidget {
  const _ManeuverCard({required this.nav});

  final NavigationController nav;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final step = nav.nextStep;
    final distance = nav.distanceToNextStepM;
    final arrived = nav.arrived;

    final (IconData icon, String headline, String detail) = arrived
        ? (Icons.flag_rounded, 'You have arrived', nav.leg?.name ?? '')
        : nav.isPlanning || step == null
        ? (
            Icons.route_rounded,
            nav.status == RouteStatus.recalculating
                ? 'Recalculating route…'
                : 'Calculating route…',
            'To ${nav.leg?.name ?? 'destination'}',
          )
        : (
            maneuverIcon(step.maneuver),
            step.instruction,
            distance == null ? '' : 'In ${formatStepDistance(distance)}',
          );

    return Semantics(
      container: true,
      liveRegion: true,
      label: detail.isEmpty ? headline : '$detail, $headline',
      excludeSemantics: true,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 48),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        style: textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    Text(
                      headline,
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
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

class _TripBar extends StatelessWidget {
  const _TripBar({required this.nav});

  final NavigationController nav;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final eta = nav.eta;
    final remaining = nav.remainingM;
    final arrival = nav.arrivalTime;
    final known = eta != null && remaining != null && arrival != null;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              child: Text(
                known
                    ? '${formatMinutes(eta)} · ${formatDistance(remaining)} · '
                          'Arrive by ${formatTime(arrival)}'
                    : 'Working out your ETA…',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (nav.route?.isFallback ?? false)
              Text(
                'Straight-line estimate. Follow the roads you know.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.warning),
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  toggled: nav.muted,
                  child: IconButton.outlined(
                    tooltip: nav.muted ? 'Unmute cues' : 'Mute cues',
                    onPressed: nav.toggleMute,
                    icon: Icon(
                      nav.muted
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_active_outlined,
                    ),
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Directions list',
                  onPressed: nav.route == null
                      ? null
                      : () => showRouteSteps(context, nav),
                  icon: const Icon(Icons.list_rounded),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('End navigation'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
