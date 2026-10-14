import 'dart:async';
import 'dart:math';

import '../../core/failures.dart';
import '../repositories/demo_controls.dart';

export '../repositories/demo_controls.dart' show OperationType;

/// Simulated latency, network state and failure injection shared by every
/// demo repository.
class DemoEngine {
  DemoEngine({
    this.latency = const Duration(milliseconds: 300),
    this.jitter = const Duration(milliseconds: 150),
    int seed = 7,
  }) : _random = Random(seed);

  Duration latency;
  Duration jitter;
  bool networkAvailable = true;

  final Random _random;
  final Set<OperationType> _failNext = {};

  /// The next call of [operation] fails with a [ServerFailure].
  void failNext(OperationType operation) => _failNext.add(operation);

  /// The next server request of any kind fails.
  bool failNextRequest = false;

  Future<T> run<T>(OperationType operation, FutureOr<T> Function() body) async {
    if (latency > Duration.zero) {
      final extra = jitter.inMilliseconds == 0
          ? 0
          : _random.nextInt(jitter.inMilliseconds);
      await Future<void>.delayed(latency + Duration(milliseconds: extra));
    } else {
      await Future<void>.value();
    }
    if (!networkAvailable && operation.requiresServer) {
      throw const NetworkUnavailableFailure();
    }
    if (_failNext.remove(operation)) throw const ServerFailure();
    if (failNextRequest && operation.requiresServer) {
      failNextRequest = false;
      throw const ServerFailure();
    }
    return body();
  }
}
