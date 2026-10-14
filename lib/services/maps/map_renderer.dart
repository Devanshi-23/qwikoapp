import 'package:flutter/widgets.dart';

import 'map_view_model.dart';

/// Draws a [MapViewModel]. Screens only see this seam, so switching
/// `MAP_PROVIDER` swaps the renderer without touching them.
abstract interface class MapRenderer {
  /// [interactive] maps pan, zoom and show recenter controls; previews
  /// don't.
  Widget build(
    BuildContext context,
    MapViewModel model, {
    bool interactive = true,
  });
}
