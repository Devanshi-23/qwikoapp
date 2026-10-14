import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/device_repository.dart';

/// Network reachability and location permission, for blockers and the
/// connectivity banner.
class DeviceController extends ChangeNotifier {
  DeviceController(this._repository) {
    _subscription = _repository.changes.listen((_) => notifyListeners());
  }

  final DeviceRepository _repository;
  late final StreamSubscription<void> _subscription;

  bool get networkAvailable => _repository.networkAvailable;

  bool get locationPermissionGranted => _repository.locationPermissionGranted;

  bool get locationServiceEnabled => _repository.locationServiceEnabled;

  /// A position fix is possible: permission granted and location on.
  bool get canLocate => locationPermissionGranted && locationServiceEnabled;

  Future<bool> requestLocationPermission() async {
    final granted = await _repository.requestLocationPermission();
    notifyListeners();
    return granted;
  }

  Future<void> enableLocationService() async {
    await _repository.enableLocationService();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
