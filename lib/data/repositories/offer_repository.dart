import '../../models/geo_point.dart';
import '../../models/trip.dart';

abstract interface class OfferRepository {
  /// Offers for a rider near [position], pushed while the stream is listened
  /// to, plus withdrawals of offers already pushed. Listen only while the
  /// rider is online and free.
  Stream<OfferEvent> watchOffers({required GeoPoint Function() position});

  /// Throws `OfferUnavailableFailure` if the offer was withdrawn, and
  /// `NotAllowedFailure` if its cash on delivery would take cash in hand
  /// over the limit.
  Future<DeliveryTrip> accept(
    DeliveryOffer offer, {
    required GeoPoint position,
  });

  Future<void> decline(
    DeliveryOffer offer,
    DeclineReason reason, {
    String? note,
  });

  Future<void> markMissed(DeliveryOffer offer);
}
