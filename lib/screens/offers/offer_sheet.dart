import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_services.dart';
import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../models/trip.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/countdown_ring.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/offer_details.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/slide_to_confirm.dart';

typedef DeclineChoice = ({DeclineReason reason, String? note, bool goOffline});

/// Asks why the rider is declining. Null when they go back to the offer.
Future<DeclineChoice?> showDeclineReasonSheet(BuildContext context) =>
    showAppBottomSheet<DeclineChoice>(
      context,
      title: 'Why are you declining?',
      subtitle: "Declining never affects your rating.",
      builder: (context) => const _DeclineReasonForm(),
    );

/// The full-height offer: pay, route and details, a countdown, slide to
/// accept and decline with a reason (optionally going offline too). Opened
/// by `OfferHost`; it closes when the offer is accepted, declined, missed or
/// released. Back and the close button open the decline reasons and never
/// accept.
class OfferSheet extends StatefulWidget {
  const OfferSheet({super.key});

  @override
  State<OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<OfferSheet> {
  late final AppServices _services = context.services;
  bool _choosingReason = false;

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _accept() async {
    try {
      await _services.offers.accept();
    } on OfferUnavailableFailure {
      // The sheet switches to the "no longer available" notice.
    } on AppFailure catch (failure) {
      if (mounted) _showMessage(failure.message);
    }
  }

  Future<void> _decline() async {
    if (_choosingReason) return;
    final offers = _services.offers;
    final offerId = offers.offer?.id;
    _choosingReason = true;
    final choice = await showDeclineReasonSheet(context);
    _choosingReason = false;
    if (choice == null || !mounted) return;
    if (offers.offer?.id != offerId || offers.isUnavailable) return;
    final messenger = ScaffoldMessenger.of(context);
    final availability = _services.availability;
    try {
      await offers.decline(choice.reason, note: choice.note);
      if (!choice.goOffline) return;
      await availability.goOffline();
    } on AppFailure catch (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            "Offer declined. You're offline and won't get new orders.",
          ),
        ),
      );
  }

  void _onBack() {
    final offers = _services.offers;
    if (offers.offer == null) return;
    offers.isUnavailable ? offers.dismissUnavailable() : _decline();
  }

  @override
  Widget build(BuildContext context) {
    final offers = _services.offers;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([offers, _services.wallet]),
            builder: (context, _) {
              final offer = offers.offer;
              if (offer == null) return const SizedBox.shrink();
              if (offers.isUnavailable) {
                return _Unavailable(onDismiss: offers.dismissUnavailable);
              }
              return _buildOffer(offer);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildOffer(DeliveryOffer offer) {
    final offers = _services.offers;
    final blocked = offers.acceptBlockedReason;
    final remaining = offers.remaining ?? Duration.zero;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.lg,
            0,
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: offers.isBusy ? null : _decline,
                tooltip: 'Not now',
                icon: const Icon(Icons.close_rounded),
              ),
              const Spacer(),
              const DemoBadge(),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: OfferDetails(
              key: ValueKey(offer.id),
              offer: offer,
              rider: _services.availability.position,
              warning: blocked,
              trailing: CountdownRing(
                remaining: remaining,
                total: Duration(seconds: offer.timeoutSeconds),
                size: 64,
                semanticSuffix: 'left to accept',
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.md,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (offers.hasExtraTime)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    'Extra time added for assistive technology.',
                    style: textTheme.bodySmall,
                  ),
                ),
              SlideToConfirm(
                label: 'Slide to accept',
                enabled: blocked == null && !offers.isBusy,
                onConfirmed: _accept,
              ),
              if (blocked != null) DisabledReason(blocked),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: offers.isBusy ? null : _decline,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Decline'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.person_off_outlined,
              size: 56,
              color: AppColors.textGrey,
            ),
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              liveRegion: true,
              child: Text(
                'This order is no longer available',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "Another partner accepted it first. This doesn't affect your "
              'acceptance rate.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(label: 'Dismiss', onPressed: onDismiss),
          ],
        ),
      ),
    );
  }
}

class _DeclineReasonForm extends StatefulWidget {
  const _DeclineReasonForm();

  @override
  State<_DeclineReasonForm> createState() => _DeclineReasonFormState();
}

class _DeclineReasonFormState extends State<_DeclineReasonForm> {
  DeclineReason? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit({required bool goOffline}) {
    final reason = _reason;
    if (reason == null) return;
    final note = _note.text.trim();
    Navigator.pop<DeclineChoice>(context, (
      reason: reason,
      note: reason == DeclineReason.other && note.isNotEmpty ? note : null,
      goOffline: goOffline,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<DeclineReason>(
          groupValue: _reason,
          onChanged: (reason) => setState(() => _reason = reason),
          child: Column(
            children: [
              for (final reason in DeclineReason.values)
                RadioListTile<DeclineReason>(
                  value: reason,
                  title: Text(reason.label),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        if (_reason == DeclineReason.other) ...[
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: 'Note (optional)',
            hint: 'Tell us more',
            icon: Icons.edit_note_rounded,
            controller: _note,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Decline order',
          variant: ButtonVariant.destructive,
          onPressed: _reason == null ? null : () => _submit(goOffline: false),
        ),
        const SizedBox(height: AppSpacing.sm),
        PrimaryButton(
          label: 'Decline and go offline',
          variant: ButtonVariant.outlined,
          onPressed: _reason == null ? null : () => _submit(goOffline: true),
        ),
        if (_reason == null) const DisabledReason('Choose a reason first.'),
      ],
    );
  }
}
