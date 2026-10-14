import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../utils/app_colors.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/primary_button.dart';

typedef CallCustomer = Future<({bool answered, Duration duration})> Function();

/// A simulated masked call: connecting, ringing, then answered or no answer.
/// The attempt is logged on the order once the phone has rung; no real call
/// is placed.
Future<void> showCustomerCallSheet(
  BuildContext context, {
  required String name,
  required CallCustomer onCall,
}) => showAppBottomSheet<void>(
  context,
  title: 'Call $name',
  subtitle: 'Simulated call through a Qwiko number. No real call is placed.',
  builder: (_) => CustomerCallSheet(onCall: onCall),
);

class CustomerCallSheet extends StatefulWidget {
  const CustomerCallSheet({super.key, required this.onCall});

  final CallCustomer onCall;

  static const Duration connecting = Duration(seconds: 1);
  static const Duration ringing = Duration(seconds: 2);

  @override
  State<CustomerCallSheet> createState() => _CustomerCallSheetState();
}

enum _Phase { connecting, ringing, answered, noAnswer, failed }

class _CustomerCallSheetState extends State<CustomerCallSheet> {
  _Phase _phase = _Phase.connecting;
  Duration _duration = Duration.zero;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(CustomerCallSheet.connecting, () {
      if (!mounted) return;
      setState(() => _phase = _Phase.ringing);
      _timer = Timer(CustomerCallSheet.ringing, _connect);
    });
  }

  Future<void> _connect() async {
    try {
      final result = await widget.onCall();
      if (!mounted) return;
      setState(() {
        _phase = result.answered ? _Phase.answered : _Phase.noAnswer;
        _duration = result.duration;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = failure.message;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String text) = switch (_phase) {
      _Phase.connecting => (
        Icons.phone_forwarded_rounded,
        AppColors.primary,
        'Connecting via Qwiko number…',
      ),
      _Phase.ringing => (
        Icons.ring_volume_rounded,
        AppColors.primary,
        'Ringing…',
      ),
      _Phase.answered => (
        Icons.call_end_rounded,
        AppColors.primary,
        'Call ended · ${formatClock(_duration)}',
      ),
      _Phase.noAnswer => (
        Icons.phone_missed_rounded,
        AppColors.error,
        'No answer. The attempt is logged on the order.',
      ),
      _Phase.failed => (
        Icons.error_outline_rounded,
        AppColors.error,
        _error ?? "Couldn't place the call.",
      ),
    };
    final inProgress = _phase == _Phase.connecting || _phase == _Phase.ringing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        Icon(icon, size: 48, color: color),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          liveRegion: true,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: inProgress ? 'Hang up' : 'Done',
          variant: inProgress
              ? ButtonVariant.destructive
              : ButtonVariant.filled,
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
