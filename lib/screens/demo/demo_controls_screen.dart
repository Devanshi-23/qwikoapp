import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../controllers/demo_controller.dart';
import '../../controllers/demo_scenarios.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../data/repositories/demo_controls.dart';
import '../../models/order.dart';
import '../../models/trip.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/state_views.dart';

/// Demo-only tools: account state, simulated network and data reset.
class DemoControlsScreen extends StatelessWidget {
  const DemoControlsScreen({super.key});

  /// After demo data changes, a signed-in partner goes back through the
  /// account-state gate; otherwise we return to the previous screen.
  static Future<void> _afterDataChange(
    BuildContext context,
    String message,
  ) async {
    final services = context.services;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(message)));
    if (!services.session.isSignedIn) {
      navigator.pop();
      return;
    }
    try {
      final partner = await services.session.refreshPartner();
      AppRoutes.goToAccountHome(navigator, partner);
    } on AppFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _useAccount(BuildContext context, DemoAccount account) async {
    final demo = context.services.demo!;
    if (account == demo.account) return;
    if (context.services.session.isSignedIn) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Switch to "${account.label}"?',
        message:
            'Demo data is rebuilt for this account state. Any active order '
            'ends.',
        confirmLabel: 'Switch account',
      );
      if (!confirmed || !context.mounted) return;
    }
    demo.useAccount(account);
    await _afterDataChange(context, 'Demo account: ${account.label}');
  }

  void _apply(BuildContext context, VoidCallback change, String message) {
    change();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _sendOffer(BuildContext context, OfferRequest request) {
    final sent = context.services.demo!.sendOffer(request);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Offer sent'
                : "Go online first. Offers arrive only when you're online, "
                      'not on a break and not on a trip.',
          ),
        ),
      );
  }

  Future<void> _runScenario(BuildContext context, DemoScenario scenario) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Run scenario ${scenario.number}?',
      message:
          'Demo data is reset and set up for "${scenario.title}". Any '
          'active order ends. The steps stay listed here.',
      confirmLabel: 'Run scenario',
    );
    if (!confirmed || !context.mounted) return;
    context.services.demo!.runScenario(scenario);
    await _afterDataChange(
      context,
      'Scenario ${scenario.number} ready: ${scenario.steps.first}',
    );
  }

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset demo data?',
      message:
          'History, earnings and notifications are rebuilt from the seed. Any '
          'active order ends.',
      confirmLabel: 'Reset data',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    context.services.demo!.resetData();
    await _afterDataChange(context, 'Demo data reset');
  }

  @override
  Widget build(BuildContext context) {
    final demo = context.services.demo;
    if (demo == null) {
      return const AppScaffold(
        title: 'Demo controls',
        body: EmptyState(
          icon: Icons.tune_rounded,
          title: 'Not available',
          message: 'Demo controls exist only in demo builds.',
        ),
      );
    }
    final textTheme = Theme.of(context).textTheme;
    return AppScaffold(
      title: 'Demo controls',
      body: ListenableBuilder(
        listenable: demo,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            _ScenarioCard(demo: demo, onRun: _runScenario),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              title: 'Account state',
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: RadioGroup<DemoAccount>(
                groupValue: demo.account,
                onChanged: (account) {
                  if (account != null) _useAccount(context, account);
                },
                child: Column(
                  children: [
                    for (final account in DemoAccount.values)
                      RadioListTile<DemoAccount>(
                        value: account,
                        title: Text(account.label),
                        subtitle: Text(account.description),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                children: [
                  SwitchListTile(
                    value: demo.networkAvailable,
                    onChanged: (value) => demo.networkAvailable = value,
                    title: const Text('Network available'),
                    subtitle: const Text(
                      'Turn off to see offline banners and blocked actions.',
                    ),
                  ),
                  SwitchListTile(
                    value: demo.locationPermissionGranted,
                    onChanged: (value) =>
                        demo.locationPermissionGranted = value,
                    title: const Text('Location permission'),
                    subtitle: const Text(
                      'Turn off to block going online until it is allowed.',
                    ),
                  ),
                  SwitchListTile(
                    value: demo.locationServiceEnabled,
                    onChanged: (value) => demo.locationServiceEnabled = value,
                    title: const Text('Location service (GPS)'),
                    subtitle: const Text(
                      'Turn off to see the "location is off" states.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              title: 'Online blockers',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Each takes effect at once, or after the current order.',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    value: demo.rejectNextDocument,
                    onChanged: (value) => demo.rejectNextDocument = value,
                    title: const Text('Reject next document upload'),
                    subtitle: const Text('Reviews finish after 10 seconds'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                  ),
                  _ActionRow(
                    label: 'Expire driving licence',
                    onPressed: () => _apply(
                      context,
                      demo.expireDocument,
                      'Driving licence expired',
                    ),
                  ),
                  _ActionRow(
                    label: 'Set cash in hand to ₹2,150',
                    onPressed: () => _apply(
                      context,
                      () => demo.setCashInHand(DemoController.blockedCashPaise),
                      'Cash in hand is now ₹2,150',
                    ),
                  ),
                  _ActionRow(
                    label: 'Both (licence and cash)',
                    onPressed: () => _apply(
                      context,
                      demo.blockGoingOnline,
                      'Licence expired and cash over the limit',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              title: 'Offers',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Offers appear over any screen while you're online, not "
                    'on a break and not on a trip.',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ActionRow(
                    label: 'Send offer now',
                    onPressed: () => _sendOffer(context, const OfferRequest()),
                  ),
                  _ActionRow(
                    label: 'Send batched offer',
                    onPressed: () =>
                        _sendOffer(context, const OfferRequest(batched: true)),
                  ),
                  _ActionRow(
                    label: 'Send offer that expires in 5 s',
                    onPressed: () => _sendOffer(
                      context,
                      const OfferRequest(timeoutSeconds: 5),
                    ),
                  ),
                  _ActionRow(
                    label: 'Send cash on delivery offer',
                    onPressed: () => _sendOffer(
                      context,
                      const OfferRequest(payment: PaymentMode.cod),
                    ),
                  ),
                  _ActionRow(
                    label: 'Send prepaid offer',
                    onPressed: () => _sendOffer(
                      context,
                      const OfferRequest(payment: PaymentMode.prepaid),
                    ),
                  ),
                  _ActionRow(
                    label: 'Next offer gets taken by someone else',
                    onPressed: () => _apply(
                      context,
                      () => demo.takeNextOffer = true,
                      'The next offer will be taken by another partner',
                    ),
                  ),
                  _ActionRow(
                    label: 'Set cash in hand to ₹1,850',
                    onPressed: () => _apply(
                      context,
                      () =>
                          demo.setCashInHand(DemoController.nearLimitCashPaise),
                      'Cash in hand is now ₹1,850',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              title: 'Zone demand',
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: RadioGroup<DemandOverride>(
                groupValue: demo.demandOverride,
                onChanged: (value) {
                  if (value != null) demo.demandOverride = value;
                },
                child: Column(
                  children: [
                    for (final option in DemandOverride.values)
                      RadioListTile<DemandOverride>(
                        value: option,
                        title: Text(option.label),
                        subtitle: option == DemandOverride.schedule
                            ? const Text('Busy 12–3 PM and 7–11 PM')
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _SimulationCard(demo: demo, apply: _apply),
            const SizedBox(height: AppSpacing.md),
            _PickupCard(demo: demo),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              title: 'Customer',
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: RadioGroup<CustomerResponse>(
                groupValue: demo.customerResponse,
                onChanged: (value) {
                  if (value != null) demo.customerResponse = value;
                },
                child: Column(
                  children: [
                    for (final option in CustomerResponse.values)
                      RadioListTile<CustomerResponse>(
                        value: option,
                        title: Text(option.label),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                      ),
                    SwitchListTile(
                      value: demo.upiPaymentFails,
                      onChanged: (value) => demo.upiPaymentFails = value,
                      title: const Text('UPI payments fail'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                    ),
                    SwitchListTile(
                      value: demo.tipAfterDelivery,
                      onChanged: (value) => demo.tipAfterDelivery = value,
                      title: const Text('Customer tips ₹10 after delivery'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.pin_outlined),
                      title: const Text('Customer delivery code'),
                      subtitle: Text(demo.customerOtp ?? 'No drop in progress'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              title: 'Money',
              child: Column(
                children: [
                  SwitchListTile(
                    value: demo.payoutFails,
                    onChanged: (value) => demo.payoutFails = value,
                    title: const Text('Payouts fail at the bank'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                  ),
                  SwitchListTile(
                    value: demo.raining,
                    onChanged: (value) => demo.raining = value,
                    title: const Text("It's raining"),
                    subtitle: const Text('Rain bonus ₹15 per order for 2 h'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.event_repeat_rounded),
                    title: const Text('Run weekly payout now'),
                    subtitle: const Text('Pays the balance as on Monday 6 AM'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    onTap: () {
                      final payout = demo.runWeeklyPayout();
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              payout == null
                                  ? 'Balance is below the ₹100 minimum.'
                                  : 'Weekly payout of '
                                        '${formatPaise(payout.amountPaise)} '
                                        'started',
                            ),
                          ),
                        );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              title: 'Failures',
              child: Column(
                children: [
                  _ActionRow(
                    label: 'Next request fails (server error)',
                    onPressed: () => _apply(
                      context,
                      demo.failNextRequest,
                      'The next server request will fail',
                    ),
                  ),
                  _ActionRow(
                    label: 'Next photo capture fails',
                    onPressed: () => _apply(
                      context,
                      demo.failNextPhoto,
                      'The next camera or gallery pick will fail',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: ListTile(
                leading: const Icon(Icons.widgets_outlined),
                title: const Text('Component gallery'),
                subtitle: const Text('Every shared component and state'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.componentGallery),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Reset demo data',
              icon: Icons.restart_alt_rounded,
              variant: ButtonVariant.destructive,
              onPressed: () => _reset(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Changes affect only this demo on this device.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks one of the scripted scenarios and shows its steps.
class _ScenarioCard extends StatefulWidget {
  const _ScenarioCard({required this.demo, required this.onRun});

  final DemoController demo;
  final Future<void> Function(BuildContext, DemoScenario) onRun;

  @override
  State<_ScenarioCard> createState() => _ScenarioCardState();
}

class _ScenarioCardState extends State<_ScenarioCard> {
  late DemoScenario _selected = widget.demo.scenario ?? DemoScenario.happyPath;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scenario = _selected;
    final prepared = widget.demo.scenario == scenario;
    return AppCard(
      title: 'Scenario',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<DemoScenario>(
            initialValue: scenario,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Scenario'),
            items: [
              for (final s in DemoScenario.values)
                DropdownMenuItem(
                  value: s,
                  child: Text(
                    '${s.number}. ${s.title}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (s) {
              if (s != null) setState(() => _selected = s);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Setup: ${scenario.setup}', style: textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          for (final (index, step) in scenario.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('${index + 1}.', style: textTheme.bodyMedium),
                  ),
                  Expanded(child: Text(step, style: textTheme.bodyMedium)),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            label: prepared ? 'Run again' : 'Run scenario',
            icon: Icons.play_arrow_rounded,
            onPressed: () => widget.onRun(context, scenario),
          ),
          if (scenario.usesTrip)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Runs the rider at 5× speed.',
                style: textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Rider movement on the demo map: speed, pause, jumps, GPS loss, route
/// deviation and routing failure.
class _SimulationCard extends StatelessWidget {
  const _SimulationCard({required this.demo, required this.apply});

  final DemoController demo;
  final void Function(BuildContext, VoidCallback, String) apply;

  @override
  Widget build(BuildContext context) {
    final services = context.services;
    final textTheme = Theme.of(context).textTheme;
    final hasTrip = services.trip.hasTrip;
    final headingToStore =
        services.trip.trip?.status == TripStatus.headingToStore;
    return AppCard(
      title: 'Simulation',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Speeds up the demo clock: rider movement, countdowns and '
            'waiting pay.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1×')),
              ButtonSegment(value: 2, label: Text('2×')),
              ButtonSegment(value: 5, label: Text('5×')),
            ],
            selected: {demo.speed},
            onSelectionChanged: (value) => demo.speed = value.first,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: demo.movementPaused,
            onChanged: (value) => demo.movementPaused = value,
            title: const Text('Pause rider movement'),
          ),
          if (!hasTrip)
            Text(
              'Accept an order to try the route tools below.',
              style: textTheme.bodySmall,
            ),
          _ActionRow(
            label: headingToStore ? 'Jump to store' : 'Jump to next stop',
            onPressed: () => apply(
              context,
              demo.jumpToNextStop,
              headingToStore
                  ? 'Rider moved to the store'
                  : 'Rider moved to the next stop',
            ),
          ),
          _ActionRow(
            label: 'Lose GPS for 20 s',
            onPressed: () =>
                apply(context, demo.loseGps, 'GPS signal lost for 20 s'),
          ),
          _ActionRow(
            label: 'Simulate route deviation',
            onPressed: () => apply(
              context,
              services.navigation.simulateDeviation,
              'Rider left the route; recalculating',
            ),
          ),
          _ActionRow(
            label: 'Next route is unavailable',
            onPressed: () => apply(
              context,
              () => demo.failNext(OperationType.planRoute),
              'The next route calculation will fail',
            ),
          ),
        ],
      ),
    );
  }
}

/// Pickup scenarios: skip a store wait, or cancel the order before pickup.
class _PickupCard extends StatelessWidget {
  const _PickupCard({required this.demo});

  final DemoController demo;

  void _run(BuildContext context, bool Function() action, String done) {
    final applied = action();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            applied ? done : 'Nothing to do: no active order to change.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      title: 'Active order',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Store events before pickup; the customer can cancel until '
            'delivery.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          _ActionRow(
            label: 'Skip store wait',
            onPressed: () => _run(
              context,
              demo.skipStoreWait,
              'Store wait skipped (logged as a demo skip)',
            ),
          ),
          _ActionRow(
            label: 'Customer cancels the order',
            onPressed: () => _run(
              context,
              () => demo.cancelTrip(CancelledBy.customer),
              'The customer cancelled the order',
            ),
          ),
          _ActionRow(
            label: 'Store cancels the order',
            onPressed: () => _run(
              context,
              () => demo.cancelTrip(CancelledBy.store),
              'The store cancelled the order',
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 44),
        ),
      ),
    );
  }
}
