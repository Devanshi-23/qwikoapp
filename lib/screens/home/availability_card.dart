import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/formatters.dart';
import '../../models/availability.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';

/// `14:05` style countdown.
String formatCountdown(Duration d) {
  final minutes = d.inMinutes.toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Offline, online or on break, with the toggle and break controls.
class AvailabilityCard extends StatelessWidget {
  const AvailabilityCard({
    super.key,
    required this.status,
    required this.onlineToday,
    required this.zoneName,
    required this.busy,
    required this.hasTrip,
    required this.onToggle,
    required this.onTakeBreak,
    required this.onEndBreak,
    this.breakRemaining,
  });

  final AvailabilityStatus status;
  final Duration onlineToday;
  final String zoneName;
  final bool busy;
  final bool hasTrip;
  final Duration? breakRemaining;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTakeBreak;
  final VoidCallback onEndBreak;

  @override
  Widget build(BuildContext context) {
    final online = status == AvailabilityStatus.online;
    final onBreak = status == AvailabilityStatus.onBreak;
    final foreground = online ? Colors.white : AppColors.textDark;
    final secondary = online
        ? Colors.white.withValues(alpha: 0.9)
        : AppColors.textSecondary;

    final (title, subtitle) = switch (status) {
      AvailabilityStatus.offline => (
        'You are Offline',
        'Go online to start receiving orders',
      ),
      AvailabilityStatus.online => (
        'You are Online',
        hasTrip ? 'On an order' : 'Looking for orders near you',
      ),
      AvailabilityStatus.onBreak => (
        'You are on a break',
        'Offers paused · ${formatCountdown(breakRemaining ?? Duration.zero)} '
            'left',
      ),
    };

    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: online ? AppColors.brandGradient : null,
        color: online
            ? null
            : onBreak
            ? AppColors.warningLight
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: online
              ? Colors.transparent
              : onBreak
              ? AppColors.warning
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: online
                      ? Colors.white.withValues(alpha: 0.2)
                      : AppColors.background,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  onBreak
                      ? Icons.coffee_rounded
                      : Icons.delivery_dining_rounded,
                  color: online
                      ? Colors.white
                      : onBreak
                      ? AppColors.warning
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              Semantics(
                label: 'Online',
                child: Switch(
                  value: status != AvailabilityStatus.offline,
                  onChanged: busy || hasTrip ? null : onToggle,
                  activeThumbColor: AppColors.primary,
                  activeTrackColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Meta(
                icon: Icons.timer_outlined,
                text: 'Online today ${formatDuration(onlineToday)}',
                color: secondary,
              ),
              _Meta(
                icon: Icons.place_outlined,
                text: zoneName,
                color: secondary,
              ),
            ],
          ),
          if (hasTrip && status != AvailabilityStatus.offline) ...[
            const SizedBox(height: 10),
            _Meta(
              icon: Icons.info_outline,
              text:
                  'Finish or hand over your current order first to go '
                  'offline or take a break.',
              color: secondary,
            ),
          ] else if (online) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onTakeBreak,
                icon: const Icon(Icons.coffee_outlined, size: 18),
                label: const Text('Take a break'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                  minimumSize: const Size(48, 44),
                ),
              ),
            ),
          ] else if (onBreak) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: busy ? null : onEndBreak,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('End break'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  minimumSize: const Size(48, 44),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text, style: TextStyle(color: color, fontSize: 12)),
        ),
      ],
    );
  }
}

/// Replaces the toggle while something stops the rider going online. Each
/// row links to its fix.
class OnlineBlockersCard extends StatelessWidget {
  const OnlineBlockersCard({
    super.key,
    required this.blockers,
    required this.onFix,
  });

  final List<OnlineBlocker> blockers;
  final ValueChanged<OnlineBlocker> onFix;

  static IconData iconFor(OnlineBlockerType type) => switch (type) {
    OnlineBlockerType.accountSuspended => Icons.block_rounded,
    OnlineBlockerType.verificationPending => Icons.hourglass_top_rounded,
    OnlineBlockerType.documentExpired => Icons.event_busy_rounded,
    OnlineBlockerType.cashLimitReached => Icons.payments_outlined,
    OnlineBlockerType.locationPermissionOff ||
    OnlineBlockerType.locationServiceOff => Icons.location_off_outlined,
    OnlineBlockerType.networkOffline => Icons.cloud_off_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final count = blockers.length;

    return AppCard(
      borderColor: AppColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              "You can't go online yet",
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            count == 1
                ? 'Fix this to start receiving orders.'
                : 'Fix these $count things to start receiving orders.',
            style: textTheme.bodySmall,
          ),
          for (final blocker in blockers) ...[
            const Divider(height: AppSpacing.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(iconFor(blocker.type), color: AppColors.warning),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(blocker.message, style: textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => onFix(blocker),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(48, 40),
                          foregroundColor: AppColors.primary,
                        ),
                        child: Text(blocker.fixLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
