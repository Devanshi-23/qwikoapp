import 'package:flutter/widgets.dart';

import '../app/app_scope.dart';
import '../services/maps/map_view_model.dart';
import '../services/maps/mock_map_view.dart';

/// The one map widget screens use. Draws [model] with the configured
/// renderer (the offline demo map unless `MAP_PROVIDER=google`).
class DeliveryMap extends StatelessWidget {
  const DeliveryMap({super.key, required this.model, this.interactive = true});

  final MapViewModel model;

  /// Previews are static; full maps pan, zoom and recenter.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final renderer =
        AppScope.maybeOf(context)?.mapRenderer ?? const MockMapRenderer();
    return renderer.build(context, model, interactive: interactive);
  }
}
