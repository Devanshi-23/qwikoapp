import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/order.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/media_image.dart';
import '../../widgets/money_text.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/route_preview.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/stop_tile.dart';
import 'order_issue_sheet.dart';

/// Opened by order id so it works from history, notifications and links.
class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  late Future<DeliveryTask> _order;

  @override
  void initState() {
    super.initState();
    _order = context.services.history.orderById(widget.orderId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.services.support.ensureLoaded();
    });
  }

  void _retry() => setState(() {
    _order = context.services.history.orderById(widget.orderId);
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DeliveryTask>(
      future: _order,
      builder: (context, snapshot) {
        final order = snapshot.data;
        return AppScaffold(
          title: order == null ? 'Order' : 'Order ${order.displayId}',
          body: switch (snapshot.connectionState) {
            ConnectionState.done when order != null => _OrderDetailsBody(
              order: order,
            ),
            ConnectionState.done => _buildError(snapshot.error),
            _ => const Padding(
              padding: EdgeInsets.all(20),
              child: SkeletonList(count: 4, itemHeight: 110),
            ),
          },
        );
      },
    );
  }

  Widget _buildError(Object? error) {
    return Center(
      child: ErrorState(
        title: "Couldn't load this order",
        message: failureMessage(error ?? const NotFoundFailure()),
        onRetry: error is NotFoundFailure ? null : _retry,
      ),
    );
  }
}

class _OrderDetailsBody extends StatelessWidget {
  const _OrderDetailsBody({required this.order});

  final DeliveryTask order;

