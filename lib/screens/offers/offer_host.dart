import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/app_services.dart';
import '../../controllers/offer_controller.dart';
import '../../core/formatters.dart';
import '../../models/trip.dart';
import '../orders/open_active_order.dart';
import 'offer_sheet.dart';

/// Shows the offer sheet over whatever the rider is looking at whenever an
/// offer arrives, alerts them (sound, vibration, screen-reader
/// announcement) and reports how each offer ended.
class OfferHost extends StatefulWidget {
  const OfferHost({super.key, required this.child});

  final Widget child;

  @override
  State<OfferHost> createState() => _OfferHostState();
}

class _OfferHostState extends State<OfferHost> {
  static const missedMessage =
      "Offer missed. It won't affect your rating, but it lowers acceptance "
      'rate.';

  late final AppServices _services = context.services;
  late final StreamSubscription<OfferOutcome> _outcomes;
  Route<void>? _route;
  String? _alertedOfferId;

  @override
  void initState() {
    super.initState();
    _services.offers.addListener(_sync);
    _outcomes = _services.offers.outcomes.listen(_onOutcome);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _services.offers.removeListener(_sync);
    _outcomes.cancel();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final offer = _services.offers.offer;
    if (offer != null && offer.id != _alertedOfferId) {
      _alertedOfferId = offer.id;
      _alert();
    }
    if (offer != null && _route == null) {
      _open();
    } else if (offer == null && _route != null) {
      _close();
    }
  }

  void _alert() {
    final offers = _services.offers;
    final settings = _services.settings.settings;
    if (settings.soundAlerts) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
    if (settings.vibration) unawaited(HapticFeedback.vibrate());
    if (MediaQuery.accessibleNavigationOf(context)) offers.extendTime();
    final offer = offers.offer;
    if (offer == null) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        _announcement(offer),
        Directionality.of(context),
        assertiveness: Assertiveness.assertive,
      ),
    );
  }

  static String _announcement(DeliveryOffer offer) =>
      'New ${offer.isBatched ? 'batched ' : ''}order offer. '
      'Earn ${spokenPaise(offer.payout.totalPaise)}, '
      '${formatDistance(offer.tripDistanceM)} trip. '
      '${offer.timeoutSeconds} seconds to respond.';

  void _open() {
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      settings: const RouteSettings(name: '/offer'),
      builder: (_) => const OfferSheet(),
    );
    _route = route;
    Navigator.of(context).push(route).whenComplete(() {
      if (_route == route) _route = null;
    });
  }

  /// Closes the sheet and anything opened over it, such as the decline
  /// reasons.
  void _close() {
    final route = _route;
    _route = null;
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r == route || r.isFirst);
    if (route.isCurrent) navigator.pop();
  }

  void _onOutcome(OfferOutcome outcome) {
    if (!mounted) return;
    switch (outcome) {
      case OfferOutcome.accepted:
        if (_route != null) _close();
        unawaited(openActiveOrder(context));
      case OfferOutcome.declined:
        _showMessage('Offer declined.');
      case OfferOutcome.missed:
        _showMessage(missedMessage);
      case OfferOutcome.released:
        _showMessage('Connection lost. Offer released.');
      case OfferOutcome.withdrawn:
        break;
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
