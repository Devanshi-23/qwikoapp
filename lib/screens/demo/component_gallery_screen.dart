import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../app/gallery_samples.dart';
import '../../core/formatters.dart';
import '../../models/media_ref.dart';
import '../../models/money.dart';
import '../../models/order.dart';
import '../../models/partner.dart';
import '../../models/support.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/connectivity_banner.dart';
import '../../widgets/countdown_ring.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/incentive_progress_card.dart';
import '../../widgets/media_image.dart';
import '../../widgets/money_text.dart';
import '../../widgets/offer_details.dart';
import '../../widgets/order_card.dart';
import '../../widgets/otp_input.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/progress_tracker.dart';
import '../../widgets/section_header.dart';
import '../../widgets/slide_to_confirm.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/stop_tile.dart';

/// Every shared component in all its states, at a chosen text scale and
/// width. Reached by long-pressing the `DEMO` pill.
class ComponentGalleryScreen extends StatefulWidget {
  const ComponentGalleryScreen({
    super.key,
    required this.samples,
    this.initialTextScale = 1.0,
    this.initialNarrow = false,
  });

  final GallerySamples samples;
  final double initialTextScale;

  /// Starts constrained to 320 dp wide, the narrowest supported phone.
  final bool initialNarrow;

  @override
  State<ComponentGalleryScreen> createState() => _ComponentGalleryScreenState();
}

class _ComponentGalleryScreenState extends State<ComponentGalleryScreen> {
  late double _textScale = widget.initialTextScale;
  late bool _narrow = widget.initialNarrow;
  final _field = TextEditingController(text: 'Arjun Mehta');
  final _ifsc = TextEditingController(text: 'HDFC12');
  final _otp = TextEditingController(text: '12');

