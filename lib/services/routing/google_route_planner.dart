import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../core/failures.dart';
import '../../models/geo_point.dart';
import '../../models/route.dart';
import 'route_planner.dart';

/// Google Routes API (two-wheeler, traffic aware). Not registered in the
/// demo build; the only file allowed to import `package:http`.
class GoogleRoutePlanner implements RoutePlanner {
  const GoogleRoutePlanner({this.apiKey = AppConfig.googleMapsApiKey});

  static const String _url =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  final String apiKey;

  static Map<String, dynamic> _waypoint(GeoPoint p) => {
    'location': {
      'latLng': {'latitude': p.latitude, 'longitude': p.longitude},
    },
  };

  @override
  Future<PlannedRoute> plan(List<GeoPoint> waypoints) async {
    final body = {
      'origin': _waypoint(waypoints.first),
      'destination': _waypoint(waypoints.last),
      if (waypoints.length > 2)
        'intermediates': waypoints
            .sublist(1, waypoints.length - 1)
            .map(_waypoint)
            .toList(),
      'travelMode': 'TWO_WHEELER',
      'routingPreference': 'TRAFFIC_AWARE',
    };

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_url),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': apiKey,
              'X-Goog-FieldMask':
                  'routes.duration,routes.distanceMeters,'
                  'routes.polyline.encodedPolyline',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));
    } on Exception {
      throw const NetworkUnavailableFailure();
    }
    if (response.statusCode != 200) {
      throw ServerFailure('Routing failed (${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      throw const ServerFailure('No route found.');
    }
    final route = routes.first as Map<String, dynamic>;
    final seconds = (route['duration'] as String? ?? '0s').replaceAll('s', '');
    return PlannedRoute(
      points: decodePolyline(route['polyline']['encodedPolyline'] as String),
      distanceM: (route['distanceMeters'] as num? ?? 0).round(),
      duration: Duration(seconds: double.tryParse(seconds)?.round() ?? 0),
    );
  }

  /// Decodes Google's encoded polyline format.
  static List<GeoPoint> decodePolyline(String encoded) {
    final points = <GeoPoint>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      for (var coordinate = 0; coordinate < 2; coordinate++) {
        var shift = 0;
        var result = 0;
        int byte;
        do {
          byte = encoded.codeUnitAt(index++) - 63;
          result |= (byte & 0x1f) << shift;
          shift += 5;
        } while (byte >= 0x20);
        final delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
        if (coordinate == 0) {
          lat += delta;
        } else {
          lng += delta;
        }
      }
      points.add(GeoPoint(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
