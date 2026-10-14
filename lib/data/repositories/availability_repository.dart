/// The server decides whether the rider may go online; each call is logged
/// in the activity log.
abstract interface class AvailabilityRepository {
  /// Throws `NotAllowedFailure` if the account, documents or cash in hand
  /// block going online.
  Future<void> goOnline({required String zoneId});

  /// Throws `NotAllowedFailure` during an active trip.
  Future<void> goOffline();

  /// Throws `NotAllowedFailure` during an active trip.
  Future<void> startBreak(Duration length);

  Future<void> endBreak();
}
