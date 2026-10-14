import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/geo_point.dart';
import 'map_renderer.dart';
import 'map_view_model.dart';

/// Google Maps behind the same seam. Used only when `MAP_PROVIDER=google`
/// and a key is configured.
class GoogleMapRenderer implements MapRenderer {
  const GoogleMapRenderer();

  @override
  Widget build(
    BuildContext context,
    MapViewModel model, {
    bool interactive = true,
  }) => GoogleMapView(model: model, interactive: interactive);
}

class GoogleMapView extends StatefulWidget {
  const GoogleMapView({
    super.key,
    required this.model,
    this.interactive = true,
  });

  final MapViewModel model;
  final bool interactive;

  @override
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<GoogleMapView> {
  GoogleMapController? _controller;

  static LatLng _latLng(GeoPoint p) => LatLng(p.latitude, p.longitude);

  LatLngBounds? get _bounds {
    final points = widget.model.allPoints;
    if (points.isEmpty) return null;
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final p in points) {
      south = math.min(south, p.latitude);
      north = math.max(north, p.latitude);
      west = math.min(west, p.longitude);
      east = math.max(east, p.longitude);
    }
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  void _fit() {
    final bounds = _bounds;
    if (bounds != null) {
      _controller?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 56));
    }
  }

  static double _hue(MapMarkerKind kind) => switch (kind) {
    MapMarkerKind.rider => BitmapDescriptor.hueGreen,
    MapMarkerKind.store => BitmapDescriptor.hueOrange,
    MapMarkerKind.customer => BitmapDescriptor.hueRed,
    MapMarkerKind.zone => BitmapDescriptor.hueViolet,
  };

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final scheme = Theme.of(context).colorScheme;
    final start =
        model.focus ??
        (model.allPoints.isEmpty
            ? const GeoPoint(28.6, 77.2)
            : model.allPoints.first);

    return Semantics(
      container: true,
      label: model.semanticLabel,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: _latLng(start), zoom: 14),
        onMapCreated: (controller) {
          _controller = controller;
          _fit();
        },
        zoomGesturesEnabled: widget.interactive,
        scrollGesturesEnabled: widget.interactive,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        zoomControlsEnabled: widget.interactive,
        myLocationButtonEnabled: false,
        mapToolbarEnabled: false,
        markers: {
          for (final m in model.markers)
            Marker(
              markerId: MarkerId(m.id),
              position: _latLng(m.position),
              rotation: m.heading ?? 0,
              infoWindow: InfoWindow(title: m.label),
              icon: BitmapDescriptor.defaultMarkerWithHue(_hue(m.kind)),
            ),
        },
        polylines: {
          for (final (i, line) in model.polylines.indexed)
            Polyline(
              polylineId: PolylineId('line-$i'),
              points: line.points.map(_latLng).toList(),
              width: line.style == MapLineStyle.route ? 6 : 4,
              color: switch (line.style) {
                MapLineStyle.travelled => Colors.grey,
                MapLineStyle.fallback => scheme.tertiary,
                MapLineStyle.upcoming => scheme.primary.withValues(alpha: 0.5),
                _ => scheme.primary,
              },
              patterns:
                  line.style == MapLineStyle.fallback ||
                      line.style == MapLineStyle.upcoming
                  ? [PatternItem.dash(20), PatternItem.gap(10)]
                  : const [],
            ),
        },
        circles: {
          for (final (i, zone) in model.zones.indexed)
            Circle(
              circleId: CircleId('zone-$i'),
              center: _latLng(zone.center),
              radius: zone.radiusM,
              strokeWidth: 1,
              strokeColor: Color.lerp(
                Colors.green,
                Colors.red,
                zone.intensity,
              )!,
              fillColor: Color.lerp(
                Colors.green,
                Colors.red,
                zone.intensity,
              )!.withValues(alpha: 0.3),
            ),
        },
      ),
    );
  }
}
