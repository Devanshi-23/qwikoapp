import '../../models/geo_point.dart';
import '../../models/media_ref.dart';
import '../../models/order.dart';
import '../../models/store_issue.dart';
import '../../models/trip.dart';

/// Result of a delivery OTP check.
typedef OtpCheck = ({bool verified, int attemptsLeft, DateTime? lockedUntil});

abstract interface class TripRepository {
  /// The trip saved on this device; works offline.
  Future<DeliveryTrip?> activeTrip();

  /// Moves the current task (or all tasks for shared pickup steps) to [next].
  /// Arriving at the store needs [position] inside the store geofence.
  /// Steps taken offline are queued and synced on reconnect.
  Future<DeliveryTrip> advance(
    String tripId,
    OrderStatus next, {
    GeoPoint? position,
  });

  /// Pickup checklist and bag. Kept on the device, so these work offline.
  Future<DeliveryTrip> setItemChecked(
    String tripId,
    ItemRef item, {
    required bool checked,
  });

  Future<DeliveryTrip> checkAllItems(String tripId);

  Future<DeliveryTrip> setHandlingChecked(
    String tripId,
    OfferTag tag, {
    required bool checked,
  });

  Future<DeliveryTrip> setBag(
    String tripId, {
    required bool sealed,
    MediaRef? photo,
  });

  Future<StoreIssueResult> reportStoreIssue(
    String tripId,
    StoreIssueRequest request,
  );

  /// Leaves after waiting [DeliveryTrip.longWait] for an order that still
  /// isn't ready. The trip becomes cancelled with compensation.
  Future<DeliveryTrip> cancelAfterLongWait(String tripId);

  /// The rider acknowledges a cancelled trip: compensation is credited and
  /// the trip ends.
  Future<TripCancellation> closeCancelledTrip(String tripId);

  /// A simulated masked call to the current customer, logged on the order.
  Future<({bool answered, Duration duration})> callCustomer(String tripId);

  /// Sends a chat message (up to 200 characters) to the current customer.
  Future<DeliveryTrip> sendChat(String tripId, String text);

  /// "Can't find address": the customer shares their exact location and
  /// the drop is re-routed.
  Future<DeliveryTrip> requestCustomerLocation(String tripId);

  /// "Can't find address": raises a support ticket; returns its reference.
  Future<String> contactSupportAboutAddress(String tripId);

  /// Ends the current drop without delivery. Needs the call attempts and
  /// door wait unless the customer [refused] the order. Returns the trip on
  /// its next leg, or null when it is over.
  Future<DeliveryTrip?> markUndeliverable(
    String tripId, {
    required String reason,
    bool refused = false,
  });

  /// Hands returned orders back at the store (inside the store geofence).
  Future<({List<DeliveryTask> returned, DeliveryTrip? trip})> returnedToStore(
    String tripId, {
    GeoPoint? position,
  });

  /// Clears the trip notice; ends the trip if nothing else is left.
  Future<DeliveryTrip?> dismissNotice(String tripId);

  /// Checks the code the customer reads out. Three wrong codes lock entry
  /// for 30 s. Works offline: the code is on the order.
  Future<OtpCheck> verifyDeliveryOtp(String tripId, String code);

  /// Simulated UPI collection for the current drop. Needs a connection.
  /// Returns false when the payment failed.
  Future<bool> collectUpi(String tripId, int amountPaise);

  /// Completes the current drop. Returns the delivered task and the trip on
  /// its next leg, which is `null` when the trip is over.
  Future<({DeliveryTask delivered, DeliveryTrip? trip})> completeDelivery(
    String tripId,
    DeliveryProof proof,
  );
}
