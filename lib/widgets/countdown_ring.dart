import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// Circular timer for offers and OTP lockouts. The parent owns the clock
/// and rebuilds this with the time left, so demos and tests stay
/// deterministic.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.remaining,
    required this.total,
    this.size = 56,
    this.semanticSuffix = 'left',
  });

  final Duration remaining;
  final Duration total;
  final double size;

  /// Spoken after the time, for example "left to accept".
  final String semanticSuffix;

  @override
  Widget build(BuildContext context) {
    final totalMs = total.inMilliseconds;
    final fraction = totalMs <= 0
        ? 0.0
        : (remaining.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final seconds = remaining.isNegative
        ? 0
        : (remaining.inMilliseconds / 1000).ceil();
    final text = seconds >= 60
        ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
        : '$seconds';
    final color = fraction > 0.5
        ? AppColors.primary
        : fraction > 0.2
        ? AppColors.warning
        : AppColors.error;
    final spoken = seconds >= 60
        ? '${seconds ~/ 60} minutes ${seconds % 60} seconds'
        : '$seconds seconds';

    return Semantics(
      label: '$spoken $semanticSuffix',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: fraction,
              strokeWidth: size / 11,
              backgroundColor: AppColors.border,
              color: color,
            ),
            Padding(
              padding: EdgeInsets.all(size / 5),
              child: FittedBox(
                child: Text(
                  text,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
