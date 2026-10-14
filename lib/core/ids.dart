import 'dart:math';

/// Seeded id and reference generator so the same scenario always produces the
/// same ids.
class IdGenerator {
  IdGenerator({int seed = 1}) : _random = Random(seed);

  final Random _random;
  int _counter = 0;

  String next(String prefix) => '$prefix-${++_counter}';

  /// Bank-style transaction reference, e.g. `TXN48213`.
  String reference(String prefix) => '$prefix${_random.nextInt(90000) + 10000}';
}
