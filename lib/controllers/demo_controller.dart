import 'package:flutter/foundation.dart';

import '../data/repositories/demo_controls.dart';
import '../models/money.dart';
import '../models/trip.dart';
import '../services/image_service.dart';
import '../services/location/location_source.dart';
import 'demo_scenarios.dart';
import 'navigation_controller.dart';

/// Backs the Demo Controls screen: account state, blockers, zone demand,
/// network and location toggles, latency, clock speed, failure injection
/// and data reset.
class DemoController extends ChangeNotifier {
  DemoController(this._controls, {this._simulation, this._navigation});

  /// Demo scenario 12: an expired licence plus this much cash in hand.
  static const blockedCashPaise = 215000;

  /// Demo scenario 24: close enough to the limit that most COD offers
  /// can't be accepted.
  static const nearLimitCashPaise = 185000;

  final DemoControls _controls;
  final LocationSimulation? _simulation;
  final NavigationController? _navigation;

  DemoAccount get account => _controls.account;

  void useAccount(DemoAccount account) {
    _controls.useAccount(account);
    notifyListeners();
  }

  void approveVerification() => _controls.approveVerification();

  void rejectVerification() => _controls.rejectVerification();

  void reinstateAccount() => _controls.reinstateAccount();

  void expireDocument() => _controls.expireDocument();

  void setCashInHand(int paise) => _controls.setCashInHand(paise);

  /// Licence expired and cash in hand over the limit: two online blockers.
  void blockGoingOnline() {
    _controls.expireDocument();
    _controls.setCashInHand(blockedCashPaise);
  }

  /// False when the rider isn't listening for offers (offline, on a break
  /// or on a trip).
  bool sendOffer(OfferRequest request) => _controls.sendOffer(request);

  bool get takeNextOffer => _controls.takeNextOffer;

  set takeNextOffer(bool value) {
    _controls.takeNextOffer = value;
    notifyListeners();
  }

  DemandOverride get demandOverride => _controls.demandOverride;

  set demandOverride(DemandOverride value) {
    _controls.demandOverride = value;
    notifyListeners();
  }

  bool get networkAvailable => _controls.networkAvailable;

  set networkAvailable(bool value) {
    _controls.networkAvailable = value;
    notifyListeners();
  }

  bool get locationPermissionGranted => _controls.locationPermissionGranted;

  set locationPermissionGranted(bool value) {
    _controls.locationPermissionGranted = value;
    notifyListeners();
  }

  bool get locationServiceEnabled => _controls.locationServiceEnabled;

  set locationServiceEnabled(bool value) {
    _controls.locationServiceEnabled = value;
    notifyListeners();
  }

  bool get movementPaused => _simulation?.isPaused ?? false;

  set movementPaused(bool value) {
    final simulation = _simulation;
    if (simulation == null) return;
    value ? simulation.pause() : simulation.resume();
    notifyListeners();
  }

  /// Puts the rider at the end of the current leg ("Jump to store" while
  /// heading to pickup).
  void jumpToNextStop() {
    final navigation = _navigation;
    if (navigation != null) {
      navigation.jumpToDestination();
    } else {
      _simulation?.jumpToEnd();
    }
  }

  /// Cancels the active trip before pickup. Returns false when there is no
  /// trip that can be cancelled.
  bool cancelTrip(CancelledBy by) => _controls.cancelActiveTrip(
    by,
    travelledM: _navigation?.travelledM.round() ?? 0,
  );

  /// Ends the current store wait at once (logged as skipped).
  bool skipStoreWait() => _controls.skipStoreWait();

  /// How the scripted customer reacts to calls, chat and location requests.
  CustomerResponse get customerResponse => _controls.customerResponse;

  set customerResponse(CustomerResponse value) {
    _controls.customerResponse = value;
    notifyListeners();
  }

  bool get upiPaymentFails => _controls.upiPaymentFails;

  set upiPaymentFails(bool value) {
    _controls.upiPaymentFails = value;
    notifyListeners();
  }

  bool get tipAfterDelivery => _controls.tipAfterDelivery;

  set tipAfterDelivery(bool value) {
    _controls.tipAfterDelivery = value;
    notifyListeners();
  }

  /// The code the current customer would read out; demo hint only.
  String? get customerOtp => _controls.customerOtp;

  bool get rejectNextDocument => _controls.rejectNextDocument;

  set rejectNextDocument(bool value) {
    _controls.rejectNextDocument = value;
    notifyListeners();
  }

  bool get payoutFails => _controls.payoutFails;

  set payoutFails(bool value) {
    _controls.payoutFails = value;
    notifyListeners();
  }

  bool get raining => _controls.raining;

  set raining(bool value) {
    _controls.raining = value;
    notifyListeners();
  }

  Payout? runWeeklyPayout() {
    final payout = _controls.runWeeklyPayout();
    notifyListeners();
    return payout;
  }

  bool get gpsLost => _simulation?.signalLost ?? false;

  /// Demo scenario 20: no GPS fixes for 20 s, then recovery.
  void loseGps() {
    _simulation?.loseSignal();
    notifyListeners();
  }

  Duration get latency => _controls.latency;

  set latency(Duration value) {
    _controls.latency = value;
    notifyListeners();
  }

  double get speed => _controls.speed;

  set speed(double value) {
    _controls.speed = value;
    notifyListeners();
  }

  void failNext(OperationType operation) => _controls.failNext(operation);

  /// The next request that needs the server fails with a server error.
  void failNextRequest() => _controls.failNextRequest();

  /// The next camera or gallery pick fails.
  void failNextPhoto() => ImageService.failNext = true;

  DemoScenario? _scenario;

  /// The scenario last prepared with [runScenario].
  DemoScenario? get scenario => _scenario;

  /// Resets the demo data and applies the scenario's setup.
  void runScenario(DemoScenario scenario) {
    _controls
      ..resetData()
      ..speed = scenario.usesTrip ? 5 : 1;
    switch (scenario) {
      case DemoScenario.codByUpi:
        _controls.upiPaymentFails = true;
      case DemoScenario.customerUnreachable || DemoScenario.batchWithFailure:
        _controls.customerResponse = CustomerResponse.noAnswer;
      case DemoScenario.wrongAddress:
        _controls.customerResponse = CustomerResponse.sharesLocation;
      case DemoScenario.blockedOnline:
        blockGoingOnline();
      case DemoScenario.payoutFailure:
        _controls.payoutFails = true;
      case DemoScenario.rainMode:
        _controls.raining = true;
      case DemoScenario.cashLimitNear:
        _controls.setCashInHand(nearLimitCashPaise);
      default:
        break;
    }
    _scenario = scenario;
    notifyListeners();
  }

  void resetData() {
    _controls.resetData();
    _scenario = null;
    notifyListeners();
  }
}
