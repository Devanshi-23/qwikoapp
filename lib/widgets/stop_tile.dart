import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../utils/app_colors.dart';

enum StopKind {
  pickup('Pickup', Icons.storefront_rounded, AppColors.primary),
  drop('Drop', Icons.home_rounded, AppColors.error);

  const StopKind(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

/// Pickup or drop row: icon, small label, name and address.
class StopTile extends StatelessWidget {
  const StopTile({
    super.key,
    required this.kind,
    required this.title,
    this.subtitle,
    this.label,
    this.distanceM,
    this.subtitleMaxLines = 1,
    this.trailing,
  });

  final StopKind kind;
  final String title;
  final String? subtitle;

  /// Replaces the default "Pickup" / "Drop" label.
  final String? label;

  /// Appended to the label as "· 1.2 km away".
  final int? distanceM;
  final int subtitleMaxLines;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final distanceM = this.distanceM;
    final caption = [
      label ?? kind.label,
      if (distanceM != null) '${formatDistance(distanceM)} away',
    ].join(' · ');

    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(kind.icon, color: kind.color, size: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caption.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: subtitleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The short vertical line between two [StopTile]s.
class StopConnector extends StatelessWidget {
  const StopConnector({super.key, this.height = 16});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 11),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(width: 2, height: height, color: AppColors.border),
      ),
    );
  }
}
