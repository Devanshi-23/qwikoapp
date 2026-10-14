import 'package:flutter/foundation.dart';

import '../../models/geo_point.dart';

enum MapMarkerKind { rider, store, customer, zone }

/// A pin on the map. Renderers decide how each [kind] looks.
@immutable
class MapMarker {
  const MapMarker({
    required this.id,
    required this.kind,
    required this.position,
    required this.label,
    this.heading,
    this.badge,
  });

  final String id;
  final MapMarkerKind kind;
  final GeoPoint position;

  /// Shown next to the pin and read by screen readers.
  final String label;

  /// Compass degrees for the rider arrow.
  final double? heading;

  /// Short text inside the pin, such as a stop number.
  final String? badge;
}

enum MapLineStyle {
  /// The leg being driven now.
  route,

  /// Already driven; drawn grey.
  travelled,

  /// Later legs of the trip.
  upcoming,

  /// Straight-line estimate when routing failed.
  fallback,

  /// Offer and order previews.
  preview,
}

@immutable
class MapPolyline {
  const MapPolyline({required this.points, required this.style});

  final List<GeoPoint> points;
  final MapLineStyle style;
}

/// A demand area, coloured by [intensity] from 0 (quiet) to 1 (busy).
@immutable
class MapZoneOverlay {
  const MapZoneOverlay({
    required this.center,
    required this.radiusM,
    required this.intensity,
    required this.label,
  });

  final GeoPoint center;
  final double radiusM;
  final double intensity;
  final String label;
}

/// Everything a map shows. Pure data: renderers know nothing about orders.
@immutable
class MapViewModel {
  const MapViewModel({
    this.markers = const [],
    this.polylines = const [],
    this.zones = const [],
    this.focus,
    this.semanticLabel = 'Map',
  });

  final List<MapMarker> markers;
  final List<MapPolyline> polylines;
  final List<MapZoneOverlay> zones;

  /// Where "Recenter" goes, usually the rider.
  final GeoPoint? focus;

  /// Text summary of the map for screen readers.
  final String semanticLabel;

  bool get isEmpty => markers.isEmpty && polylines.isEmpty && zones.isEmpty;

  /// Every point that "Show full route" should fit.
  List<GeoPoint> get allPoints => [
    for (final m in markers) m.position,
    for (final l in polylines) ...l.points,
    for (final z in zones) z.center,
  ];
}
