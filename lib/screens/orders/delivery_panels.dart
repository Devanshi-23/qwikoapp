import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../controllers/active_trip_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../core/formatters.dart';
import '../../models/order.dart';
import '../../models/trip.dart';
import '../../utils/app_colors.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/money_text.dart';
import '../../widgets/primary_button.dart';
import 'pickup_panels.dart';

extension CustomerPreferenceText on CustomerPreference {
  String get label => switch (this) {
    CustomerPreference.leaveAtDoor => 'Leave at door',
    CustomerPreference.doNotRing => "Don't ring the bell",
    CustomerPreference.contactless => 'Contactless',
  };
}

/// Customer first name, address details, preferences and what to collect.
class CustomerCard extends StatelessWidget {
  const CustomerCard({super.key, required this.trip});

  final DeliveryTrip trip;

  @override
  Widget build(BuildContext context) {
    final task = trip.currentTask;
    final customer = task.customer;
    final textTheme = Theme.of(context).textTheme;
    final batch = trip.tasks.length > 1;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.home_rounded, color: AppColors.error),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.firstName, style: textTheme.titleMedium),
                    Text(customer.fullAddress, style: textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                batch
                    ? 'Drop ${trip.currentTaskIndex + 1} of ${trip.tasks.length}'
                    : task.displayId,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (customer.floor.isNotEmpty)
            InfoLine(icon: Icons.stairs_outlined, text: customer.floor),
          if (customer.landmark.isNotEmpty)
            InfoLine(
              icon: Icons.place_outlined,
              text: 'Near ${customer.landmark}',
            ),
          if (customer.instructions.isNotEmpty)
            InfoLine(
              icon: Icons.sticky_note_2_outlined,
              text: customer.instructions,
            ),
          if (customer.preferences.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final preference in customer.preferences)
                  Chip(
                    label: Text(preference.label),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: AppColors.primaryLight,
                    labelStyle: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          PaymentBanner(payment: task.payment),
          if (batch) _NextDrop(trip: trip),
        ],
      ),
    );
  }
}

class _NextDrop extends StatelessWidget {
  const _NextDrop({required this.trip});

  final DeliveryTrip trip;

  @override
  Widget build(BuildContext context) {
    DeliveryTask? next;
    for (final task in trip.tasks.skip(trip.currentTaskIndex + 1)) {
      if (!task.status.isFinal && task.status != OrderStatus.returningToStore) {
        next = task;
        break;
      }
    }
    final returning = trip.returnTasks.isNotEmpty;
    final text = next != null
        ? 'Next drop: ${next.customer.firstName}, ${next.customer.locality}'
        : returning
        ? 'Next: return to ${trip.store.name}'
        : 'Last drop of this trip';
    return InfoLine(icon: Icons.alt_route_rounded, text: text);
  }
}

/// "Collect ₹X cash" for COD orders, "Prepaid" otherwise.
class PaymentBanner extends StatelessWidget {
  const PaymentBanner({super.key, required this.payment});

  final PaymentInfo payment;

  @override
  Widget build(BuildContext context) {
    final cod = payment.amountToCollectPaise;
    final (Color background, Color foreground) = cod > 0
        ? (AppColors.warningLight, AppColors.warning)
        : (AppColors.primaryLight, AppColors.primary);
    const style = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: cod > 0
          ? MoneyText(
              cod,
              prefix: 'Cash on delivery: collect ',
              style: style.copyWith(color: foreground),
            )
          : Text(
              'Prepaid · nothing to collect',
              style: style.copyWith(color: foreground),
            ),
    );
  }
}

/// Call, Chat and Navigate in one row.
class CustomerContactRow extends StatelessWidget {
  const CustomerContactRow({
    super.key,
    required this.onCall,
    required this.onChat,
    required this.onNavigate,
  });

  final VoidCallback onCall;
  final VoidCallback onChat;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ContactButton(
            icon: Icons.call_outlined,
            label: 'Call',
            tooltip: 'Call the customer',
            onTap: onCall,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: ContactButton(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Chat',
            tooltip: 'Chat with the customer',
            onTap: onChat,
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
    );
  }
}

