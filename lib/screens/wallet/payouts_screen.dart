import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/formatters.dart';
import '../../models/money.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_header.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_badge.dart';
import 'withdraw_sheet.dart';

/// Balance, next weekly payout, and payout history with retries.
class PayoutsScreen extends StatefulWidget {
  const PayoutsScreen({super.key, this.highlightId});

  /// Payout opened from a notification.
  final String? highlightId;

  @override
  State<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends State<PayoutsScreen> {
  late final _wallet = context.services.wallet;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _wallet.ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Payouts',
      showDemoBadge: true,
      body: ListenableBuilder(
        listenable: _wallet,
        builder: (context, _) {
          final balance = _wallet.balance;
          if (balance == null) {
            final error = _wallet.error;
            return error == null
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: SkeletonList(count: 3),
                  )
                : ErrorState(message: error, onRetry: _wallet.load);
          }
          return RefreshIndicator(
            onRefresh: _wallet.refresh,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                PayoutBalanceCard(balance: balance),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader('Payout history'),
                const SimulatedLabel(text: 'Simulated payouts'),
                const SizedBox(height: AppSpacing.sm),
                if (_wallet.payouts.isEmpty)
                  const EmptyState(
                    icon: Icons.account_balance_outlined,
                    title: 'No payouts yet',
                    message: 'Earnings are paid to your bank every Monday.',
                    boxed: true,
                  ),
                for (final payout in _wallet.payouts)
                  PayoutTile(
                    payout: payout,
                    highlighted: payout.id == widget.highlightId,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Available balance with the instant withdrawal button.
class PayoutBalanceCard extends StatelessWidget {
  const PayoutBalanceCard({super.key, required this.balance, this.onPayouts});

  final WalletBalance balance;

  /// Shows a "Payouts" button when set.
  final VoidCallback? onPayouts;

  Future<void> _withdraw(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final payout = await showWithdrawSheet(context);
    if (payout == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${formatPaise(payout.amountPaise)} withdrawal requested · '
            '${payout.reference}',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final services = context.services;
    final wallet = services.wallet;
    const white = TextStyle(color: Colors.white);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available balance',
            style: white.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          MoneyText(
            balance.withdrawablePaise,
            style: white.copyWith(fontSize: 34, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Auto payout every Monday · next '
            '${formatDate(balance.nextScheduledPayoutOn, now: services.clock.now())}',
            style: white.copyWith(fontSize: 12),
          ),
          if (balance.pendingPaise > 0)
            Text(
              '${formatPaise(balance.pendingPaise)} on its way to your bank',
              style: white.copyWith(fontSize: 12),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: wallet.isWithdrawing
                      ? null
                      : () => _withdraw(context),
                  icon: const Icon(Icons.account_balance_rounded, size: 20),
                  label: Text(
                    wallet.alreadyWithdrewToday
                        ? 'Withdrawn today'
                        : 'Withdraw now',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    elevation: 0,
                  ),
                ),
              ),
              if (onPayouts != null) ...[
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: onPayouts,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                  ),
                  child: const Text('Payouts'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class PayoutTile extends StatelessWidget {
  const PayoutTile({super.key, required this.payout, this.highlighted = false});

  final Payout payout;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final style = payoutStatusStyle(payout.status);
    final failureReason = payout.failureReason;
    final now = context.services.clock.now();
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      borderColor: highlighted ? AppColors.primary : AppColors.border,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(style.icon, color: style.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MoneyText(
                  payout.amountPaise,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                StatusBadge(style, dense: true),
                const SizedBox(height: 4),
                Text(
                  '${payout.kind} · '
                  '${formatDateTime(payout.requestedAt, now: now)} · '
                  '${payout.reference}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (failureReason != null)
                  Text(
                    failureReason,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                    ),
                  ),
                if (payout.status == PayoutStatus.failed && payout.isInstant)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                      onPressed: () => showWithdrawSheet(
                        context,
                        amountPaise: payout.amountPaise,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
