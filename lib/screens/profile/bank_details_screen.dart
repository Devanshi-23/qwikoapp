import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../controllers/profile_controller.dart';
import '../../core/failures.dart';
import '../../core/validators.dart';
import '../../models/partner.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/unsaved_changes_guard.dart';

class BankDetailsScreen extends StatefulWidget {
  final bool isOnboarding;

  const BankDetailsScreen({super.key, this.isOnboarding = false});

  @override
  State<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends State<BankDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ProfileController _controller = context.services.profile;
  late final PartnerProfile? _profile = _controller.profile;
  late final BankAccount? _bank = _profile?.bank;

  /// A saved account number stays masked until the rider changes it.
  late bool _changingAccount = _bank == null;

  late final _holderController = TextEditingController(
    text: _bank?.holderName ?? _profile?.name ?? '',
  );
  final _accountController = TextEditingController();
  final _confirmController = TextEditingController();
  late final _ifscController = TextEditingController(text: _bank?.ifsc ?? '');
  late final _upiController = TextEditingController(
    text: _profile?.upiId ?? '',
  );

  @override
  void dispose() {
    _holderController.dispose();
    _accountController.dispose();
    _confirmController.dispose();
    _ifscController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  String get _ifsc => _ifscController.text.trim().toUpperCase();

  bool get _isDirty =>
      _holderController.text.trim() !=
          (_bank?.holderName ?? _profile?.name ?? '') ||
      _accountController.text.isNotEmpty ||
      _ifsc != (_bank?.ifsc ?? '') ||
      _upiController.text.trim() != (_profile?.upiId ?? '');

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final ifsc = _ifsc;
    final previous = _bank;
    final accountNumber = _changingAccount
        ? _accountController.text.trim()
        : previous!.accountNumber;
    final unchanged =
        previous != null &&
        previous.accountNumber == accountNumber &&
        previous.ifsc == ifsc;

    try {
      await _controller.updateBank(
        BankAccount(
          holderName: _holderController.text.trim(),
          accountNumber: accountNumber,
          ifsc: ifsc,
          bankName: bankNameForIfsc(ifsc),
          verification: unchanged
              ? previous.verification
              : BankVerification.verifying,
        ),
        upiId: _upiController.text.trim(),
      );
    } on AppFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!widget.isOnboarding) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            unchanged
                ? 'Bank details saved'
                : 'Bank details saved. Verifying the account…',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final bank = _bank;
    final ifscError = Validators.ifsc(_ifsc);
    return UnsavedChangesGuard(
      isDirty: () => _isDirty,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('Bank Details')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Banner(
                    icon: bank?.verification == BankVerification.verifying
                        ? Icons.hourglass_top_rounded
                        : Icons.lock_outline_rounded,
                    text: switch (bank?.verification) {
                      BankVerification.verifying =>
                        'Verifying your bank account. Withdrawals start once '
                            "it's verified (about 10 seconds in the demo).",
                      BankVerification.failed =>
                        "We couldn't verify this account. Check the number "
                            'and IFSC, then save again.',
                      _ =>
                        'Your earnings are sent to this account every week. '
                            'Details are kept secure.',
                    },
                  ),
                  AppTextField(
                    label: 'Account Holder Name',
                    hint: 'Name as per bank records',
                    icon: Icons.person_outline_rounded,
                    controller: _holderController,
                    textCapitalization: TextCapitalization.words,
                    validator: Validators.name,
                  ),
                  if (!_changingAccount && bank != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.account_balance_outlined,
                          color: AppColors.primary,
                        ),
                        title: Text('Account ${bank.maskedAccountNumber}'),
                        subtitle: Text(switch (bank.verification) {
                          BankVerification.verified => 'Verified',
                          BankVerification.verifying => 'Verifying',
                          BankVerification.failed => 'Verification failed',
                        }),
                        trailing: TextButton(
                          onPressed: () =>
                              setState(() => _changingAccount = true),
                          child: const Text('Change account'),
                        ),
                      ),
                    )
                  else ...[
                    AppTextField(
                      label: 'Account Number',
                      hint: 'Enter bank account number',
                      icon: Icons.account_balance_outlined,
                      controller: _accountController,
                      keyboardType: TextInputType.number,
                      maxLength: 18,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: Validators.bankAccount,
                    ),
                    AppTextField(
                      label: 'Confirm Account Number',
                      hint: 'Re-enter account number',
                      icon: Icons.account_balance_outlined,
                      controller: _confirmController,
                      keyboardType: TextInputType.number,
                      maxLength: 18,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => Validators.matches(
                        v,
                        _accountController.text,
                        'Account numbers do not match',
                      ),
                    ),
                  ],
                  AppTextField(
                    label: 'IFSC Code',
                    hint: 'e.g. SBIN0001234',
                    icon: Icons.qr_code_rounded,
                    controller: _ifscController,
                    maxLength: 11,
                    textCapitalization: TextCapitalization.characters,
                    validator: Validators.ifsc,
                    onChanged: (_) => setState(() {}),
                    helperText: ifscError == null
                        ? bankNameForIfsc(_ifsc)
                        : null,
                  ),
                  AppTextField(
                    label: 'UPI ID (optional)',
                    hint: 'e.g. name@upi',
                    icon: Icons.currency_rupee_rounded,
                    controller: _upiController,
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.optionalUpi,
                    helperText: 'Used for UPI payouts in a later update.',
                  ),
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => PrimaryButton(
                      label: widget.isOnboarding
                          ? 'Save & Continue'
                          : 'Save Details',
                      isLoading: _controller.isSaving,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
