import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../controllers/active_trip_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/order.dart';
import '../../models/trip.dart';
import '../../utils/app_colors.dart';
import '../../widgets/delivery_map.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/progress_tracker.dart';
import '../navigation/route_widgets.dart';
import 'chat_screen.dart';
import 'customer_call_sheet.dart';
import 'delivery_complete_screen.dart';
import 'delivery_panels.dart';
import 'pickup_panels.dart';
import 'proof_of_delivery_screen.dart';
import 'store_issue_sheet.dart';
import 'trip_cancelled_view.dart';

enum DeliveryStep {
  toStore(0),
  atStore(1),
  toCustomer(2),
  atCustomer(3),
  returning(3),

  /// Nothing left but a notice to read.
  done(4);

  const DeliveryStep(this.progress);

  /// Index into [ActiveOrderScreen.progressSteps].
  final int progress;
}

DeliveryStep stepFor(OrderStatus status) => switch (status) {
  OrderStatus.arrivedAtStore => DeliveryStep.atStore,
  OrderStatus.pickedUp ||
  OrderStatus.headingToCustomer => DeliveryStep.toCustomer,
  OrderStatus.arrivedAtCustomer => DeliveryStep.atCustomer,
  OrderStatus.returningToStore => DeliveryStep.returning,
  _ when status.isFinal => DeliveryStep.done,
  _ => DeliveryStep.toStore,
};

/// Runs the active trip step by step: map on top, task panel below. Pops
/// with the total paise earned once the trip is over (delivered, returned
/// or closed after a notice), or with the [TripCancellation] after a
/// cancelled trip is acknowledged. Leaving early keeps the trip active so
/// Home can resume it.
class ActiveOrderScreen extends StatefulWidget {
  const ActiveOrderScreen({super.key});

  static const List<String> progressSteps = [
    'Accepted',
    'At store',
    'Picked up',
    'At customer',
    'Delivered',
  ];

