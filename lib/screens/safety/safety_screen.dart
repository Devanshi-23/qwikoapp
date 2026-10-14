import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/formatters.dart';
import '../../models/money.dart';
import '../../models/support.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/hold_to_confirm.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
import 'call_112.dart';

/// Safety centre: SOS, Call 112, trip sharing, incident reports, insurance
/// and riding tips.
class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});

  static const tips = [
    (
      Icons.sports_motorsports_outlined,
      'Always wear your helmet, even for short trips.',
    ),
    (
      Icons.water_drop_outlined,
      'In rain, ride slower and avoid waterlogged underpasses.',
    ),
    (
      Icons.nightlight_outlined,
      'At night, keep to well-lit main roads where you can.',
    ),
    (
      Icons.phone_disabled_outlined,
      "Don't use your phone while riding. Pull over first.",
    ),
  ];

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.services.safety.ensureLoaded();
      context.services.profile.ensureLoaded();
    });
  }

  void _openSos() => Navigator.pushNamed(context, AppRoutes.sos);

  String _shareMessage(String orderLabel) {
    final name = context.services.profile.profile?.firstName ?? 'I';
    return "$name is delivering Qwiko order $orderLabel. Follow the ride "
        'live: https://qwiko.in/track/demo';
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Copied. Paste it in a message.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    return AppScaffold(
      title: 'Safety',
      body: ListenableBuilder(
        listenable: Listenable.merge([s.safety, s.trip, s.incentives]),
        builder: (context, _) {
          final sos = s.safety.activeSos;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              if (sos != null) ...[
                AppCard(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderColor: AppColors.error,
                  onTap: _openSos,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active_rounded,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'SOS is active since ${formatTime(sos.at)}. Tap '
                          "when you're safe.",
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              ..._buildAdvisory(),
              AppCard(
                child: Column(
                  children: [
                    HoldToConfirmButton(
                      label: 'SOS',
                      hint: 'Press and hold for 3 seconds',
                      onConfirmed: _openSos,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const SimulatedLabel(
                      text: 'Alerts are simulated in the demo',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _build112Card(),
              const SizedBox(height: AppSpacing.md),
              ..._buildShareTrip(),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.report_outlined,
                        color: AppColors.primary,
                      ),
                      title: const Text('Report an incident'),
                      subtitle: const Text(
                        'Accident, harassment, breakdown or unsafe place',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.reportIncident,
                      ),
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.contact_phone_outlined,
                        color: AppColors.primary,
                      ),
                      title: const Text('Emergency contacts'),
                      subtitle: Text(
                        switch (s.profile.profile?.emergencyContacts.length ??
                            0) {
                          0 => 'None added',
                          1 => '1 contact',
                          final n => '$n contacts',
                        },
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.emergencyContacts,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              ..._buildInsurance(s.safety.insurance),
              const SectionHeader('Riding safely'),
              for (final (icon, tip) in SafetyScreen.tips)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icon, color: AppColors.primary),
                  title: Text(tip),
                ),
              ..._buildIncidents(s.safety.incidents),
            ],
          );
        },
      ),
    );
  }

  Widget _build112Card() {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      borderColor: AppColors.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('In an emergency', style: textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Call 112 for police, fire or ambulance. This opens your '
            "phone's dialer with 112 filled in; it doesn't place the call "
            'for you.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Call 112',
            icon: Icons.call_rounded,
            variant: ButtonVariant.destructive,
            onPressed: () => call112(context),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAdvisory() {
    final now = context.services.clock.now();
    final raining = context.services.incentives.incentives.any(
      (i) =>
          i.type == IncentiveType.rainBonus &&
          i.statusAt(now) == IncentiveStatus.active,
    );
    if (!raining) return const [];
    return [
      AppCard(
        color: AppColors.info.withValues(alpha: 0.08),
        borderColor: AppColors.info,
        child: const Row(
          children: [
            Icon(Icons.thunderstorm_outlined, color: AppColors.info),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Rain in your zone. Roads are slippery: ride slower, keep '
                'your distance and avoid waterlogged underpasses.',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
    ];
  }

  List<Widget> _buildShareTrip() {
    final trip = context.services.trip.trip;
    if (trip == null) return const [];
    final message = _shareMessage(trip.currentTask.displayId);
    return [
      AppCard(
        title: 'Share your trip',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(message),
            ),
            const SizedBox(height: AppSpacing.sm),
            const SimulatedLabel(text: 'Demo link: no location is shared'),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: 'Copy message',
              icon: Icons.copy_rounded,
              variant: ButtonVariant.outlined,
              onPressed: () => _copy(message),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
    ];
  }

  List<Widget> _buildInsurance(InsurancePolicy? policy) {
    if (policy == null) return const [];
    final textTheme = Theme.of(context).textTheme;
    return [
      const SectionHeader('Insurance'),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(policy.insurer, style: textTheme.titleSmall),
            Text(
              'Policy ${policy.policyNumber} · valid till '
              '${formatDate(policy.validUntil)}',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Accident cover ${formatPaise(policy.accidentCoverPaise)} · '
              'Hospital cover ${formatPaise(policy.hospitalCoverPaise)}',
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Active whenever you are online or on a delivery.',
              style: textTheme.bodySmall,
            ),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('How to claim'),
                children: [
                  for (final (index, step) in policy.claimSteps.indexed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: CircleAvatar(
                        radius: 12,
                        child: Text('${index + 1}'),
                      ),
                      title: Text(step),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
    ];
  }

  List<Widget> _buildIncidents(List<SafetyIncident> incidents) {
    if (incidents.isEmpty) return const [];
    final now = context.services.clock.now();
    return [
      const SizedBox(height: AppSpacing.lg),
      const SectionHeader('Your reports'),
      for (final incident in incidents)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            incident.type == SafetyIncidentType.sos
                ? Icons.sos_rounded
                : Icons.report_outlined,
            color: incident.isOpen ? AppColors.error : AppColors.textSecondary,
          ),
          title: Text('${incident.type.label} · ${incident.status.label}'),
          subtitle: Text(
            '${formatDateTime(incident.at, now: now)}\n${incident.description}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          onTap: switch (incident.ticketId) {
            final id? => () => Navigator.pushNamed(
              context,
              AppRoutes.ticket,
              arguments: id,
            ),
            null => null,
          },
        ),
    ];
  }
}
