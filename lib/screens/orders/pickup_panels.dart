import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../controllers/active_trip_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/media_ref.dart';
import '../../models/order.dart';
import '../../models/trip.dart';
import '../../services/image_service.dart';
import '../../utils/app_colors.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/media_image.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/slide_to_confirm.dart';

/// Store name, address, counter and pickup instructions, plus handling
/// notes from the order's tags.
class PickupStoreCard extends StatelessWidget {
  const PickupStoreCard({super.key, required this.trip});

  final DeliveryTrip trip;

  @override
  Widget build(BuildContext context) {
    final store = trip.store;
    final textTheme = Theme.of(context).textTheme;
    final instructions = store.pickupInstructions;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.storefront_rounded, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store.name, style: textTheme.titleMedium),
                    Text(store.address, style: textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (store.counterLabel.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoLine(
              icon: Icons.point_of_sale_rounded,
              text: 'Collect at ${store.counterLabel}',
            ),
          ],
          if (instructions.isNotEmpty)
            InfoLine(icon: Icons.info_outline_rounded, text: instructions),
          for (final tag in trip.tags)
            InfoLine(
              icon: Icons.warning_amber_rounded,
              text: tag.instruction,
              color: AppColors.warning,
            ),
        ],
      ),
    );
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine({
    super.key,
    required this.icon,
    required this.text,
    this.color = AppColors.textSecondary,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// "Will sync when online" while a step taken offline is queued.
class QueuedStepsChip extends StatelessWidget {
  const QueuedStepsChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.warning),
            SizedBox(width: AppSpacing.xs + 2),
            Flexible(
              child: Text(
                'Will sync when online',
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Heading to the store: store details, distance and "I've arrived", which
/// unlocks inside the store geofence.
class HeadingToStorePanel extends StatelessWidget {
  const HeadingToStorePanel({
    super.key,
    required this.trip,
    required this.controller,
    required this.navigation,
    required this.onArrived,
    required this.onCallStore,
    required this.onNavigate,
    required this.onReportIssue,
  });

  final DeliveryTrip trip;
  final ActiveTripController controller;
  final NavigationController navigation;
  final VoidCallback onArrived;
  final VoidCallback onCallStore;
  final VoidCallback onNavigate;
  final VoidCallback onReportIssue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Go to the store for pickup',
          style: textTheme.labelLarge?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        PickupStoreCard(trip: trip),
        const SizedBox(height: AppSpacing.md),
        ListenableBuilder(
          listenable: navigation,
          builder: (context, _) {
            final summary = navigation.summary;
            final distance = controller.distanceToStoreM;
            final near = controller.isNearStore;
            final busy = controller.isBusy;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (summary != null) Text(summary, style: textTheme.titleSmall),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: ContactButton(
                        icon: Icons.call_outlined,
                        label: 'Call store',
                        onTap: onCallStore,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: ContactButton(
                        icon: Icons.navigation_outlined,
                        label: 'Navigate',
                        onTap: onNavigate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: "I've arrived",
                  icon: Icons.storefront_rounded,
                  isLoading: busy,
                  onPressed: near ? onArrived : null,
                ),
                if (!near)
                  DisabledReason(
                    distance == null
                        ? "Turn on location so we can confirm you're at the "
                              'store.'
                        : 'Available within ${DeliveryTrip.pickupGeofenceM} m '
                              'of the store · ${formatDistance(distance)} away',
                    icon: Icons.location_on_outlined,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onReportIssue,
            icon: const Icon(Icons.report_outlined, size: 18),
            label: const Text('Report a store issue'),
          ),
        ),
      ],
    );
  }
}

/// At the store: order ID and pickup code for staff, waiting timer, item
/// checklist, bag and "Slide to confirm pickup".
class AtStorePanel extends StatefulWidget {
  const AtStorePanel({
    super.key,
    required this.trip,
    required this.controller,
    required this.onPickedUp,
    required this.onCallStore,
    required this.onReportIssue,
    required this.onCancelForWait,
  });

  final DeliveryTrip trip;
  final ActiveTripController controller;
  final Future<void> Function() onPickedUp;
  final VoidCallback onCallStore;
  final VoidCallback onReportIssue;
  final VoidCallback onCancelForWait;

  @override
  State<AtStorePanel> createState() => _AtStorePanelState();
}

class _AtStorePanelState extends State<AtStorePanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  ActiveTripController get _controller => widget.controller;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _addBagPhoto() async {
    final choice = await showAppBottomSheet<String>(
      context,
      title: 'Bag photo',
      subtitle: 'Optional. Shows the sealed bag in the order record.',
      builder: (context) => Column(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take or choose a photo'),
            onTap: () => Navigator.pop(context, 'device'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Use sample photo'),
            onTap: () => Navigator.pop(context, 'sample'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    MediaRef? photo;
    if (choice == 'sample') {
      photo = const MediaRef.sample('bag-photo');
    } else {
      final path = await ImageService.pickImage(context);
      if (path != null) photo = MediaRef.file(path);
    }
    if (photo == null || !mounted) return;
    await _run(() => _controller.setBag(sealed: true, photo: photo));
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final now = _controller.now;
    final textTheme = Theme.of(context).textTheme;
    final blocked = trip.pickupBlockedReason(now);
    final busy = _controller.isBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HandoverCard(trip: trip),
        const SizedBox(height: AppSpacing.md),
        _WaitCard(
          trip: trip,
          now: now,
          onCancelForWait: busy ? null : widget.onCancelForWait,
        ),
        const SizedBox(height: AppSpacing.md),
        _Checklist(
          trip: trip,
          onItem: (ref, checked) =>
              _run(() => _controller.setItemChecked(ref, checked: checked)),
          onTag: (tag, checked) =>
              _run(() => _controller.setHandlingChecked(tag, checked: checked)),
          onCheckAll: () => _run(_controller.checkAllItems),
        ),
        const SizedBox(height: AppSpacing.sm),
        CheckboxListTile(
          value: trip.bagSealed,
          onChanged: (value) => _run(
            () => _controller.setBag(
              sealed: value ?? false,
              photo: trip.bagPhoto,
            ),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('Bag sealed (optional)'),
        ),
        Row(
          children: [
            if (trip.bagPhoto != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: MediaImage(
                    media: trip.bagPhoto!,
                    fallback: const Icon(Icons.shopping_bag_outlined),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: TextButton.icon(
                onPressed: _addBagPhoto,
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(
                  trip.bagPhoto == null ? 'Add bag photo' : 'Change bag photo',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: ContactButton(
                icon: Icons.call_outlined,
                label: 'Call store',
                onTap: widget.onCallStore,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ContactButton(
                icon: Icons.report_outlined,
                label: 'Store issue',
                onTap: widget.onReportIssue,
                tooltip: 'Report a store issue',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SlideToConfirm(
          label: 'Slide to confirm pickup',
          enabled: blocked == null && !busy,
          onConfirmed: widget.onPickedUp,
        ),
        if (blocked != null) DisabledReason(blocked),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Customer details are shown in full after pickup.',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// What store staff need to find the order.
class _HandoverCard extends StatelessWidget {
  const _HandoverCard({required this.trip});

  final DeliveryTrip trip;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ids = trip.tasks.map((t) => t.displayId).join(', ');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Show this at ${trip.store.counterLabel}',
            style: textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            ids,
            style: textTheme.headlineSmall?.copyWith(color: AppColors.primary),
          ),
          if (trip.pickupCode.isNotEmpty)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              children: [
                Text(
                  'Pickup code ${trip.pickupCode}',
                  style: textTheme.titleMedium,
                ),
                const SimulatedLabel(text: 'Demo code'),
              ],
            ),
        ],
      ),
    );
  }
}

/// Time at the store, waiting pay and store delays.
class _WaitCard extends StatelessWidget {
  const _WaitCard({
    required this.trip,
    required this.now,
    required this.onCancelForWait,
  });

  final DeliveryTrip trip;
  final DateTime now;
  final VoidCallback? onCancelForWait;

  static String _clock(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final waited = trip.waitedAt(now);
    final paid = trip.isWaitingPaid(now);
    final notReady = !trip.isOrderReady(now);
    final fixing = trip.isStoreFixing(now);
    final freeLeft = DeliveryTrip.freeWait - waited;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer_outlined, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Waiting ${_clock(waited)}',
                  style: textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            paid
                ? 'Waiting pay is now being added (₹1/min) · '
                      '${formatPaise(trip.waitingPaiseAt(now))} so far'
                : 'Waiting pay starts in ${formatMinutes(freeLeft)}.',
            style: textTheme.bodySmall?.copyWith(
              color: paid ? AppColors.primary : AppColors.textSecondary,
              fontWeight: paid ? FontWeight.w700 : null,
            ),
          ),
          if (notReady) ...[
            const SizedBox(height: AppSpacing.sm),
            _StatusLine(
              icon: Icons.hourglass_top_rounded,
              text:
                  'The store is preparing the order · ready in about '
                  '${formatMinutes(trip.orderReadyAt!.difference(now))}',
            ),
          ],
          if (fixing) ...[
            const SizedBox(height: AppSpacing.sm),
            _StatusLine(
              icon: Icons.build_circle_outlined,
              text:
                  'The store is fixing the order · about '
                  '${trip.storeFixingUntil!.difference(now).inSeconds} s',
            ),
          ],
          if (trip.canCancelForWaitAt(now)) ...[
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: 'Cancel and get compensation',
              variant: ButtonVariant.destructive,
              height: 48,
              onPressed: onCancelForWait,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.warning,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Items grouped per order, then handling checks. Removed items stay
/// visible, struck through.
class _Checklist extends StatelessWidget {
  const _Checklist({
    required this.trip,
    required this.onItem,
    required this.onTag,
    required this.onCheckAll,
  });

  final DeliveryTrip trip;
  final void Function(ItemRef ref, bool checked) onItem;
  final void Function(OfferTag tag, bool checked) onTag;
  final VoidCallback onCheckAll;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final total = trip.pickupItems.length + trip.pickupChecks.length;
    final done = total - trip.uncheckedCount;
    final batched = trip.tasks.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Check items · $done of $total',
                style: textTheme.titleSmall,
              ),
            ),
            TextButton(
              onPressed: trip.uncheckedCount == 0 ? null : onCheckAll,
              child: const Text('Mark all as checked'),
            ),
          ],
        ),
        for (final task in trip.tasks) ...[
          if (batched)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Order ${task.displayId}',
                style: textTheme.labelLarge,
              ),
            ),
          for (final (index, item) in task.items.indexed)
            _ItemTile(
              item: item,
              onChanged: item.status == ItemStatus.removed
                  ? null
                  : (checked) =>
                        onItem((orderId: task.orderId, index: index), checked),
            ),
        ],
        for (final tag in trip.pickupChecks)
          CheckboxListTile(
            value: trip.checkedTags.contains(tag),
            onChanged: (value) => onTag(tag, value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            secondary: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.warning,
            ),
            title: Text(tag.pickupCheck!),
          ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onChanged});

  final OrderItem item;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final removed = item.status == ItemStatus.removed;
    final note = switch (item.status) {
      ItemStatus.replaced => 'Replacement · check the new item',
      ItemStatus.removed => 'Removed from the order',
      _ => null,
    };
    return CheckboxListTile(
      value: removed ? false : item.isPicked,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        item.label,
        style: removed
            ? const TextStyle(
                decoration: TextDecoration.lineThrough,
                color: AppColors.textSecondary,
              )
            : null,
      ),
      subtitle: note == null ? null : Text(note),
    );
  }
}

class ContactButton extends StatelessWidget {
  const ContactButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
    final tooltip = this.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
