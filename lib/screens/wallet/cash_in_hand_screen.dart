import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../core/validators.dart';
import '../../models/money.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/money_text.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
import '../../widgets/state_views.dart';

/// COD cash the rider holds, the limit, depositing it, and past deposits.
class CashInHandScreen extends StatefulWidget {
  const CashInHandScreen({super.key});

  /// Share of the limit at which the screen warns.
  static const warnAt = 0.8;

  @override
  State<CashInHandScreen> createState() => _CashInHandScreenState();
}

class _CashInHandScreenState extends State<CashInHandScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  DepositMethod _method = DepositMethod.storeCounter;
  int? _prefilledFor;

  late final _wallet = context.services.wallet;

  @override
  void initState() {
    super.initState();
    _wallet.addListener(_prefill);
    _prefill();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _wallet.ensureLoaded();
    });
  }

  @override
  void dispose() {
    _wallet.removeListener(_prefill);
    _amount.dispose();
    super.dispose();
  }

  int get _amountPaise => rupeesToPaise(int.tryParse(_amount.text) ?? 0);

  /// Suggests the full balance, again whenever the balance changes.
  void _prefill() {
    if (!_wallet.isReady) return;
    final balance = _wallet.cash.balancePaise;
    if (_prefilledFor == balance) return;
    _prefilledFor = balance;
    _amount.text = balance > 0 ? '${(balance / 100).floor()}' : '';
  }

  Future<void> _deposit() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final deposit = await _wallet.depositCash(_amountPaise, _method);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Deposited ${formatPaise(deposit.amountPaise)} · '
              'Ref ${deposit.reference}',
            ),
            backgroundColor: AppColors.primary,
          ),
        );
    } on AppFailure catch (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Cash in hand',
      showDemoBadge: true,
      body: ListenableBuilder(
        listenable: _wallet,
        builder: (context, _) {
          if (!_wallet.isReady) {
            final error = _wallet.error;
            return error == null
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: SkeletonList(count: 3),
                  )
                : ErrorState(message: error, onRetry: _wallet.load);
          }
          return _buildBody(_wallet.cash);
        },
      ),
    );
  }

  Widget _buildBody(CashInHand cash) {
    final textTheme = Theme.of(context).textTheme;
    final over = cash.balancePaise >= cash.limitPaise;
    final movements = cash.movements.reversed.take(10).toList();
    final now = context.services.clock.now();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AppCard(
          borderColor: over ? AppColors.error : AppColors.border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You are holding', style: textTheme.bodySmall),
              const SizedBox(height: 4),
              MoneyText(
                cash.balancePaise,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: over ? AppColors.error : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: cash.usage.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  color: over ? AppColors.error : AppColors.primary,
                  semanticsLabel:
                      'Cash limit used: ${(cash.usage * 100).round()} percent',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Limit ${formatPaise(cash.limitPaise)}',
                style: textTheme.bodySmall,
              ),
              if (over) ...[
                const SizedBox(height: 8),
                Text(
                  "You're over the limit. Deposit cash to go online again.",
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else if (cash.usage >= CashInHandScreen.warnAt) ...[
                const SizedBox(height: 8),
                Text(
                  "You're close to the limit. Deposit soon to keep getting "
                  'cash orders; at ${formatPaise(cash.limitPaise)} you '
                  "can't go online.",
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const DisabledReason(
          'Cash in hand is separate from your earnings. Depositing it does '
          'not change your withdrawable balance.',
        ),
        const SizedBox(height: AppSpacing.xl),
        if (cash.balancePaise > 0) _buildDepositForm(cash),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader('Recent cash movements'),
        if (movements.isEmpty)
          const EmptyState(
            icon: Icons.payments_outlined,
            title: 'No cash yet',
            message: 'Cash collected on COD orders shows up here.',
            boxed: true,
          ),
        for (final movement in movements)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              movement.type == CashMovementType.codCollected
                  ? Icons.add_circle_outline_rounded
                  : Icons.remove_circle_outline_rounded,
              color: movement.type == CashMovementType.codCollected
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
            title: Text(switch (movement.type) {
              CashMovementType.codCollected => 'Cash collected',
              CashMovementType.changeGiven => 'Change given',
              CashMovementType.deposit => 'Deposited',
            }),
            subtitle: Text(formatDateTime(movement.at, now: now)),
            trailing: MoneyText(
              movement.amountPaise,
              prefix: movement.signedPaise >= 0 ? '+' : '−',
              style: textTheme.titleSmall,
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader('Deposits'),
        if (cash.deposits.isEmpty)
          const EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No deposits yet',
            boxed: true,
          ),
        for (final deposit in cash.deposits.reversed.take(20))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              deposit.method == DepositMethod.upi
                  ? Icons.qr_code_rounded
                  : Icons.storefront_outlined,
              color: AppColors.primary,
            ),
            title: Text(
              deposit.method == DepositMethod.upi
                  ? 'UPI deposit'
                  : 'Store counter deposit',
            ),
            subtitle: Text(
              '${formatDateTime(deposit.at, now: now)} · '
              'Ref ${deposit.reference}',
            ),
            trailing: MoneyText(
              deposit.amountPaise,
              style: textTheme.titleSmall,
            ),
          ),
      ],
    );
  }

  Widget _buildDepositForm(CashInHand cash) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUnfocus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Deposit cash'),
          AppTextField(
            label: 'Amount (₹)',
            hint: 'Amount to deposit',
            icon: Icons.currency_rupee_rounded,
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (_) => Validators.cashDeposit(
              amountPaise: _amountPaise,
              cashInHandPaise: cash.balancePaise,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          RadioGroup<DepositMethod>(
            groupValue: _method,
            onChanged: (value) {
              if (value != null) setState(() => _method = value);
            },
            child: const Column(
              children: [
                RadioListTile<DepositMethod>(
                  value: DepositMethod.storeCounter,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Pay at a Qwiko store counter'),
                ),
                RadioListTile<DepositMethod>(
                  value: DepositMethod.upi,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Pay by UPI'),
                ),
              ],
            ),
          ),
          const SimulatedLabel(text: 'Simulated deposit'),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Deposit cash',
            icon: Icons.account_balance_wallet_outlined,
            isLoading: _wallet.isDepositing,
            onPressed: _wallet.isDepositing ? null : _deposit,
          ),
        ],
      ),
    );
  }
}
