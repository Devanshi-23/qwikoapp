import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../controllers/safety_controller.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/support.dart';
import '../../utils/app_colors.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/primary_button.dart';
import 'call_112.dart';

/// SOS: a 5-second chance to cancel, then the (simulated) alert and
/// "I'm safe now". Cancelling records nothing.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  static const countdownSeconds = 5;

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  late final SafetyController _safety = context.services.safety;
  Timer? _timer;
  late int _remaining = SosScreen.countdownSeconds;
  String? _error;

  bool get _counting => _timer?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    if (_safety.activeSos == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (_remaining > 1) {
      setState(() => _remaining--);
      return;
    }
    _timer?.cancel();
    _send();
  }

  Future<void> _send() async {
    setState(() => _error = null);
    try {
      await _safety.raiseSos();
      if (mounted) setState(() {});
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    }
  }

  void _cancel() {
    _timer?.cancel();
    Navigator.pop(context);
  }

  Future<void> _markSafe(SafetyIncident sos) async {
    try {
      await _safety.markSafe(sos.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text("Glad you're safe. Alert closed.")),
        );
      Navigator.pop(context);
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_counting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: ListenableBuilder(
        listenable: _safety,
        builder: (context, _) {
          final sos = _safety.activeSos;
          return Scaffold(
            backgroundColor: sos == null ? AppColors.error : Colors.white,
            appBar: AppBar(
              backgroundColor: sos == null ? AppColors.error : Colors.white,
              foregroundColor: sos == null ? Colors.white : AppColors.textDark,
              title: const Text('SOS'),
              automaticallyImplyLeading: sos != null,
            ),
            body: SafeArea(
              child: sos == null ? _buildCountdown() : _buildSent(sos),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCountdown() {
    final textTheme = Theme.of(context).textTheme;
    final error = _error;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const Spacer(),
          Text(
            error == null ? 'Sending SOS in' : "SOS couldn't be sent",
            style: textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (error == null)
            Semantics(
              liveRegion: true,
              label: 'Sending in $_remaining seconds',
              excludeSemantics: true,
              child: Text(
                _counting ? '$_remaining' : '…',
                style: textTheme.displayLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 96,
                ),
              ),
            )
          else
            Text(
              error,
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(color: Colors.white),
            ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Our safety team and your emergency contacts will be alerted '
            'with your location.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
          const Spacer(),
          if (error != null) ...[
            PrimaryButton(label: 'Try again', onPressed: _send),
            const SizedBox(height: AppSpacing.md),
          ],
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white, width: 2),
              ),
              onPressed: _cancel,
              child: const Text(
                'Cancel SOS',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSent(SafetyIncident sos) {
    final textTheme = Theme.of(context).textTheme;
    final contacts =
        context.services.profile.profile?.emergencyContacts ?? const [];
    final location = sos.location;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const Icon(
          Icons.notifications_active_rounded,
          size: 56,
          color: AppColors.error,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Alert sent',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        const Center(child: SimulatedLabel(text: 'Simulated alert')),
        const SizedBox(height: AppSpacing.lg),
        _Step(
          icon: Icons.support_agent_rounded,
          title: 'Qwiko safety team notified',
          body: 'They will call you within 2 minutes.',
        ),
        _Step(
          icon: Icons.contact_phone_outlined,
          title: contacts.isEmpty
              ? 'No emergency contacts yet'
              : 'Emergency contacts messaged',
          body: contacts.isEmpty
              ? 'Add someone we can alert next time.'
              : '${contacts.map((c) => c.name).join(', ')} got your live '
                    'location.',
          action: contacts.isEmpty
              ? TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.emergencyContacts),
                  child: const Text('Add an emergency contact'),
                )
              : null,
        ),
        _Step(
          icon: Icons.local_police_outlined,
          title: 'Nearest help',
          body: location == null
              ? 'Location unavailable. Tell the agent where you are.'
              : 'Lajpat Nagar police station, about 1.2 km away. Shared at '
                    '${formatTime(sos.at)}.',
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Call 112',
          icon: Icons.call_rounded,
          variant: ButtonVariant.destructive,
          onPressed: () => call112(context),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          "Opens your phone's dialer with 112 filled in.",
          textAlign: TextAlign.center,
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: "I'm safe now",
          icon: Icons.verified_user_outlined,
          variant: ButtonVariant.outlined,
          isLoading: _safety.isSending,
          onPressed: () => _markSafe(sos),
        ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(error, style: const TextStyle(color: AppColors.error)),
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
                ?action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
