/// Device state the app depends on. A live build would back this with the
/// connectivity and location plugins.
abstract interface class DeviceRepository {
  bool get networkAvailable;

  bool get locationPermissionGranted;

  /// The phone's location setting (GPS) is on.
  bool get locationServiceEnabled;

  /// Fires whenever any value changes.
  Stream<void> get changes;

  /// Shows the system permission prompt. Returns whether access was granted.
  Future<bool> requestLocationPermission();

  /// Asks the system to turn location on.
  Future<void> enableLocationService();
}
