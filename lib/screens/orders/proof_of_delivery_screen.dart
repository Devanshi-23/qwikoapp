import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../controllers/active_trip_controller.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/delivery_check.dart';
import '../../models/media_ref.dart';
import '../../models/order.dart';
import '../../services/image_service.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/media_image.dart';
import '../../widgets/otp_input.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/slide_to_confirm.dart';
import 'delivery_panels.dart';

/// Proof of delivery and payment for the current drop. Pops with the
/// delivered task, or null if the rider backs out.
class ProofOfDeliveryScreen extends StatefulWidget {
  const ProofOfDeliveryScreen({super.key, required this.controller});

  final ActiveTripController controller;

  @override
  State<ProofOfDeliveryScreen> createState() => _ProofOfDeliveryScreenState();
}

class _ProofOfDeliveryScreenState extends State<ProofOfDeliveryScreen> {
  final _otp = TextEditingController();
  final _received = TextEditingController();
  Timer? _ticker;

  bool _otpVerified = false;
  String? _otpError;
  DateTime? _lockedUntil;
  MediaRef? _photo;
  int _upiPaise = 0;
  bool _changeFromOwnCash = false;
  bool _working = false;

  ActiveTripController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _lockedUntil != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _otp.dispose();
    _received.dispose();
    super.dispose();
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  int? get _receivedPaise {
    final rupees = int.tryParse(_received.text.trim());
    return rupees == null ? null : rupeesToPaise(rupees);
  }

  DeliveryCheck _check(DeliveryTask task) {
    final received = _receivedPaise;
    return DeliveryCheck(
      task: task,
      otpVerified: _otpVerified,
      photo: _photo,
      upiPaise: _upiPaise,
      cash: received == null
          ? null
          : CashCheck(
              duePaise: task.payment.amountToCollectPaise,
              receivedPaise: received,
              upiPaise: _upiPaise,
            ),
    );
  }

  bool get _locked {
    final until = _lockedUntil;
    return until != null && _controller.now.isBefore(until);
  }

