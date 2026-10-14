import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_services.dart';
import '../../controllers/earnings_controller.dart';
import '../../controllers/loadable_controller.dart';
import '../../controllers/wallet_controller.dart';
import '../../core/formatters.dart';
import '../../models/money.dart';
import '../../utils/app_colors.dart';
import '../../widgets/adaptive.dart';
import '../../widgets/app_card.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_header.dart';
import '../../widgets/state_views.dart';
import '../wallet/payouts_screen.dart';
import 'statement_screen.dart';

/// Shown inside the Earnings tab of the home screen.
class EarningsView extends StatefulWidget {
  const EarningsView({super.key});

  @override
  State<EarningsView> createState() => _EarningsViewState();
}

class _EarningsViewState extends State<EarningsView> {
  late final AppServices _services = context.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _services.earnings.ensureLoaded();
      _services.wallet.ensureLoaded();
    });
  }

  static IconData iconFor(EarningType type) => switch (type) {
    EarningType.orderPay => Icons.delivery_dining_rounded,
    EarningType.waitingPay => Icons.hourglass_bottom_rounded,
    EarningType.surge => Icons.trending_up_rounded,
    EarningType.batchBonus => Icons.layers_outlined,
    EarningType.compensation => Icons.healing_outlined,
    EarningType.tip => Icons.volunteer_activism_outlined,
    EarningType.incentive => Icons.local_fire_department_outlined,
    EarningType.adjustment => Icons.tune_rounded,
    EarningType.payout => Icons.account_balance_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final earnings = _services.earnings;
    final wallet = _services.wallet;

    return ListenableBuilder(
      listenable: Listenable.merge([earnings, wallet]),
      builder: (context, _) {
        final twoPane = Breakpoints.useTwoPane(context);
        final summary = _buildSummary(
          earnings,
          wallet,
          includeOrders: !twoPane,
        );
        Future<void> refresh() =>
            Future.wait([earnings.refresh(), wallet.refresh()]);
        if (!twoPane) {
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: summary,
            ),
          );
        }
        return TwoPane(
          listWidth: 460,
          list: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: summary,
            ),
          ),
          detail: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: earnings.isReady ? _buildOrders(earnings) : const [],
          ),
        );
      },
    );
  }

  List<Widget> _buildSummary(
    EarningsController earnings,
    WalletController wallet, {
    required bool includeOrders,
  }) => [
    Semantics(
      header: true,
      child: Text('Earnings', style: Theme.of(context).textTheme.headlineSmall),
    ),
    const SizedBox(height: 16),
    if (wallet.balance case final balance?)
      PayoutBalanceCard(
        balance: balance,
        onPayouts: () => Navigator.pushNamed(context, AppRoutes.payouts),
      )
    else if (wallet.status == LoadStatus.error)
      ErrorState(message: wallet.error!, onRetry: wallet.load)
    else
      const SkeletonBox(height: 170, radius: 20),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: _LinkTile(
            icon: Icons.local_fire_department_outlined,
            label: 'Incentives',
            onTap: () => Navigator.pushNamed(context, AppRoutes.incentives),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _LinkTile(
            icon: Icons.payments_outlined,
            label: wallet.isReady
                ? 'Cash ${formatPaise(wallet.cash.balancePaise)}'
                : 'Cash in hand',
            onTap: () => Navigator.pushNamed(context, AppRoutes.cashInHand),
          ),
        ),
      ],
    ),
    const SizedBox(height: 20),
    _PeriodPicker(earnings: earnings),
    const SizedBox(height: 12),
    ..._buildEarnings(earnings, includeOrders: includeOrders),
  ];

  List<Widget> _buildEarnings(
    EarningsController earnings, {
    required bool includeOrders,
  }) {
    if (earnings.status == LoadStatus.error) {
      return [ErrorState(message: earnings.error!, onRetry: earnings.load)];
    }
    if (!earnings.isReady) {
      return const [
        SkeletonBox(height: 230, radius: 16),
        SizedBox(height: 14),
        SkeletonBox(height: 180, radius: 16),
      ];
    }
    return [
      AppCard(
        title: earnings.rangeLabel,
        trailing: MoneyText(
          earnings.totalPaise,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: EarningsChart(buckets: earnings.buckets),
        ),
      ),
      const SizedBox(height: 14),
      AppCard(
        title: 'Breakdown · ${earnings.orderCount} orders',
        child: Column(
          children: [
            if (earnings.breakdown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No earnings in this period.'),
              ),
            for (final (type, amount) in earnings.breakdown)
              _BreakdownRow(iconFor(type), type.label, amount),
            const Divider(height: 22, color: AppColors.border),
            _BreakdownRow(null, 'Total', earnings.totalPaise, bold: true),
            const SizedBox(height: 4),
            Text(
              'Order pay includes the base fee and distance pay.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('View statement'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => StatementScreen(
                      title: earnings.rangeLabel,
                      entries: earnings.entries,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      if (includeOrders) ...[
        const SizedBox(height: 20),
        ..._buildOrders(earnings),
      ],
    ];
  }

  List<Widget> _buildOrders(EarningsController earnings) {
    final now = _services.clock.now();
    final orders = earnings.orders;
    return [
      SectionHeader('Orders (${orders.length})'),
      if (orders.isEmpty)
        const EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No orders in this period',
          boxed: true,
        ),
      for (final order in orders)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.inventory_2_outlined,
            color: AppColors.primary,
          ),
          title: Text(order.label),
          subtitle: Text(formatDateTime(order.at, now: now)),
          trailing: MoneyText(
            order.totalPaise,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.orderDetails,
            arguments: order.orderId,
          ),
        ),
    ];
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.earnings});

  final EarningsController earnings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<EarningsPeriod>(
          segments: [
            for (final period in EarningsPeriod.values)
              ButtonSegment(value: period, label: Text(period.label)),
          ],
          selected: {earnings.period},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              earnings.setPeriod(selection.single),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous ${earnings.period.label.toLowerCase()}',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: earnings.canGoPrevious ? earnings.previous : null,
            ),
            Expanded(
              child: Text(
                earnings.rangeLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Next ${earnings.period.label.toLowerCase()}',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: earnings.canGoNext ? earnings.next : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Bars drawn with a custom painter; each bar has its own semantics.
class EarningsChart extends StatelessWidget {
  const EarningsChart({super.key, required this.buckets});

  final List<EarningsBucket> buckets;

  static const chartHeight = 130.0;

  @override
  Widget build(BuildContext context) {
    final maxValue = buckets.fold(
      0,
      (m, b) => b.totalPaise > m ? b.totalPaise : m,
    );
    final showValues = buckets.length <= 7;
    return SizedBox(
      height: chartHeight + 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final bucket in buckets)
            Expanded(
              child: Semantics(
                label:
                    '${bucket.spokenLabel}, '
                    '${spokenPaise(bucket.totalPaise)} earned',
                excludeSemantics: true,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (showValues)
                      Text(
                        bucket.totalPaise == 0
                            ? ''
                            : formatPaise(bucket.totalPaise),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                    const SizedBox(height: 4),
                    CustomPaint(
                      size: Size(
                        double.infinity,
                        maxValue == 0
                            ? 4
                            : (bucket.totalPaise / maxValue * chartHeight)
                                  .clamp(4.0, chartHeight),
                      ),
                      painter: _BarPainter(
                        color: bucket.isCurrent
                            ? AppColors.accent
                            : AppColors.primary,
                        inset: showValues ? 6 : 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      bucket.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: bucket.isCurrent
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: bucket.isCurrent
                            ? FontWeight.w800
                            : FontWeight.w500,
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

class _BarPainter extends CustomPainter {
  const _BarPainter({required this.color, required this.inset});

  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(inset, 0, size.width - inset, size.height);
    if (rect.width <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.color != color || old.inset != inset;
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow(
    this.icon,
    this.label,
    this.amountPaise, {
    this.bold = false,
  });

  final IconData? icon;
  final String label;
  final int amountPaise;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: bold ? AppColors.primary : AppColors.textDark,
      fontSize: bold ? 16 : 14,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textDark,
                fontSize: 14,
                fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
              ),
            ),
          ),
          MoneyText(amountPaise, style: style),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