  @override
  Widget build(BuildContext context) {
    final style = orderStatusStyle(order.status);
    final payout = order.payout;
    final support = context.services.support;
    final now = context.services.clock.now();
    final cancelNote = order.timeline
        .where(
          (e) =>
              e.type == OrderEventType.cancelled ||
              e.type == OrderEventType.returningToStore,
        )
        .map((e) => e.note)
        .whereType<String>()
        .firstOrNull;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppCard(
          color: style.background,
          borderColor: style.background,
          margin: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Icon(style.icon, color: style.color, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      style.label,
                      style: TextStyle(
                        color: style.color,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      formatDateTime(order.lastUpdatedAt, now: now),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    if (cancelNote != null)
                      Text(
                        cancelNote,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _section(
          title: 'Route',
          child: Column(
            children: [
              RoutePreview(
                store: order.store.location,
                storeLabel: order.store.name,
                drops: [order.customer.location],
                height: 160,
              ),
              const SizedBox(height: 12),
              StopTile(
                kind: StopKind.pickup,
                title: order.store.name,
                subtitle: order.store.address,
                subtitleMaxLines: 3,
              ),
              const StopConnector(height: 18),
              // Finished orders keep only what a rider needs to recall them.
              StopTile(
                kind: StopKind.drop,
                title: order.status.isFinal
                    ? order.customer.firstName
                    : order.customer.fullName,
                subtitle: order.status.isFinal
                    ? order.customer.locality
                    : order.customer.fullAddress,
                subtitleMaxLines: 3,
              ),
              const SizedBox(height: 10),
              _Row('Distance', formatDistance(order.distanceM)),
            ],
          ),
        ),
        _section(
          title: 'Items (${order.items.length})',
          child: Column(
            children: [
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.circle,
                        size: 6,
                        color: AppColors.textGrey,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.label,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      MoneyText(
                        item.linePaise,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _section(
          title: 'Payment',
          child: Column(
            children: [
              _Row.money('Order value', order.payment.orderValuePaise),
              _Row(
                'Payment mode',
                order.payment.isCod ? 'Cash on delivery' : 'Paid online',
              ),
              if (order.proof case final proof?
                  when proof.cashCollectedPaise > 0)
                _Row.money('Cash collected', proof.cashCollectedPaise),
              if (order.proof case final proof? when proof.changeGivenPaise > 0)
                _Row.money('Change given', proof.changeGivenPaise),
              if (order.proof case final proof?
                  when proof.upiCollectedPaise > 0)
                _Row.money('UPI collected', proof.upiCollectedPaise),
            ],
          ),
        ),
        if (order.proof case final proof?)
          _section(
            title: 'Proof of delivery',
            child: Row(
              children: [
                if (proof.photo case final photo?) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox.square(
                      dimension: 72,
                      child: MediaImage(
                        media: photo,
                        semanticLabel: 'Delivery photo',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Row(
                        'Customer code',
                        proof.otpVerified ? 'Verified' : 'Not needed',
                      ),
                      _Row(
                        'Photo',
                        proof.photo == null ? 'Not taken' : 'Taken',
                      ),
                      _Row('Captured', formatTime(proof.capturedAt)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        _section(
          title: 'Your earnings',
          child: Column(
            children: [
              if (payout.orderPayPaise > 0)
                _Row.money('Delivery fee', payout.orderPayPaise),
              if (payout.surgePaise > 0) _Row.money('Surge', payout.surgePaise),
              if (payout.waitingPaise > 0)
                _Row.money('Waiting pay', payout.waitingPaise),
              if (payout.batchBonusPaise > 0)
                _Row.money('Batch bonus', payout.batchBonusPaise),
              if (payout.compensationPaise > 0)
                _Row.money('Compensation', payout.compensationPaise),
              _Row.money('Customer tip', payout.tipPaise),
              const Divider(height: 20, color: AppColors.border),
              _Row.money('Total', order.earnedPaise, bold: true),
            ],
          ),
        ),
        if (order.timeline.isNotEmpty)
          _section(
            title: 'Timeline',
            child: Column(
              children: [
                for (final event in order.timeline)
                  _Row(_eventLabel(event.type), formatTime(event.at)),
              ],
            ),
          ),
        ListenableBuilder(
          listenable: support,
          builder: (context, _) {
            final tickets = support.tickets
                .where((ticket) => ticket.orderId == order.orderId)
                .toList();
            if (tickets.isEmpty) return const SizedBox.shrink();
            return _section(
              title: 'Support requests',
              child: Column(
                children: [
                  for (final ticket in tickets)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.support_agent_rounded),
                      title: Text(ticket.category),
                      subtitle: Text('${ticket.id} · ${ticket.status.label}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pushNamed(context, AppRoutes.help),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        PrimaryButton(
          label: 'Report an issue with this order',
          icon: Icons.support_agent_rounded,
          variant: ButtonVariant.outlined,
          onPressed: () => _reportIssue(context),
        ),
      ],
    );
  }

  Future<void> _reportIssue(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ticket = await showOrderIssueSheet(context, order);
    if (ticket == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Request ${ticket.id} sent to support'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => navigator.pushNamed(AppRoutes.help),
        ),
      ),
    );
  }

  Widget _section({required String title, required Widget child}) => AppCard(
    title: title,
    margin: const EdgeInsets.only(bottom: 14),
    child: child,
  );

  String _eventLabel(OrderEventType type) => switch (type) {
    OrderEventType.offered => 'Offered',
    OrderEventType.accepted => 'Accepted',
    OrderEventType.arrivedAtStore => 'Arrived at store',
    OrderEventType.pickedUp => 'Picked up',
    OrderEventType.arrivedAtCustomer => 'Arrived at customer',
    OrderEventType.delivered => 'Delivered',
    OrderEventType.cancelled => 'Cancelled',
    OrderEventType.returningToStore => 'Returning to store',
    OrderEventType.returned => 'Returned to store',
    OrderEventType.issueReported => 'Issue reported',
    OrderEventType.callAttempted => 'Call attempted',
    OrderEventType.chatSent => 'Message sent',
    OrderEventType.chatReceived => 'Customer replied',
    OrderEventType.locationShared => 'Customer shared location',
    OrderEventType.proofCaptured => 'Proof captured',
    OrderEventType.paymentCollected => 'Payment collected',
    OrderEventType.tipReceived => 'Tip received',
    OrderEventType.ratingReceived => 'Rated by customer',
  };
}

/// Label on the left, value on the right.
class _Row extends StatelessWidget {
  const _Row(this.label, String this.value) : paise = null, bold = false;

  const _Row.money(this.label, int this.paise, {this.bold = false})
    : value = null;

  final String label;
  final String? value;
  final int? paise;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final paise = this.paise;
    final valueStyle = TextStyle(
      color: bold ? AppColors.primary : AppColors.textDark,
      fontSize: bold ? 16 : 14,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: bold ? AppColors.textDark : AppColors.textSecondary,
                fontSize: 14,
                fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: paise == null
                ? Text(value ?? '', textAlign: TextAlign.end, style: valueStyle)
                : MoneyText(paise, textAlign: TextAlign.end, style: valueStyle),
          ),
        ],
      ),
    );
  }
}
