import '../../models/money.dart';
import '../../models/order.dart';
import '../../models/trip.dart';

/// Operations whose next call can be made to fail from Demo Controls.
enum OperationType {
  signIn,
  restoreSession,
  signUp,
  loadProfile,
  saveProfile,
  verification,
  setAvailability,
  fetchOffer,
  acceptOffer,
  declineOffer,
  loadTrip,
  updateTrip,
  completeDelivery,
  collectUpi,
  loadHistory,
  loadEarnings,
  loadWallet,
  withdraw,
  depositCash,
  loadIncentives,
  loadZones,
  loadNotifications,
  updateNotifications,
  loadActivity,
  loadSupport,
  createTicket,
  sendSupportMessage,
  loadSafety,
  sos,
  loadSettings,
  saveSettings,
  planRoute;

  /// Settings, the saved session, offline routing and the saved trip are
  /// device-local; trip steps and SOS alerts are queued while offline (plan
  /// 3.8.1). Everything else needs the server.
  bool get requiresServer => !const {
    restoreSession,
    loadSettings,
    saveSettings,
    planRoute,
    loadTrip,
    updateTrip,
    completeDelivery,
    loadSafety,
    sos,
  }.contains(this);
}

/// Account states the demo can sign in as.
enum DemoAccount {
  verified('Verified partner', 'Ready to deliver, with 60 days of history'),
  newSignup('New sign-up', 'Needs vehicle, documents and bank details'),
  pending('Verification pending', 'Documents submitted and under review'),
  rejectedDocument('Rejected document', 'Aadhaar card needs a new upload'),
  suspended('Suspended', 'Account on hold; only Help is available');

  const DemoAccount(this.label, this.description);

  final String label;
  final String description;
}

/// Zone demand: follow the daily schedule (lunch 12–3 PM and dinner
/// 7–11 PM are busy) or force a level.
enum DemandOverride {
  schedule('Follow schedule'),
  high('Force high demand'),
  surge('Force very high demand'),
  low('Force low demand');

  const DemandOverride(this.label);

  final String label;
}

/// How the demo customer reacts to calls, chats and location requests.
enum CustomerResponse {
  answers('Answers the first call'),
  noAnswer('Never answers'),
  sharesLocation('Answers and shares a new location');

  const CustomerResponse(this.label);

  final String label;
}

/// The shape of an offer sent from Demo Controls.
class OfferRequest {
  const OfferRequest({
    this.batched = false,
    this.timeoutSeconds = 30,
    this.payment,
  });

  /// Two drops from the same store.
  final bool batched;
  final int timeoutSeconds;

  /// Forces cash on delivery or prepaid; random when null.
  final PaymentMode? payment;
}

/// Simulation knobs exposed to the Demo Controls screen. Only the demo
/// implementation exists; a live build has no demo controls.
abstract interface class DemoControls {
  DemoAccount get account;

  /// Rebuilds demo data with the partner in the given account state.
  void useAccount(DemoAccount account);

  /// Pending verification passes; all pending documents become verified.
  void approveVerification();

  /// Pending verification fails with the Aadhaar card rejected.
  void rejectVerification();

  /// A suspended account becomes verified again.
  void reinstateAccount();

  /// The driving licence (or Aadhaar for vehicles without one) expires
  /// today.
  void expireDocument();

  /// Adds COD cash or deposits so cash in hand equals [paise].
  void setCashInHand(int paise);

  /// Pushes an offer to a rider who is online and free. Returns false when
  /// nobody is listening for offers.
  bool sendOffer(OfferRequest request);

  /// The next offer is taken by another partner a few seconds after it
  /// appears.
  bool get takeNextOffer;

  set takeNextOffer(bool value);

  DemandOverride get demandOverride;

  set demandOverride(DemandOverride value);

  bool get networkAvailable;

  set networkAvailable(bool value);

  bool get locationPermissionGranted;

  set locationPermissionGranted(bool value);

  bool get locationServiceEnabled;

  set locationServiceEnabled(bool value);

  Duration get latency;

  set latency(Duration value);

  double get speed;

  set speed(double value);

  void failNext(OperationType operation);

  /// The next request that needs the server fails, whatever it is.
  void failNextRequest();

  CustomerResponse get customerResponse;

  set customerResponse(CustomerResponse value);

  /// The next UPI payments come back as failed.
  bool get upiPaymentFails;

  set upiPaymentFails(bool value);

  /// The customer adds a ₹10 tip about 10 s after each delivery.
  bool get tipAfterDelivery;

  set tipAfterDelivery(bool value);

  /// The delivery OTP the current customer would read out, if any.
  String? get customerOtp;

  /// The next re-uploaded document is rejected after review instead of
  /// verified.
  bool get rejectNextDocument;

  set rejectNextDocument(bool value);

  /// Payouts requested from now on fail at the bank.
  bool get payoutFails;

  set payoutFails(bool value);

  /// Rain in the city: a rain bonus runs for two hours while on.
  bool get raining;

  set raining(bool value);

  /// Pays out the withdrawable balance as the Monday 06:00 run would.
  /// Returns null when it is below the minimum withdrawal.
  Payout? runWeeklyPayout();

  /// Cancels the active trip (plan 3.8.3). Before pickup the whole trip
  /// ends, and [travelledM] decides compensation while heading to the store.
  /// After pickup only a customer cancels, and only the current drop: it is
  /// returned or disposed of. Returns false when nothing can be cancelled.
  bool cancelActiveTrip(CancelledBy by, {int travelledM = 0});

  /// Ends the current store wait (order not ready or being fixed) at once.
  /// Returns false when the rider isn't waiting.
  bool skipStoreWait();

  /// Rebuilds all demo data from the seed.
  void resetData();
}