  Future<void> _verify(String code) async {
    if (_locked || code.length < 4) return;
    try {
      final result = await _controller.verifyDeliveryOtp(code);
      if (!mounted) return;
      setState(() {
        _otpVerified = result.verified;
        _lockedUntil = result.lockedUntil;
        _otpError = result.verified
            ? null
            : result.lockedUntil != null
            ? 'Too many wrong codes. Entry is locked for 30 s.'
            : 'Wrong code. ${result.attemptsLeft} '
                  '${result.attemptsLeft == 1 ? 'try' : 'tries'} left.';
        if (!result.verified) _otp.clear();
      });
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _otpError = failure.message);
    }
  }

  Future<void> _otpHelp() => showAppBottomSheet<void>(
    context,
    title: "Customer can't find the code?",
    builder: (context) => const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(Icons.sms_outlined),
          title: Text('Ask them to check the order SMS'),
          subtitle: Text('The 4-digit code is in the "Out for delivery" text'),
        ),
        ListTile(
          leading: Icon(Icons.phone_android_rounded),
          title: Text('Or the Qwiko app'),
          subtitle: Text('Orders → this order → Delivery code'),
        ),
        ListTile(
          leading: Icon(Icons.support_agent_rounded),
          title: Text('Still stuck? Call support from Help'),
          subtitle: Text('Support can confirm the delivery for you'),
        ),
        SizedBox(height: AppSpacing.md),
      ],
    ),
  );

  Future<void> _addPhoto() async {
    final choice = await showAppBottomSheet<String>(
      context,
      title: 'Delivery photo',
      subtitle: 'Show the order at the door, without people in it.',
      builder: (context) => Column(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take or choose a photo'),
            onTap: () => Navigator.pop(context, 'device'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Use sample photo'),
            onTap: () => Navigator.pop(context, 'sample'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    MediaRef? photo;
    if (choice == 'sample') {
      photo = const MediaRef.sample('delivery-photo');
    } else {
      final path = await ImageService.pickImage(context);
      if (path != null) photo = MediaRef.file(path);
    }
    if (photo != null && mounted) setState(() => _photo = photo);
  }

  Future<void> _payByUpi(int amountPaise) async {
    final paid = await showAppBottomSheet<bool>(
      context,
      title: 'Collect ${formatPaise(amountPaise)} by UPI',
      subtitle: 'Ask the customer to scan the code with any UPI app.',
      builder: (_) => _UpiSheet(
        amountPaise: amountPaise,
        onCollect: () => _controller.collectUpi(amountPaise),
      ),
    );
    if (paid == true && mounted) {
      setState(() => _upiPaise += amountPaise);
      _say('${formatPaise(amountPaise)} received by UPI.');
    }
  }

  Future<void> _reportPaymentIssue() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Report a payment issue?',
      message:
          "Support reviews it. In the demo the order is treated as "
          'undeliverable and you are paid for the trip.',
      confirmLabel: 'Report',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    try {
      await _controller.markUndeliverable(
        reason: "Customer couldn't pay the full amount.",
        refused: true,
      );
      if (mounted) Navigator.pop(context);
    } on AppFailure catch (failure) {
      if (mounted) _say(failure.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deliver(DeliveryTask task) async {
    final check = _check(task);
    final change = check.cash?.changePaise ?? 0;
    try {
      final delivered = await _controller.completeDelivery(
        check.proof(
          _controller.now,
          changeFromOwnCashPaise: _changeFromOwnCash ? change : 0,
        ),
      );
      if (mounted) Navigator.pop(context, delivered);
    } on AppFailure catch (failure) {
      if (mounted) _say(failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final task = _controller.currentTask;
        if (task == null || task.status != OrderStatus.arrivedAtCustomer) {
          return Scaffold(
            appBar: AppBar(title: const Text('Proof of delivery')),
            body: const Center(child: Text('This drop is no longer active.')),
          );
        }
        final check = _check(task);
        final method = task.requiredProof;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text('Deliver ${task.displayId}'),
            actions: const [
              DemoBadge(),
              SizedBox(width: AppSpacing.sm),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _HandOverCard(task: task),
              if (method.needsOtp) ...[
                const SizedBox(height: AppSpacing.md),
                _buildOtp(task),
              ],
              if (method.needsPhoto) ...[
                const SizedBox(height: AppSpacing.md),
                _buildPhoto(),
              ],
              if (task.payment.amountToCollectPaise > 0) ...[
                const SizedBox(height: AppSpacing.md),
                _buildPayment(task, check),
              ],
              const SizedBox(height: AppSpacing.md),
              _Summary(check: check),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SlideToConfirm(
                  label: 'Slide to mark delivered',
                  enabled: check.isComplete && !_controller.isBusy && !_working,
                  onConfirmed: () => _deliver(task),
                ),
                if (!check.isComplete)
                  DisabledReason('Still needed: ${check.missing.join(', ')}.'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOtp(DeliveryTask task) {
    final hint = context.services.demo?.customerOtp;
    final locked = _locked;
    return AppCard(
      title: 'Delivery code',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_otpVerified)
            const _Done(text: 'OTP verified')
          else ...[
            Text(
              'Ask ${task.customer.firstName} for the 4-digit code.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            OtpInput(
              length: 4,
              controller: _otp,
              enabled: !locked && !_controller.isBusy,
              errorText: locked
                  ? 'Too many wrong codes. Try again in '
                        '${formatClock(_lockedUntil!.difference(_controller.now))}.'
                  : _otpError,
              semanticLabel: 'Delivery code',
              onCompleted: _verify,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (hint != null)
                  Expanded(
                    child: SimulatedLabel(text: 'Demo: the code is $hint'),
                  )
                else
                  const Spacer(),
                TextButton(onPressed: _otpHelp, child: const Text('Get help')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhoto() {
    final photo = _photo;
    return AppCard(
      title: 'Delivery photo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photo == null) ...[
            Text(
              'Required for this order. Show the order at the door.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Add photo',
              icon: Icons.photo_camera_outlined,
              variant: ButtonVariant.outlined,
              onPressed: _addPhoto,
            ),
          ] else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: MediaImage(
                  media: photo,
                  semanticLabel: 'Delivery photo',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Expanded(child: _Done(text: 'Photo added')),
                TextButton.icon(
                  onPressed: _addPhoto,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retake'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPayment(DeliveryTask task, DeliveryCheck check) {
    final textTheme = Theme.of(context).textTheme;
    final due = task.payment.amountToCollectPaise;
    final online = context.services.device.networkAvailable;
    final cashDue = (due - _upiPaise).clamp(0, due);
    final cash = check.cash;
    return AppCard(
      title: 'Collect payment',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Amount due: ${formatPaise(due)}', style: textTheme.titleMedium),
          if (_upiPaise > 0)
            _Done(text: '${formatPaise(_upiPaise)} received by UPI'),
          if (check.paid && cashDue == 0)
            const _Done(text: 'Fully paid')
          else ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _received,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Cash received (₹)',
                helperText: 'Cash to collect: ${formatPaise(cashDue)}',
                errorText: cash?.error,
                prefixText: '₹ ',
              ),
            ),
            if (cash != null && cash.isEnough) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                cash.changePaise == 0
                    ? 'Exact amount. No change to return.'
                    : 'Return ${formatPaise(cash.changePaise)} change.',
                style: textTheme.titleSmall?.copyWith(color: AppColors.primary),
              ),
              if (cash.likelyTypo)
                const DisabledReason(
                  "That's over ₹2,000 more than due. Check the amount.",
                  icon: Icons.warning_amber_rounded,
                ),
              if (cash.changePaise > 0)
                CheckboxListTile(
                  value: _changeFromOwnCash,
                  onChanged: (value) =>
                      setState(() => _changeFromOwnCash = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('I gave the change from my own cash'),
                  subtitle: const Text('Lowers your cash in hand'),
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No change? Ask for the exact amount or UPI.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: cash != null && !cash.isEnough
                  ? 'Customer pays the rest by UPI'
                  : 'Customer wants to pay by UPI',
              icon: Icons.qr_code_2_rounded,
              variant: ButtonVariant.outlined,
              onPressed: online
                  ? () => _payByUpi(
                      cash != null && !cash.isEnough
                          ? cash.shortPaise
                          : cashDue,
                    )
                  : null,
            ),
            if (!online)
              const DisabledReason(
                "You're offline. UPI needs a connection, so collect cash.",
                icon: Icons.cloud_off_rounded,
              ),
            if (cash != null && !cash.isEnough)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: _working ? null : _reportPaymentIssue,
                  child: const Text('Report payment issue'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _HandOverCard extends StatelessWidget {
  const _HandOverCard({required this.task});

  final DeliveryTask task;

  @override
  Widget build(BuildContext context) {
    final contactless = task.customer.preferences.contains(
      CustomerPreference.contactless,
    );
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${task.customer.firstName} · ${task.customer.locality}',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Proof needed: ${task.requiredProof.label}',
            style: textTheme.bodySmall,
          ),
          if (contactless) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Contactless: place the order on the doormat and step back.',
              style: textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          PaymentBanner(payment: task.payment),
        ],
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.check});

  final DeliveryCheck check;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Before you finish',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in check.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    item.done
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: item.done
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 20,
                    semanticLabel: item.done ? 'Done' : 'Not done',
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(item.label)),
                ],
              ),
            ),
          if (check.items.isEmpty)
            const Text('Hand over the order, then slide to finish.'),
        ],
      ),
    );
  }
}

class _UpiSheet extends StatefulWidget {
  const _UpiSheet({required this.amountPaise, required this.onCollect});

  final int amountPaise;
  final Future<bool> Function() onCollect;

  @override
  State<_UpiSheet> createState() => _UpiSheetState();
}

class _UpiSheetState extends State<_UpiSheet> {
  bool _waiting = false;
  String? _error;

  Future<void> _collect() async {
    setState(() {
      _waiting = true;
      _error = null;
    });
    try {
      final paid = await widget.onCollect();
      if (!mounted) return;
      if (paid) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _error = 'Payment failed. Ask the customer to try again.');
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _waiting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_2_rounded, size: 96),
                SimulatedLabel(text: 'Demo QR · not payable'),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          formatPaise(widget.amountPaise),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: _error == null ? 'Check payment' : 'Try again',
          isLoading: _waiting,
          onPressed: _collect,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
