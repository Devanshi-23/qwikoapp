import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../utils/app_colors.dart';

/// Shown while the network is unavailable (in the demo, the Demo Controls
/// toggle). Pass [offline] to force a state.
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key, this.offline});

  final bool? offline;

  @override
  Widget build(BuildContext context) {
    final forced = offline;
    if (forced != null) return forced ? const _Banner() : const SizedBox();

    final device = AppScope.maybeOf(context)?.device;
    if (device == null) return const SizedBox();
    return ListenableBuilder(
      listenable: device,
      builder: (context, _) =>
          device.networkAvailable ? const SizedBox() : const _Banner(),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: AppColors.textDark,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: const Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "You're offline (simulated). Showing saved data.",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
