import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/geo_point.dart';
import '../../models/zone.dart';
import '../../services/maps/map_view_model.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/delivery_map.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/state_views.dart';

Color demandColor(DemandLevel level) => switch (level) {
  DemandLevel.low => AppColors.textGrey,
  DemandLevel.normal => AppColors.info,
  DemandLevel.high => AppColors.warning,
  DemandLevel.surge => AppColors.error,
};

/// Zone demand as a heat overlay on the demo map, with "Move here" to
/// simulate riding to a zone (plan 3.8.7).
class DemandMapScreen extends StatefulWidget {
  const DemandMapScreen({super.key});

  @override
  State<DemandMapScreen> createState() => _DemandMapScreenState();
}

class _DemandMapScreenState extends State<DemandMapScreen> {
  late final _services = context.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _services.zones.ensureLoaded();
    });
  }

  void _moveTo(DeliveryZone zone) {
    final messenger = ScaffoldMessenger.of(context);
    try {
      _services.availability.moveToZone(zone.id, zone.center);
    } on AppFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text("You're now in ${zone.name}. Offers come from here."),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final zones = _services.zones;
    final availability = _services.availability;

    return AppScaffold(
      title: 'Demand map',
      showDemoBadge: true,
      body: ListenableBuilder(
        listenable: Listenable.merge([zones, availability, _services.trip]),
        builder: (context, _) {
          if (!zones.isReady) {
            final error = zones.error;
            return error == null
                ? const Center(child: CircularProgressIndicator())
                : ErrorState(message: error, onRetry: zones.load);
          }
          final position = availability.position;
          final current = availability.zoneId;
          final hasTrip = _services.trip.hasTrip;
          final busy = zones.zones.where((z) => z.demand.isBusy).toList();

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: DeliveryMap(
                      interactive: false,
                      model: demandMapModel(
                        zones: zones.zones,
                        rider: position,
                        currentZoneId: current,
                        semanticLabel: busy.isEmpty
                            ? 'Map: demand is normal in every zone.'
                            : 'Map: ${busy.map((z) => '${z.demand.label} in ${z.name}').join(', ')}.',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final zone in zones.zones)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _ZoneTile(
                    zone: zone,
                    distanceM: position.distanceMetersTo(zone.center),
                    isCurrent: zone.id == current,
                    onMove: hasTrip ? null : () => _moveTo(zone),
                  ),
                ),
              if (hasTrip)
                const DisabledReason(
                  'You can move to another zone after your current order.',
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ZoneTile extends StatelessWidget {
  const _ZoneTile({
    required this.zone,
    required this.distanceM,
    required this.isCurrent,
    required this.onMove,
  });

  final DeliveryZone zone;
  final int distanceM;
  final bool isCurrent;
  final VoidCallback? onMove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final multiplier = zone.surgeMultiplier > 1
        ? ' · ${zone.surgeMultiplier.toStringAsFixed(1)}×'
        : '';

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
              Icons.circle,
              size: 14,
              color: demandColor(zone.demand),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(zone.name, style: textTheme.titleSmall),
                Text(
                  '${zone.demand.label}$multiplier · '
                  '${isCurrent ? 'You are here' : formatDistance(distanceM)}',
                  style: textTheme.bodySmall,
                ),
                if (!isCurrent)
                  TextButton(
                    onPressed: onMove,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 44),
                    ),
                    child: Text('Move to ${zone.name}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

double demandIntensity(DemandLevel level) => switch (level) {
  DemandLevel.low => 0.1,
  DemandLevel.normal => 0.35,
  DemandLevel.high => 0.7,
  DemandLevel.surge => 1,
};

/// Zones as heat overlays plus the rider, as pure map data.
MapViewModel demandMapModel({
  required List<DeliveryZone> zones,
  required GeoPoint rider,
  required String currentZoneId,
  required String semanticLabel,
}) => MapViewModel(
  focus: rider,
  semanticLabel: semanticLabel,
  zones: [
    for (final zone in zones)
      MapZoneOverlay(
        center: zone.center,
        radiusM: zone.demand.isBusy ? 900 : 700,
        intensity: demandIntensity(zone.demand),
        label: zone.id == currentZoneId ? '${zone.name} (you)' : zone.name,
      ),
  ],
  markers: [
    MapMarker(
      id: 'rider',
      kind: MapMarkerKind.rider,
      position: rider,
      label: 'You',
    ),
  ],
);
