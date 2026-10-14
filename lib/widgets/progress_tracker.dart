import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// Horizontal step indicator. Steps up to and including [current] are done.
class ProgressTracker extends StatelessWidget {
  const ProgressTracker({
    super.key,
    required this.steps,
    required this.current,
  });

  /// Must not be empty.
  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);

    return Semantics(
      label: 'Step ${current + 1} of ${steps.length}: ${steps[current]}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == steps.length - 1 ? 0 : 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: duration,
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= current
                            ? AppColors.primary
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      steps[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: i <= current
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: i == current
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
