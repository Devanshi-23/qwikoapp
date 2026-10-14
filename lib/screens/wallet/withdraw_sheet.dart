import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../core/validators.dart';
import '../../models/money.dart';
import '../../models/partner.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/primary_button.dart';
import '../profile/bank_details_screen.dart';

/// Instant withdrawal to the bank. Returns the payout once requested.
Future<Payout?> showWithdrawSheet(BuildContext context, {int? amountPaise}) =>
    showAppBottomSheet<Payout>(
      context,
      title: 'Withdraw now',
      subtitle: 'Instant transfer to your bank account',
      builder: (_) => WithdrawForm(amountPaise: amountPaise),
    );

/// Why an instant withdrawal can't start, or null when it can.
String? withdrawBlocker({
  required BankAccount? bank,
  required int availablePaise,
  required bool alreadyWithdrewToday,
}) {
  if (bank == null) return 'Add your bank account to withdraw.';
  if (bank.verification != BankVerification.verified) {
    return 'Your bank account is still being verified. You can withdraw '
        'once it is verified.';
  }
  if (availablePaise < Validators.minWithdrawPaise) {
    return 'You need at least ${formatPaise(Validators.minWithdrawPaise)} '
        'to withdraw. Your balance is ${formatPaise(availablePaise)}.';
  }
  if (alreadyWithdrewToday) {
    return 'You can make one instant withdrawal per day. Try again '
        'tomorrow or wait for the Monday payout.';
  }
  return null;
}

class WithdrawForm extends StatefulWidget {
  const WithdrawForm({super.key, this.amountPaise});

  /// Prefilled amount, for retrying a failed payout.
  final int? amountPaise;

  @override
  State<WithdrawForm> createState() => _WithdrawFormState();
}

class _WithdrawFormState extends State<WithdrawForm> {
  final _formKey = GlobalKey<FormState>();
  late final _wallet = context.services.wallet;
  late final _amount = TextEditingController(
    text: _rupees(
      widget.amountPaise ?? _wallet.balance?.withdrawablePaise ?? 0,
    ),
  );

  static String _rupees(int paise) => paise > 0 ? '${paise ~/ 100}' : '';

  int get _amountPaise => rupeesToPaise(int.tryParse(_amount.text) ?? 0);

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit(BankAccount bank) async {
    if (!_formKey.currentState!.validate()) return;
    final amount = _amountPaise;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Withdraw ${formatPaise(amount)}?',
      message:
          '${formatPaise(amount)} goes to ${bank.bankName} '
          '${bank.maskedAccountNumber}. Fee ₹0. It usually arrives within '
          'a few minutes.',
      confirmLabel: 'Withdraw ${formatPaise(amount)}',
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final payout = await _wallet.withdraw(amount);
      if (mounted) Navigator.pop(context, payout);
    } on AppFailure catch (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bank = context.services.profile.profile?.bank;
    final available = _wallet.balance?.withdrawablePaise ?? 0;
    final blocker = withdrawBlocker(
      bank: bank,
      availablePaise: available,
      alreadyWithdrewToday: _wallet.alreadyWithdrewToday,
    );

    if (blocker != null || bank == null) {
      final needsBank =
          bank == null || bank.verification != BankVerification.verified;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(blocker ?? '', style: textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.lg),
          if (needsBank)
            PrimaryButton(
              label: 'Open bank details',
              icon: Icons.account_balance_outlined,
              onPressed: () {
                final navigator = Navigator.of(context)..pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BankDetailsScreen(),
                  ),
                );
              },
            )
          else
            PrimaryButton(
              label: 'OK',
              variant: ButtonVariant.outlined,
              onPressed: () => Navigator.pop(context),
            ),
          const SizedBox(height: AppSpacing.md),
        ],
      );
    }

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Available ${formatPaise(available)}',
            style: textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'Amount (₹)',
            hint: 'Amount to withdraw',
            icon: Icons.currency_rupee_rounded,
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (_) => Validators.withdrawAmount(
              amountPaise: _amountPaise,
              availablePaise: available,
              alreadyWithdrewToday: _wallet.alreadyWithdrewToday,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Line('To', '${bank.bankName} ${bank.maskedAccountNumber}'),
          const _Line('Fee', '₹0'),
          _Line(
            'Limits',
            'Min ${formatPaise(Validators.minWithdrawPaise)} · one per day',
          ),
          const SizedBox(height: AppSpacing.sm),
          const SimulatedLabel(text: 'Simulated payout'),
          const SizedBox(height: AppSpacing.md),
          ListenableBuilder(
            listenable: _wallet,
            builder: (context, _) => PrimaryButton(
              label: 'Withdraw',
              icon: Icons.account_balance_rounded,
              isLoading: _wallet.isWithdrawing,
              onPressed: () => _submit(bank),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