/// Heading to the customer: details, ETA, contact and "I've arrived" inside
/// the customer geofence.
class HeadingToCustomerPanel extends StatelessWidget {
  const HeadingToCustomerPanel({
    super.key,
    required this.trip,
    required this.controller,
    required this.navigation,
    required this.onArrived,
    required this.onCall,
    required this.onChat,
    required this.onNavigate,
    required this.onCantFindAddress,
  });

  final DeliveryTrip trip;
  final ActiveTripController controller;
  final NavigationController navigation;
  final VoidCallback onArrived;
  final VoidCallback onCall;
  final VoidCallback onChat;
  final VoidCallback onNavigate;
  final VoidCallback onCantFindAddress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Deliver to customer',
          style: textTheme.labelLarge?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        CustomerCard(trip: trip),
        const SizedBox(height: AppSpacing.md),
        ListenableBuilder(
          listenable: navigation,
          builder: (context, _) {
            final summary = navigation.summary;
            final distance = controller.distanceToCustomerM;
            final near = controller.isNearCustomer;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (summary != null) Text(summary, style: textTheme.titleSmall),
                const SizedBox(height: AppSpacing.md),
                CustomerContactRow(
                  onCall: onCall,
                  onChat: onChat,
                  onNavigate: onNavigate,
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: "I've arrived",
                  icon: Icons.home_rounded,
                  isLoading: controller.isBusy,
                  onPressed: near ? onArrived : null,
                ),
                if (!near)
                  DisabledReason(
                    distance == null
                        ? "Turn on location so we can confirm you're at the "
                              'customer.'
                        : 'Available within ${DeliveryTask.customerGeofenceM} '
                              'm of the customer · ${formatDistance(distance)} '
                              'away',
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
            onPressed: onCantFindAddress,
            icon: const Icon(Icons.wrong_location_outlined, size: 18),
            label: const Text("Can't find address"),
          ),
        ),
      ],
    );
  }
}

/// At the customer: hand over, or, when they can't be reached, the calls
/// and door wait that unlock "Mark undeliverable".
class AtCustomerPanel extends StatefulWidget {
  const AtCustomerPanel({
    super.key,
    required this.trip,
    required this.controller,
    required this.onComplete,
    required this.onCall,
    required this.onChat,
    required this.onNavigate,
    required this.onUndeliverable,
    required this.onRefused,
  });

  final DeliveryTrip trip;
  final ActiveTripController controller;
  final VoidCallback onComplete;
  final VoidCallback onCall;
  final VoidCallback onChat;
  final VoidCallback onNavigate;
  final VoidCallback onUndeliverable;
  final VoidCallback onRefused;

  @override
  State<AtCustomerPanel> createState() => _AtCustomerPanelState();
}