  @override
  State<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends State<ActiveOrderScreen> {
  late final ActiveTripController _controller = context.services.trip;
  late final NavigationController _nav = context.services.navigation;

  /// Portrait panel height as a fraction of the screen; the map sits above
  /// it so its controls stay visible.
  final ValueNotifier<double> _sheetExtent = ValueNotifier(_initialExtent);

  static const double _initialExtent = 0.5;
  static const double _minExtent = 0.25;
  static const double _maxExtent = 0.92;

  @override
  void dispose() {
    _sheetExtent.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _simulateCall(String name) {
    _showMessage('Simulated call to $name · calling is disabled in demo mode');
  }

  void _openNavigation() =>
      Navigator.pushNamed<Object?>(context, AppRoutes.navigation);

  void _openChat() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(controller: _controller),
      ),
    );
  }

  void _callCustomer(DeliveryTask task) => showCustomerCallSheet(
    context,
    name: task.customer.firstName,
    onCall: _controller.callCustomer,
  );

  /// Swaps to the completion screen once nothing is left on the trip.
  void _popIfOver() {
    if (!mounted || _controller.trip != null) return;
    final finished = _controller.tripFinished;
    if (finished.isEmpty) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DeliveryCompleteScreen(tasks: finished),
      ),
    );
  }

  Future<void> _cantFindAddress() async {
    final choice = await showAppBottomSheet<String>(
      context,
      title: "Can't find the address?",
      builder: (context) => Column(
        children: [
          ListTile(
            leading: const Icon(Icons.my_location_rounded),
            title: const Text('Ask the customer to share their location'),
            subtitle: const Text('The route updates when they do'),
            onTap: () => Navigator.pop(context, 'location'),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_rounded),
            title: const Text('Contact support'),
            onTap: () => Navigator.pop(context, 'support'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await _attempt(() async {
      if (choice == 'location') {
        await _controller.requestCustomerLocation();
        if (mounted) _showMessage('Location received. Route updated.');
      } else {
        final ticket = await _controller.contactSupportAboutAddress();
        if (mounted) {
          _showMessage('Support is on it (ticket $ticket). Keep calling.');
        }
      }
    });
  }

  Future<void> _markUndeliverable(
    DeliveryTask task, {
    bool refused = false,
  }) async {
    final reason = await showReasonSheet(
      context,
      title: refused ? 'Customer refused the order' : 'Mark undeliverable',
      subtitle: task.isReturnable
          ? 'You take the order back to the store and are paid for the trip.'
          : "This order can't go back to the store; you dispose of it as "
                'instructed and are paid for the trip.',
      reasons: refused ? refusalReasons : undeliverableReasons,
      confirmLabel: refused ? 'Confirm refusal' : 'Mark undeliverable',
    );
    if (reason == null || !mounted) return;
    await _attempt(() async {
      await _controller.markUndeliverable(reason: reason, refused: refused);
      _popIfOver();
    });
  }

  Future<void> _returnedToStore() => _attempt(() async {
    await _controller.returnedToStore();
    if (_controller.trip == null) return _popIfOver();
    if (mounted) _showMessage('Returned to the store.');
  });

  Future<void> _dismissNotice() => _attempt(() async {
    await _controller.dismissNotice();
    _popIfOver();
  });

  Future<void> _attempt(Future<void> Function() action) async {
    try {
      await action();
    } on AppFailure catch (failure) {
      if (mounted) _showMessage(failure.message);
    }
  }

  Future<void> _pickedUp() => _attempt(() async {
    await _controller.pickedUp();
    final task = _controller.currentTask;
    if (mounted && task != null) {
      _showMessage('Picked up. Head to ${task.customer.fullName}.');
    }
  });

  Future<void> _reportStoreIssue(DeliveryTrip trip) async {
    final request = await showStoreIssueSheet(
      context,
      trip: trip,
      nearStore: _controller.isNearStore,
    );
    if (request == null || !mounted) return;
    await _attempt(() async {
      final result = await _controller.reportStoreIssue(request);
      if (mounted && result.outcome != IssueOutcome.cancelled) {
        _showMessage(result.message);
      }
    });
  }

  Future<void> _cancelForWait() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel and get compensation?',
      message:
          'The order is cancelled and you are paid for the trip to the store '
          'and the time you waited.',
      confirmLabel: 'Cancel order',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _attempt(_controller.cancelAfterLongWait);
  }

  Future<void> _closeCancelled() => _attempt(() async {
    final cancellation = await _controller.closeCancelledTrip();
    if (mounted) await Navigator.of(context).maybePop(cancellation);
  });

  Future<void> _completeDelivery() async {
    final delivered = await Navigator.push<DeliveryTask>(
      context,
      MaterialPageRoute(
        builder: (_) => ProofOfDeliveryScreen(controller: _controller),
      ),
    );
    if (!mounted) return;
    final trip = _controller.trip;
    if (trip == null) return _popIfOver();
    if (delivered == null) return;
    final earned = formatPaise(delivered.earnedPaise);
    _showMessage(
      trip.status == TripStatus.returningToStore
          ? '${delivered.displayId} delivered · $earned. Now return to the '
                'store.'
          : '${delivered.displayId} delivered · $earned. Head to the next '
                'customer.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final trip = _controller.trip;
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Active order')),
            body: const Center(child: Text('No active order right now.')),
          );
        }
        if (trip.cancellation != null) {
          return TripCancelledView(
            trip: trip,
            busy: _controller.isBusy,
            onDone: _closeCancelled,
          );
        }
        final panel = _panelChildren(trip);
        return Scaffold(
          backgroundColor: Colors.white,
          body: OrientationBuilder(
            builder: (context, orientation) =>
                orientation == Orientation.landscape
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildMap()),
                      SizedBox(
                        width: 380,
                        child: _Panel(
                          bottomInset: MediaQuery.paddingOf(context).bottom,
                          children: panel,
                        ),
                      ),
                    ],
                  )
                : _buildPortrait(panel),
          ),
        );
      },
    );
  }

  Widget _buildPortrait(List<Widget> panel) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return Stack(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _sheetExtent,
              builder: (context, extent, map) => Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: height * extent - 20,
                child: map!,
              ),
              child: _buildMap(),
            ),
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                _sheetExtent.value = notification.extent;
                return false;
              },
              child: DraggableScrollableSheet(
                initialChildSize: _initialExtent,
                minChildSize: _minExtent,
                maxChildSize: _maxExtent,
                builder: (context, scrollController) => _Panel(
                  controller: scrollController,
                  showHandle: true,
                  bottomInset: MediaQuery.paddingOf(context).bottom,
                  children: panel,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Rebuilds with every position update; the panel does not.
  Widget _buildMap() {
    return ListenableBuilder(
      listenable: _nav,
      builder: (context, _) => Stack(
        children: [
          Positioned.fill(child: DeliveryMap(model: _nav.mapModel)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRoundButton(
                        Icons.arrow_back_rounded,
                        'Back',
                        () => Navigator.maybePop(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: RouteChip(navigation: _nav)),
                      const SizedBox(width: 6),
                      const Material(
                        color: Colors.white,
                        shape: StadiumBorder(),
                        elevation: 3,
                        child: DemoBadge(),
                      ),
                      const SizedBox(width: 6),
                      Material(
                        color: AppColors.error,
                        shape: const CircleBorder(),
                        elevation: 3,
                        child: IconButton(
                          tooltip: 'Safety and SOS',
                          onPressed: () =>
                              Navigator.pushNamed(context, AppRoutes.safety),
                          icon: const Icon(
                            Icons.sos_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LocationBanners(navigation: _nav),
                  if (_controller.trip?.hasQueuedSteps ?? false)
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: QueuedStepsChip(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, color: AppColors.textDark),
      ),
    );
  }

  List<Widget> _panelChildren(DeliveryTrip trip) {
    final step = stepFor(trip.currentTask.status);
    final task = trip.currentTask;
    final notice = trip.notice;
    return [
      ProgressTracker(
        steps: ActiveOrderScreen.progressSteps,
        current: step.progress,
      ),
      const SizedBox(height: AppSpacing.md),
      if (notice != null) ...[
        TripNoticeCard(
          notice: notice,
          busy: _controller.isBusy,
          onOk: _dismissNotice,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      switch (step) {
        DeliveryStep.toStore => HeadingToStorePanel(
          trip: trip,
          controller: _controller,
          navigation: _nav,
          onArrived: () => _attempt(_controller.arrivedAtStore),
          onCallStore: () => _simulateCall(trip.store.name),
          onNavigate: _openNavigation,
          onReportIssue: () => _reportStoreIssue(trip),
        ),
        DeliveryStep.atStore => AtStorePanel(
          trip: trip,
          controller: _controller,
          onPickedUp: _pickedUp,
          onCallStore: () => _simulateCall(trip.store.name),
          onReportIssue: () => _reportStoreIssue(trip),
          onCancelForWait: _cancelForWait,
        ),
        DeliveryStep.toCustomer => HeadingToCustomerPanel(
          trip: trip,
          controller: _controller,
          navigation: _nav,
          onArrived: () => _attempt(_controller.arrivedAtCustomer),
          onCall: () => _callCustomer(task),
          onChat: _openChat,
          onNavigate: _openNavigation,
          onCantFindAddress: _cantFindAddress,
        ),
        DeliveryStep.atCustomer => AtCustomerPanel(
          trip: trip,
          controller: _controller,
          onComplete: _completeDelivery,
          onCall: () => _callCustomer(task),
          onChat: _openChat,
          onNavigate: _openNavigation,
          onUndeliverable: () => _markUndeliverable(task),
          onRefused: () => _markUndeliverable(task, refused: true),
        ),
        DeliveryStep.returning => ReturningToStorePanel(
          trip: trip,
          controller: _controller,
          navigation: _nav,
          onReturned: _returnedToStore,
          onCallStore: () => _simulateCall(trip.store.name),
          onNavigate: _openNavigation,
        ),
        DeliveryStep.done => const SizedBox.shrink(),
      },
    ];
  }
}

/// White rounded panel holding the task for the current step.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.children,
    required this.bottomInset,
    this.controller,
    this.showHandle = false,
  });

  final List<Widget> children;
  final double bottomInset;
  final ScrollController? controller;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x66000000),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          20,
          showHandle ? 8 : 16,
          20,
          16 + bottomInset,
        ),
        children: [
          if (showHandle)
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}
