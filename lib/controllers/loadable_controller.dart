import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/domain_events.dart';
import '../core/failures.dart';

enum LoadStatus { idle, loading, ready, error }

/// Base for controllers that load data from a repository: tracks load state
/// and errors, and refreshes quietly when a relevant domain event arrives.
abstract class LoadableController extends ChangeNotifier {
  LoadableController({DomainEventBus? events}) {
    _subscription = events?.stream.listen(_onEvent);
  }

  StreamSubscription<DomainEvent>? _subscription;
  LoadStatus _status = LoadStatus.idle;
  String? _error;
  bool _disposed = false;
  int _generation = 0;

  LoadStatus get status => _status;

  /// Message for the last failed load or refresh, if any.
  String? get error => _error;

  bool get isLoading => _status == LoadStatus.loading;

  bool get isReady => _status == LoadStatus.ready;

  /// Fetches data and stores it on the controller. Throws on failure.
  @protected
  Future<void> fetch();

  /// Drops loaded data, for sign-out and data resets.
  @protected
  void clearData();

  /// Whether [event] makes the loaded data stale.
  @protected
  bool shouldRefresh(DomainEvent event) => false;

  Future<void> load() async {
    final generation = ++_generation;
    _status = LoadStatus.loading;
    _error = null;
    notify();
    try {
      await fetch();
      if (generation != _generation) return;
      _status = LoadStatus.ready;
    } catch (error, stack) {
      if (generation != _generation) return;
      _reportUnexpected(error, stack);
      _status = LoadStatus.error;
      _error = failureMessage(error);
    }
    notify();
  }

  Future<void> ensureLoaded() async {
    if (_status == LoadStatus.idle || _status == LoadStatus.error) {
      await load();
    }
  }

  /// Reloads while keeping current data on screen. Does nothing if never
  /// loaded.
  Future<void> refresh() async {
    if (_status == LoadStatus.idle) return;
    final generation = ++_generation;
    try {
      await fetch();
      if (generation != _generation) return;
      _status = LoadStatus.ready;
      _error = null;
    } catch (error, stack) {
      if (generation != _generation) return;
      _reportUnexpected(error, stack);
      _error = failureMessage(error);
    }
    notify();
  }

  /// Marks data supplied from elsewhere (e.g. a sign-in response) as loaded.
  @protected
  void markReady() {
    _generation++;
    _status = LoadStatus.ready;
    _error = null;
  }

  void reset() {
    _generation++;
    _status = LoadStatus.idle;
    _error = null;
    clearData();
    notify();
  }

  void _onEvent(DomainEvent event) {
    if (event is DataReset) {
      final wasLoaded = _status != LoadStatus.idle;
      reset();
      if (wasLoaded) load();
    } else if (shouldRefresh(event)) {
      refresh();
    }
  }

  void _reportUnexpected(Object error, StackTrace stack) {
    if (error is AppFailure) return;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'controllers',
      ),
    );
  }

  @protected
  void notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}

/// Runs [action] while [setBusy] reports progress, so screens can disable
/// buttons during writes.
Future<T> runBusy<T>(
  void Function(bool busy) setBusy,
  Future<T> Function() action,
) async {
  setBusy(true);
  try {
    return await action();
  } finally {
    setBusy(false);
  }
}
