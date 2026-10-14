import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import 'map_renderer.dart';
import 'map_view_model.dart';
import 'mock_city.dart';

/// The default renderer: a painted, seeded city. No assets, no network.
class MockMapRenderer implements MapRenderer {
  const MockMapRenderer({this.city = const MockCity()});

  final MockCity city;

  @override
  Widget build(
    BuildContext context,
    MapViewModel model, {
    bool interactive = true,
  }) => MockMapView(model: model, city: city, interactive: interactive);
}

/// Pan, pinch and double-tap zoom over a [CustomPainter] city. North stays
/// up. Markers and lines keep their on-screen size at every zoom.
class MockMapView extends StatefulWidget {
  const MockMapView({
    super.key,
    required this.model,
    this.city = const MockCity(),
    this.interactive = true,
  });

  static const String watermark = 'Demo map · not real navigation';

  final MapViewModel model;
  final MockCity city;
  final bool interactive;

  @override
  State<MockMapView> createState() => _MockMapViewState();
}

class _MockMapViewState extends State<MockMapView> {
  final TransformationController _user = TransformationController();
  Offset? _doubleTapAt;
  Size _size = Size.zero;
  _Fit? _fit;

  @override
  void dispose() {
    _user.dispose();
    super.dispose();
  }

  void _zoomAt(Offset point) {
    final scale = _user.value.getMaxScaleOnAxis();
    if (scale >= 4) {
      _user.value = Matrix4.identity();
      return;
    }
    _user.value =
        (Matrix4.identity()
          ..translateByDouble(point.dx, point.dy, 0, 1)
          ..scaleByDouble(2, 2, 1, 1)
          ..translateByDouble(-point.dx, -point.dy, 0, 1)) *
        _user.value;
  }

