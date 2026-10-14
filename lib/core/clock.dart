/// Source of the current time. Injected everywhere so countdowns, ETAs and
/// timestamps are deterministic in demos and tests.
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Runs from the real time at creation, optionally faster (1×, 2×, 5×) so
/// demo waits and payouts can be shown quickly.
class DemoClock implements Clock {
  DemoClock({this._speed = 1}) {
    _anchorDemo = DateTime.now();
    _stopwatch.start();
  }

  final Stopwatch _stopwatch = Stopwatch();
  late DateTime _anchorDemo;
  Duration _anchorElapsed = Duration.zero;
  double _speed;

  double get speed => _speed;

  set speed(double value) {
    _anchorDemo = now();
    _anchorElapsed = _stopwatch.elapsed;
    _speed = value;
  }

  @override
  DateTime now() {
    final realElapsed = _stopwatch.elapsed - _anchorElapsed;
    return _anchorDemo.add(realElapsed * _speed);
  }
}

/// Manually controlled clock for tests.
class FakeClock implements Clock {
  FakeClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration duration) => _now = _now.add(duration);

  void set(DateTime value) => _now = value;
}

DateTime startOfDay(DateTime time) => DateTime(time.year, time.month, time.day);