class _AtCustomerPanelState extends State<AtCustomerPanel> {
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

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final task = trip.currentTask;
    final now = widget.controller.now;
    final busy = widget.controller.isBusy;
    final textTheme = Theme.of(context).textTheme;
    final blocked = task.undeliverableBlockedReason(now);
    final waited = task.waitedAtDoor(now);
    final calls = task.callAttempts;
    const required = DeliveryTask.requiredCallAttempts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hand over the order',
          style: textTheme.labelLarge?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        CustomerCard(trip: trip),
        const SizedBox(height: AppSpacing.md),
        CustomerContactRow(
          onCall: widget.onCall,
          onChat: widget.onChat,
          onNavigate: widget.onNavigate,
        ),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          label: 'Complete Delivery',
          icon: Icons.check_circle_outline_rounded,
          isLoading: busy,
          onPressed: widget.onComplete,
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Customer not reachable?', style: textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.xs,
                children: [
                  _Requirement(
                    icon: Icons.call_outlined,
                    text: 'Calls: ${calls.clamp(0, required)} of $required',
                    met: calls >= required,
                  ),
                  _Requirement(
                    icon: Icons.timer_outlined,
                    text:
                        'Waited ${formatClock(waited)} of '
                        '${formatClock(DeliveryTask.doorWait)}',
                    met: waited >= DeliveryTask.doorWait,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                label: 'Mark undeliverable',
                icon: Icons.block_rounded,
                variant: ButtonVariant.outlined,
                onPressed: blocked == null && !busy
                    ? widget.onUndeliverable
                    : null,
              ),
              if (blocked != null)
                DisabledReason(blocked)
              else
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    task.isReturnable
                        ? "You've called and waited. You can mark the order "
                              'undeliverable and take it back to the store.'
                        : "You've called and waited. You can mark the order "
                              'undeliverable; dispose of it as instructed.',
                    style: textTheme.bodySmall,
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: busy ? null : widget.onRefused,
                  child: const Text('Customer refused the order'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Requirement extends StatelessWidget {
  const _Requirement({
    required this.icon,
    required this.text,
    required this.met,
  });

  final IconData icon;
  final String text;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final color = met ? AppColors.primary : AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(met ? Icons.check_circle_rounded : icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Taking undelivered orders back: why, ETA and "Returned to store" inside
/// the store geofence.
class ReturningToStorePanel extends StatelessWidget {
  const ReturningToStorePanel({
    super.key,
    required this.trip,
    required this.controller,
    required this.navigation,
    required this.onReturned,
    required this.onCallStore,
    required this.onNavigate,
  });

  final DeliveryTrip trip;
  final ActiveTripController controller;
  final NavigationController navigation;
  final VoidCallback onReturned;
  final VoidCallback onCallStore;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final returning = trip.returnTasks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Return to store',
          style: textTheme.labelLarge?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final task in returning)
          InfoLine(
            icon: Icons.assignment_return_outlined,
            text:
                '${task.displayId}: ${task.timeline.last.note ?? 'Not '
                        'delivered.'}',
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
                  label: 'Returned to store',
                  icon: Icons.assignment_return_rounded,
                  isLoading: controller.isBusy,
                  onPressed: near ? onReturned : null,
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
      ],
    );
  }
}

const List<String> undeliverableReasons = [
  "Customer isn't answering calls",
  "Customer isn't at the address",
  "Can't get into the building",
];

const List<String> refusalReasons = [
  "Customer doesn't want the order any more",
  'Items damaged or spilled',
  'Wrong or missing items',
];

/// Pick a reason, then confirm. Returns the reason, or null if dismissed.
Future<String?> showReasonSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<String> reasons,
  required String confirmLabel,
}) => showAppBottomSheet<String>(
  context,
  title: title,
  subtitle: subtitle,
  builder: (_) => _ReasonPicker(reasons: reasons, confirmLabel: confirmLabel),
);

class _ReasonPicker extends StatefulWidget {
  const _ReasonPicker({required this.reasons, required this.confirmLabel});

  final List<String> reasons;
  final String confirmLabel;

  @override
  State<_ReasonPicker> createState() => _ReasonPickerState();
}

class _ReasonPickerState extends State<_ReasonPicker> {
  String? _reason;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<String>(
          groupValue: _reason,
          onChanged: (value) => setState(() => _reason = value),
          child: Column(
            children: [
              for (final reason in widget.reasons)
                RadioListTile<String>(
                  value: reason,
                  title: Text(reason),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          label: widget.confirmLabel,
          variant: ButtonVariant.destructive,
          onPressed: _reason == null
              ? null
              : () => Navigator.pop(context, _reason),
        ),
        if (_reason == null) const DisabledReason('Choose a reason first.'),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

/// What changed on the trip (a cancellation, a return) and what to do now.
class TripNoticeCard extends StatelessWidget {
  const TripNoticeCard({
    super.key,
    required this.notice,
    required this.onOk,
    this.busy = false,
  });

  final TripNotice notice;
  final VoidCallback onOk;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.info_rounded, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(notice.title, style: textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(notice.message, style: textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(label: 'OK', isLoading: busy, onPressed: onOk),
          ],
        ),
      ),
    );
  }
}