  void _recenter() {
    final focus = widget.model.focus;
    final fit = _fit;
    if (focus == null || fit == null) {
      _user.value = Matrix4.identity();
      return;
    }
    final scale = math.max(_user.value.getMaxScaleOnAxis(), 2.0);
    final at = fit.toScreen(widget.city.toWorld(focus));
    final target = _size.center(Offset.zero) - at * scale;
    _user.value = Matrix4.identity()
      ..translateByDouble(target.dx, target.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _showAll() => _user.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    final palette = _Palette.of(Theme.of(context));
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        final fit = _fit = _Fit.of(
          widget.model,
          widget.city,
          _size,
          padding: widget.interactive ? 56 : 28,
        );
        final painting = RepaintBoundary(
          child: CustomPaint(
            size: _size,
            painter: _MapPainter(
              model: widget.model,
              city: widget.city,
              fit: fit,
              user: _user,
              palette: palette,
              textScaler: MediaQuery.textScalerOf(context)
                  .clamp(maxScaleFactor: 1.3),
            ),
          ),
        );

        return Semantics(
          container: true,
          label: widget.model.semanticLabel,
          child: Stack(
            children: [
              Positioned.fill(child: ExcludeSemantics(child: painting)),
              if (widget.interactive)
                Positioned.fill(
                  child: GestureDetector(
                    onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
                    onDoubleTap: () =>
                        _zoomAt(_doubleTapAt ?? _size.center(Offset.zero)),
                    child: InteractiveViewer(
                      transformationController: _user,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      minScale: 0.5,
                      maxScale: 8,
                      child: const ColoredBox(
                        color: Colors.transparent,
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              if (widget.interactive)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Recenter',
                        onPressed: _recenter,
                        icon: const Icon(Icons.my_location),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Show full route',
                        onPressed: _showAll,
                        icon: const Icon(Icons.zoom_out_map),
                      ),
                    ],
                  ),
                ),
              Positioned(
                left: 8,
                bottom: 8,
                right: widget.interactive ? 112 : 8,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: _Watermark(
                    text: widget.interactive
                        ? MockMapView.watermark
                        : 'Demo map',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Watermark extends StatelessWidget {
  const _Watermark({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Fits the model's bounds into the view: world metres → screen pixels
/// before the user's pan and zoom.
class _Fit {
  const _Fit(this.center, this.scale, this.size);

  factory _Fit.of(
    MapViewModel model,
    MockCity city,
    Size size, {
    required double padding,
  }) {
    final points = [
      for (final p in model.allPoints) city.toWorld(p),
      for (final z in model.zones) ...[
        city.toWorld(z.center) + Offset(z.radiusM, z.radiusM),
        city.toWorld(z.center) - Offset(z.radiusM, z.radiusM),
      ],
    ];
    if (points.isEmpty) points.add(city.toWorld(city.anchor));
    var minX = points.first.dx, maxX = minX;
    var minY = points.first.dy, maxY = minY;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    const minSpan = 500.0;
    final spanX = math.max(maxX - minX, minSpan);
    final spanY = math.max(maxY - minY, minSpan);
    final pad = math.min(padding, size.shortestSide / 4);
    final scale = math.max(
      0.001,
      math.min((size.width - 2 * pad) / spanX, (size.height - 2 * pad) / spanY),
    );
    return _Fit(Offset((minX + maxX) / 2, (minY + maxY) / 2), scale, size);
  }

  final Offset center;

  /// Pixels per metre at zoom 1.
  final double scale;
  final Size size;

  Offset toScreen(Offset world) =>
      (world - center) * scale + size.center(Offset.zero);

  Offset toWorld(Offset screen) =>
      (screen - size.center(Offset.zero)) / scale + center;

  @override
  bool operator ==(Object other) =>
      other is _Fit &&
      other.center == center &&
      other.scale == scale &&
      other.size == size;

  @override
  int get hashCode => Object.hash(center, scale, size);
}

class _Palette {
  const _Palette({
    required this.land,
    required this.block,
    required this.park,
    required this.water,
    required this.road,
    required this.majorRoad,
    required this.roadEdge,
    required this.label,
    required this.route,
    required this.travelled,
    required this.fallback,
    required this.store,
    required this.customer,
    required this.rider,
    required this.halo,
  });

  factory _Palette.of(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    return dark
        ? _Palette(
            land: const Color(0xFF1E2126),
            block: const Color(0xFF262A30),
            park: const Color(0xFF1F3527),
            water: const Color(0xFF1B3446),
            road: const Color(0xFF3A3F47),
            majorRoad: const Color(0xFF5A5240),
            roadEdge: const Color(0xFF15171A),
            label: const Color(0xFFE6E8EC),
            route: scheme.primary,
            travelled: const Color(0xFF7D838C),
            fallback: scheme.tertiary,
            store: const Color(0xFFE08A1E),
            customer: const Color(0xFFE5534B),
            rider: scheme.primary,
            halo: Colors.black,
          )
        : _Palette(
            land: const Color(0xFFEDEAE3),
            block: const Color(0xFFF5F3EE),
            park: const Color(0xFFCFE6C9),
            water: const Color(0xFFAFD3EC),
            road: Colors.white,
            majorRoad: const Color(0xFFFCE9AE),
            roadEdge: const Color(0xFFD9D4C8),
            label: const Color(0xFF3C4350),
            route: scheme.primary,
            travelled: const Color(0xFF9AA1AB),
            fallback: const Color(0xFF6B4FBB),
            store: const Color(0xFFC46A00),
            customer: const Color(0xFFC62828),
            rider: scheme.primary,
            halo: Colors.white,
          );
  }

  final Color land;
  final Color block;
  final Color park;
  final Color water;
  final Color road;
  final Color majorRoad;
  final Color roadEdge;
  final Color label;
  final Color route;
  final Color travelled;
  final Color fallback;
  final Color store;
  final Color customer;
  final Color rider;
  final Color halo;

  @override
  bool operator ==(Object other) =>
      other is _Palette && other.land == land && other.route == route;

  @override
  int get hashCode => Object.hash(land, route);
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.model,
    required this.city,
    required this.fit,
    required this.user,
    required this.palette,
    required this.textScaler,
  }) : super(repaint: user);

  final MapViewModel model;
  final MockCity city;
  final _Fit fit;
  final TransformationController user;
  final _Palette palette;
  final TextScaler textScaler;

  late Matrix4 _matrix;
  late double _zoom;

  Offset _screen(GeoPoint p) => _project(city.toWorld(p));

  Offset _project(Offset world) =>
      MatrixUtils.transformPoint(_matrix, fit.toScreen(world));

  double get _pxPerM => fit.scale * _zoom;

  @override
  void paint(Canvas canvas, Size size) {
    _matrix = user.value;
    _zoom = _matrix.getMaxScaleOnAxis();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.land);

    final inverse = Matrix4.tryInvert(_matrix) ?? Matrix4.identity();
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => fit.toWorld(MatrixUtils.transformPoint(inverse, c)));
    final visible = Rect.fromPoints(
      Offset(
        corners.map((c) => c.dx).reduce(math.min),
        corners.map((c) => c.dy).reduce(math.min),
      ),
      Offset(
        corners.map((c) => c.dx).reduce(math.max),
        corners.map((c) => c.dy).reduce(math.max),
      ),
    ).inflate(MockCity.blockM);

    _paintBlocks(canvas, visible);
    _paintRiver(canvas, visible);
    _paintRoads(canvas, visible);
    _paintZones(canvas);
    for (final style in MapLineStyle.values) {
      for (final line in model.polylines.where((l) => l.style == style)) {
        _paintLine(canvas, line);
      }
    }
    final ordered = [...model.markers]
      ..sort((a, b) => _markerOrder(a.kind).compareTo(_markerOrder(b.kind)));
    for (final marker in ordered) {
      _paintMarker(canvas, marker);
    }
  }

  static int _markerOrder(MapMarkerKind kind) => switch (kind) {
    MapMarkerKind.zone => 0,
    MapMarkerKind.store => 1,
    MapMarkerKind.customer => 2,
    MapMarkerKind.rider => 3,
  };

  (int, int) _range(double from, double to) =>
      ((from / MockCity.blockM).floor(), (to / MockCity.blockM).ceil());

  void _paintBlocks(Canvas canvas, Rect visible) {
    final blockPx = MockCity.blockM * _pxPerM;
    if (blockPx < 6) return;
    final (c0, c1) = _range(visible.left, visible.right);
    final (r0, r1) = _range(visible.top, visible.bottom);
    if ((c1 - c0) * (r1 - r0) > 4000) return;
    final blockPaint = Paint()..color = palette.block;
    final parkPaint = Paint()..color = palette.park;
    final inset = 8 * _pxPerM;
    for (var c = c0; c < c1; c++) {
      for (var r = r0; r < r1; r++) {
        final topLeft = _project(
          Offset(c * MockCity.blockM, r * MockCity.blockM),
        );
        final bottomRight = _project(
          Offset((c + 1) * MockCity.blockM, (r + 1) * MockCity.blockM),
        );
        final rect = Rect.fromPoints(topLeft, bottomRight).deflate(inset);
        if (rect.isEmpty) continue;
        canvas.drawRect(rect, city.isPark(c, r) ? parkPaint : blockPaint);
      }
    }
  }

  void _paintRiver(Canvas canvas, Rect visible) {
    final path = Path();
    const step = 80.0;
    var first = true;
    for (var x = visible.left - step; x <= visible.right + step; x += step) {
      final p = _project(Offset(x, city.riverY(x)));
      if (first) {
        path.moveTo(p.dx, p.dy);
        first = false;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.water
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(4, MockCity.riverWidthM * _pxPerM),
    );
  }

  void _paintRoads(Canvas canvas, Rect visible) {
    final blockPx = MockCity.blockM * _pxPerM;
    final showMinor = blockPx >= 14;
    final (c0, c1) = _range(visible.left, visible.right);
    final (r0, r1) = _range(visible.top, visible.bottom);
    if (c1 - c0 > 400 || r1 - r0 > 400) return;

    final minorWidth = math.max(2.0, 14 * _pxPerM);
    final majorWidth = math.max(3.5, 24 * _pxPerM);
    for (final major in [false, true]) {
      if (!major && !showMinor) continue;
      final width = major ? majorWidth : minorWidth;
      final edge = Paint()
        ..color = palette.roadEdge
        ..strokeWidth = width + 2;
      final fill = Paint()
        ..color = major ? palette.majorRoad : palette.road
        ..strokeWidth = width;
      for (final paint in [edge, fill]) {
        for (var c = c0; c <= c1; c++) {
          if (MockCity.isMajor(c) != major) continue;
          final x = c * MockCity.blockM;
          canvas.drawLine(
            _project(Offset(x, visible.top)),
            _project(Offset(x, visible.bottom)),
            paint,
          );
        }
        for (var r = r0; r <= r1; r++) {
          if (MockCity.isMajor(r) != major) continue;
          final y = r * MockCity.blockM;
          canvas.drawLine(
            _project(Offset(visible.left, y)),
            _project(Offset(visible.right, y)),
            paint,
          );
        }
      }
    }

    if (blockPx < 70) return;
    final screenCenter = fit.size.center(Offset.zero);
    for (var r = r0; r <= r1; r++) {
      if (!MockCity.isMajor(r)) continue;
      final y = _project(Offset(0, r * MockCity.blockM)).dy;
      _label(
        canvas,
        city.streetName(RoadAxis.horizontal, r),
        Offset(screenCenter.dx, y),
        background: false,
        size: 10,
      );
    }
  }

  static Color _heat(double intensity) {
    final t = intensity.clamp(0.0, 1.0);
    return t < 0.5
        ? Color.lerp(const Color(0xFF2E9D57), const Color(0xFFE0A100), t * 2)!
        : Color.lerp(
            const Color(0xFFE0A100),
            const Color(0xFFD32F2F),
            (t - 0.5) * 2,
          )!;
  }

  void _paintZones(Canvas canvas) {
    for (final zone in model.zones) {
      final center = _screen(zone.center);
      final radius = math.max(18.0, zone.radiusM * _pxPerM);
      final color = _heat(zone.intensity);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.55),
              color.withValues(alpha: 0.12),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.7),
      );
      _label(canvas, zone.label, center + const Offset(0, 14));
    }
  }

  void _paintLine(Canvas canvas, MapPolyline line) {
    if (line.points.length < 2) return;
    final points = line.points.map(_screen).toList();
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final (color, width, dashed) = switch (line.style) {
      MapLineStyle.route => (palette.route, 6.0, false),
      MapLineStyle.travelled => (palette.travelled, 5.0, false),
      MapLineStyle.upcoming => (
        palette.route.withValues(alpha: 0.5),
        4.0,
        true,
      ),
      MapLineStyle.fallback => (palette.fallback, 4.0, true),
      MapLineStyle.preview => (palette.route, 4.0, false),
    };
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (!dashed) {
      canvas.drawPath(path, stroke(palette.halo, width + 3));
      canvas.drawPath(path, stroke(color, width));
      return;
    }
    final paint = stroke(color, width);
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 16) {
        canvas.drawPath(metric.extractPath(d, d + 9), paint);
      }
    }
  }

  void _paintMarker(Canvas canvas, MapMarker marker) {
    final at = _screen(marker.position);
    switch (marker.kind) {
      case MapMarkerKind.rider:
        canvas.drawCircle(
          at,
          20,
          Paint()..color = palette.rider.withValues(alpha: 0.18),
        );
        canvas.drawCircle(at, 11, Paint()..color = palette.halo);
        canvas.drawCircle(at, 8.5, Paint()..color = palette.rider);
        final heading = marker.heading;
        if (heading != null) {
          canvas.save();
          canvas.translate(at.dx, at.dy);
          canvas.rotate(heading * math.pi / 180);
          final arrow = Path()
            ..moveTo(0, -5.5)
            ..lineTo(4.5, 4)
            ..lineTo(0, 1.8)
            ..lineTo(-4.5, 4)
            ..close();
          canvas.drawPath(arrow, Paint()..color = palette.halo);
          canvas.restore();
        }
        _label(canvas, marker.label, at + const Offset(0, 18));
      case MapMarkerKind.store:
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: at, width: 28, height: 28),
          const Radius.circular(7),
        );
        canvas.drawRRect(rect.inflate(2), Paint()..color = palette.halo);
        canvas.drawRRect(rect, Paint()..color = palette.store);
        _glyph(canvas, marker.badge, Icons.storefront, at);
        _label(canvas, marker.label, at + const Offset(0, 22));
      case MapMarkerKind.customer:
        final tip = at;
        final head = tip - const Offset(0, 22);
        final pin = Path()
          ..moveTo(tip.dx, tip.dy)
          ..quadraticBezierTo(head.dx - 14, head.dy + 6, head.dx - 13, head.dy)
          ..arcToPoint(
            Offset(head.dx + 13, head.dy),
            radius: const Radius.circular(13),
          )
          ..quadraticBezierTo(head.dx + 14, head.dy + 6, tip.dx, tip.dy)
          ..close();
        canvas.drawPath(
          pin,
          Paint()
            ..color = palette.halo
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
        canvas.drawPath(pin, Paint()..color = palette.customer);
        _glyph(canvas, marker.badge, Icons.home, head);
        _label(canvas, marker.label, tip + const Offset(0, 6));
      case MapMarkerKind.zone:
        canvas.drawCircle(at, 4, Paint()..color = palette.label);
    }
  }

  void _glyph(Canvas canvas, String? badge, IconData icon, Offset center) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: badge != null
          ? TextSpan(
              text: badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            )
          : TextSpan(
              text: String.fromCharCode(icon.codePoint),
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontFamily: icon.fontFamily,
                package: icon.fontPackage,
              ),
            ),
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  void _label(
    Canvas canvas,
    String text,
    Offset topCenter, {
    bool background = true,
    double size = 11,
  }) {
    if (text.isEmpty) return;
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      textScaler: textScaler,
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: palette.label,
          fontSize: size,
          fontWeight: FontWeight.w700,
        ),
      ),
    )..layout(maxWidth: 140);
    final origin = topCenter - Offset(painter.width / 2, 0);
    if (background) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (origin & painter.size).inflate(3),
          const Radius.circular(4),
        ),
        Paint()..color = palette.halo.withValues(alpha: 0.85),
      );
    }
    painter.paint(canvas, origin);
    painter.dispose();
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.model != model ||
      old.fit != fit ||
      old.palette != palette ||
      old.textScaler != textScaler;
}
