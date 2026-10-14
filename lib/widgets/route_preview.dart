import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../core/formatters.dart';
import '../models/geo_point.dart';
import '../services/maps/map_view_model.dart';
import '../services/routing/mock_route_planner.dart';
import 'delivery_map.dart';

/// Small static map of a route: optionally the rider, then the store, then
/// one or two drops. Planned offline so it shows instantly.
class RoutePreview extends StatelessWidget {
  const RoutePreview({
    super.key,
    required this.store,
    required this.drops,
    this.rider,
    this.storeLabel = 'Store',
    this.height = 140,
  });

  final GeoPoint? rider;
  final GeoPoint store;
  final List<GeoPoint> drops;
  final String storeLabel;
  final double height;

  static const MockRoutePlanner _planner = MockRoutePlanner();

  @override
  Widget build(BuildContext context) {
    final rider = this.rider;
    final route = _planner.planSync([?rider, store, ...drops]);
    final dropCount = drops.length == 1 ? 'one drop' : '${drops.length} drops';
    final multiDrop = drops.length > 1;
    final model = MapViewModel(
      markers: [
        if (rider != null)
          MapMarker(
            id: 'rider',
            kind: MapMarkerKind.rider,
            position: rider,
            label: 'You',
          ),
        MapMarker(
          id: 'store',
          kind: MapMarkerKind.store,
          position: store,
          label: storeLabel,
        ),
        for (final (i, drop) in drops.indexed)
          MapMarker(
            id: 'drop-$i',
            kind: MapMarkerKind.customer,
            position: drop,
            label: multiDrop ? 'Drop ${i + 1}' : 'Drop',
            badge: multiDrop ? '${i + 1}' : null,
          ),
      ],
      polylines: [
        MapPolyline(points: route.points, style: MapLineStyle.preview),
      ],
      semanticLabel:
          'Route preview: ${rider == null ? '' : 'you, '}the store, then '
          '$dropCount. About ${formatDistance(route.distanceM)} in total.',
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: height,
        child: DeliveryMap(model: model, interactive: false),
      ),
    );
  }
}