  @override
  void dispose() {
    _field.dispose();
    _ifsc.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final samples = widget.samples;
    final now = samples.now;

    final sections = <Widget>[
      _Section('Buttons', [
        PrimaryButton(label: 'Primary', onPressed: () => _toast('Primary')),
        PrimaryButton(
          label: 'With icon',
          icon: Icons.account_balance_rounded,
          onPressed: () => _toast('With icon'),
        ),
        PrimaryButton(
          label: 'Outlined',
          variant: ButtonVariant.outlined,
          onPressed: () => _toast('Outlined'),
        ),
        PrimaryButton(
          label: 'Log out',
          variant: ButtonVariant.destructive,
          icon: Icons.logout_rounded,
          onPressed: () => _toast('Destructive'),
        ),
        const PrimaryButton(label: 'Saving', isLoading: true, onPressed: null),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PrimaryButton(label: "I've arrived", onPressed: null),
            DisabledReason('Available within 200 m of the store · 1.2 km away'),
          ],
        ),
      ]),
      _Section('Text fields', [
        AppTextField(
          label: 'Full name',
          hint: 'Enter your name',
          icon: Icons.person_outline_rounded,
          controller: _field,
          helperText: 'As printed on your Aadhaar card',
        ),
        AppTextField(
          label: 'IFSC',
          hint: 'HDFC0001234',
          icon: Icons.account_balance_outlined,
          controller: _ifsc,
          errorText: 'Enter a valid 11-character IFSC',
        ),
      ]),
      _Section('OTP input', [
        OtpInput(controller: _otp, onCompleted: (v) => _toast('OTP $v')),
        const OtpInput(errorText: 'Incorrect OTP · 2 attempts left'),
      ]),
      _Section('Status badges', [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in const [
              OrderStatus.delivered,
              OrderStatus.headingToCustomer,
              OrderStatus.returned,
              OrderStatus.cancelled,
            ])
              StatusBadge.order(s),
            for (final s in DocumentStatus.values) StatusBadge.document(s),
            for (final s in PayoutStatus.values) StatusBadge.payout(s),
            for (final s in TicketStatus.values) StatusBadge.ticket(s),
            for (final s in VerificationStatus.values)
              StatusBadge.verification(s),
            for (final s in IncentiveStatus.values) StatusBadge.incentive(s),
            StatusBadge.payout(PayoutStatus.paid, dense: true),
          ],
        ),
      ]),
      _Section('Money and stats', [
        const Wrap(
          spacing: 16,
          children: [
            MoneyText(129500, style: TextStyle(fontSize: 22)),
            MoneyText(4500, prefix: '+'),
            MoneyText(12345678),
          ],
        ),
        Row(
          children: [
            const Expanded(
              child: StatTile(
                icon: Icons.shopping_bag_outlined,
                value: '12',
                label: 'Orders',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                icon: Icons.currency_rupee_rounded,
                value: formatPaise(84500),
                semanticValue: spokenPaise(84500),
                label: 'Earnings',
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: StatTile(
                icon: Icons.timer_outlined,
                value: StatTile.placeholder,
                label: 'Online',
              ),
            ),
          ],
        ),
        const Row(
          children: [
            Expanded(
              child: StatTile(
                value: '412',
                label: 'Delivered',
                valueColor: AppColors.primary,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: '1,204 km',
                label: 'Distance',
                valueColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ]),
      _Section('Section header', [
        SectionHeader(
          'Recent deliveries',
          actionLabel: 'See all',
          onAction: () => _toast('See all'),
        ),
        const SectionHeader('Without action'),
      ]),
      _Section('Stops', [
        const AppCard(
          child: Column(
            children: [
              StopTile(
                kind: StopKind.pickup,
                distanceM: 1200,
                title: 'Qwiko Store · Lajpat Nagar',
                subtitle: 'Counter B, ring bell at rear gate',
              ),
              StopConnector(),
              StopTile(
                kind: StopKind.drop,
                title: 'Priya Sharma',
                subtitle:
                    'Flat 302, Tower B, Green Meadows, near the temple, '
                    'Lajpat Nagar IV, New Delhi 110024',
                subtitleMaxLines: 3,
              ),
            ],
          ),
        ),
      ]),
      _Section('Order cards', [
        for (final order in samples.orders)
          OrderCard(
            order: order,
            when: formatDateTime(order.lastUpdatedAt, now: now),
            onTap: () => _toast(order.displayId),
          ),
      ]),
      _Section('Offer details', [
        OfferDetails(
          offer: samples.offer,
          rider: samples.rider,
          trailing: const CountdownRing(
            remaining: Duration(seconds: 22),
            total: Duration(seconds: 30),
            size: 64,
          ),
        ),
        OfferDetails(
          offer: samples.batchedOffer,
          rider: samples.rider,
          warning: codLimitReason(15000),
          trailing: const CountdownRing(
            remaining: Duration(seconds: 5),
            total: Duration(seconds: 30),
            size: 64,
          ),
        ),
      ]),
      _Section('Progress tracker', [
        for (var step = 0; step < 4; step++)
          ProgressTracker(
            steps: const ['Pickup', 'Collect', 'Drop', 'Deliver'],
            current: step,
          ),
      ]),
      _Section('Incentives', [
        for (final incentive in samples.incentives)
          IncentiveProgressCard(incentive: incentive, now: now),
      ]),
      _Section('Slide to confirm', [
        SlideToConfirm(
          label: 'Slide to accept',
          onConfirmed: () => _toast('Confirmed'),
        ),
        const SlideToConfirm(
          label: 'Slide to deliver',
          enabled: false,
          onConfirmed: _noop,
        ),
        const DisabledReason('Verify the customer OTP first'),
      ]),
      const _Section('Countdown ring', [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            CountdownRing(
              remaining: Duration(seconds: 30),
              total: Duration(seconds: 30),
            ),
            CountdownRing(
              remaining: Duration(seconds: 12),
              total: Duration(seconds: 30),
            ),
            CountdownRing(
              remaining: Duration(seconds: 4),
              total: Duration(seconds: 30),
            ),
            CountdownRing(
              remaining: Duration(seconds: 90),
              total: Duration(seconds: 120),
              size: 72,
            ),
          ],
        ),
      ]),
      _Section('States', [
        EmptyState(
          icon: Icons.radar_rounded,
          title: 'Waiting for new orders...',
          message: 'Stay in a busy area to get orders faster.',
          boxed: true,
          actionLabel: 'Go online',
          onAction: () => _toast('Go online'),
        ),
        ErrorState(
          message: 'No internet connection. Check your network.',
          onRetry: () => _toast('Retry'),
        ),
        ErrorState(
          message: 'Could not load more orders.',
          onRetry: () => _toast('Retry'),
          compact: true,
        ),
        const SkeletonList(count: 2),
        const Row(
          children: [
            SkeletonBox(width: 44, height: 44, radius: 22),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 14)),
          ],
        ),
      ]),
      _Section('Dialogs and sheets', [
        PrimaryButton(
          label: 'Confirm dialog',
          variant: ButtonVariant.outlined,
          onPressed: () async {
            final ok = await showConfirmDialog(
              context,
              title: 'Withdraw earnings?',
              message: '${formatPaise(129500)} to HDFC •••• 4821',
              confirmLabel: 'Withdraw ${formatPaise(129500)}',
            );
            _toast(ok ? 'Confirmed' : 'Cancelled');
          },
        ),
        PrimaryButton(
          label: 'Bottom sheet',
          variant: ButtonVariant.outlined,
          onPressed: () => showAppBottomSheet<void>(
            context,
            title: 'Why are you declining?',
            subtitle: 'Declining never affects your rating.',
            builder: (context) => Column(
              children: [
                for (final reason in const [
                  'Too far',
                  'Low payout',
                  'Vehicle issue',
                ])
                  ListTile(
                    title: Text(reason),
                    onTap: () => Navigator.pop(context),
                  ),
              ],
            ),
          ),
        ),
      ]),
      const _Section('Demo labelling', [
        ConnectivityBanner(offline: true),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [DemoBadge(), SimulatedLabel()],
        ),
      ]),
      const _Section('Media', [
        SizedBox(
          height: 80,
          width: 80,
          child: MediaImage(
            media: MediaRef.sample('documents/aadhaar'),
            fallback: Icon(Icons.badge_outlined, size: 40),
          ),
        ),
      ]),
    ];

    final media = MediaQuery.of(context);

    return AppScaffold(
      title: 'Component gallery',
      showDemoBadge: true,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 1.0, label: Text('1.0×')),
                    ButtonSegment(value: 2.0, label: Text('2.0×')),
                  ],
                  selected: {_textScale},
                  onSelectionChanged: (s) =>
                      setState(() => _textScale = s.first),
                ),
                FilterChip(
                  label: const Text('320 dp'),
                  selected: _narrow,
                  onSelected: (v) => setState(() => _narrow = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: MediaQuery(
              data: media.copyWith(textScaler: TextScaler.linear(_textScale)),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: SizedBox(
                    width: _narrow ? 320 - AppSpacing.lg * 2 : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: sections,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _noop() {}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title),
          for (final child in children) ...[
            child,
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}
