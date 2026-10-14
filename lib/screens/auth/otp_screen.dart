import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../core/validators.dart';
import '../../models/auth.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/countdown_ring.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/otp_input.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/state_views.dart';

/// Enters the OTP for the session's current challenge. Attempts, lockout and
/// resend timing come from the challenge; this screen only counts down.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, this.purpose = OtpPurpose.signIn});

  final OtpPurpose purpose;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otp = TextEditingController();
  Timer? _ticker;
  String? _error;
  bool _wasLocked = false;
  bool _verifying = false;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _otp.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final challenge = context.services.session.otpChallenge;
    final locked = challenge?.isLockedAt(context.services.clock.now()) ?? false;
    setState(() {
      if (_wasLocked && !locked) _error = null;
      _wasLocked = locked;
    });
  }

  Future<void> _verify() async {
    if (_verifying) return;
    final code = _otp.text;
    final invalid = Validators.signInOtp(code);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    final session = context.services.session;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _error = null;
      _verifying = true;
    });
    try {
      switch (widget.purpose) {
        case OtpPurpose.signIn:
          final partner = await session.verifySignInOtp(code);
          AppRoutes.goToAccountHome(navigator, partner);
        case OtpPurpose.resetPassword:
          final token = await session.verifyResetOtp(code);
          navigator.pushReplacementNamed(
            AppRoutes.resetPassword,
            arguments: token,
          );
      }
    } on OtpFailure catch (failure) {
      if (!mounted) return;
      _otp.clear();
      setState(() {
        _verifying = false;
        _error = failure.message;
        _wasLocked = failure.challenge.isLockedAt(context.services.clock.now());
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() => _verifying = false);
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _resend() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _resending = true);
    try {
      await context.services.session.resendOtp();
      _otp.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('A new OTP has been sent')),
      );
      if (mounted) setState(() => _error = null);
    } on AppFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  static String _clock(Duration d) {
    final seconds = (d.inMilliseconds / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  static String _formatPhone(String phone) => phone.length == 10
      ? '+91 ${phone.substring(0, 5)} ${phone.substring(5)}'
      : '+91 $phone';

  @override
  Widget build(BuildContext context) {
    final services = context.services;
    final challenge = services.session.otpChallenge;
    final textTheme = Theme.of(context).textTheme;

    if (challenge == null || challenge.purpose != widget.purpose) {
      return AppScaffold(
        title: 'Verify OTP',
        body: EmptyState(
          icon: Icons.sms_failed_outlined,
          title: 'No OTP requested',
          message: 'Go back and enter your mobile number to get a new OTP.',
          actionLabel: 'Go back',
          onAction: () => Navigator.maybePop(context),
        ),
      );
    }

    final now = services.clock.now();
    final locked = challenge.isLockedAt(now);
    final resendIn = challenge.resendIn(now);

    return AppScaffold(
      title: 'Verify OTP',
      showDemoBadge: true,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        children: [
          Center(
            child: Container(
              height: 88,
              width: 88,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.sms_outlined,
                color: AppColors.primary,
                size: 42,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Enter the 6-digit code sent to',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            _formatPhone(challenge.phone),
            textAlign: TextAlign.center,
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Center(child: SimulatedLabel(text: 'Demo OTP: 123456')),
          const SizedBox(height: AppSpacing.xxl),
          OtpInput(
            controller: _otp,
            autofocus: true,
            enabled: !locked,
            errorText: _error,
            onChanged: (_) {
              if (_error != null && !locked) setState(() => _error = null);
            },
            onCompleted: (_) => _verify(),
          ),
          if (locked) ...[
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              liveRegion: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CountdownRing(
                    remaining: challenge.lockRemaining(now),
                    total: OtpChallenge.lockout,
                    size: 44,
                    semanticSuffix: 'until you can try again',
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Flexible(
                    child: Text(
                      'Try again in ${_clock(challenge.lockRemaining(now))}',
                      style: textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: challenge.canResendAt(now)
                ? TextButton(
                    onPressed: _resending ? null : _resend,
                    child: const Text('Resend OTP'),
                  )
                : Text(
                    locked
                        ? 'Resend is available after the lock ends'
                        : 'Resend OTP in ${_clock(resendIn)}',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Verify',
            isLoading: _verifying,
            onPressed: locked ? null : _verify,
          ),
        ],
      ),
    );
  }
}
