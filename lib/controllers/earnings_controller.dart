import '../core/clock.dart';
import '../core/domain_events.dart';
import '../data/repositories/earnings_repository.dart';
import '../models/money.dart';
import 'loadable_controller.dart';

enum EarningsPeriod {
  day('Day'),
  week('Week'),
  month('Month');

  const EarningsPeriod(this.label);

  final String label;
}

/// One bar of the earnings chart.
class EarningsBucket {
  const EarningsBucket({
    required this.from,
    required this.label,
    required this.spokenLabel,
    required this.totalPaise,
    this.isCurrent = false,
  });

  final DateTime from;
  final String label;
  final String spokenLabel;
  final int totalPaise;
  final bool isCurrent;
}

/// What one order earned in the period.
class OrderEarnings {
  const OrderEarnings({
    required this.orderId,
    required this.label,
    required this.at,
    required this.totalPaise,
  });

  final String orderId;
  final String label;
  final DateTime at;
  final int totalPaise;
}

/// Earnings for a day, week or month, all computed from ledger entries.
class EarningsController extends LoadableController {
  EarningsController({
    required this._repository,
    required this._clock,
    super.events,
  });

  /// How far back the rider can page.
  static const historyDays = 90;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final EarningsRepository _repository;
  final Clock _clock;

  EarningsPeriod _period = EarningsPeriod.week;

  /// How many periods back from the current one; 0 is today, this week or
  /// this month.
  int _offset = 0;
  List<EarningEntry> _entries = const [];
  List<EarningEntry> _todayEntries = const [];

  EarningsPeriod get period => _period;

  int get offset => _offset;

  /// Credits in the period, newest first. Payouts excluded.
  List<EarningEntry> get entries => _entries;

  /// Start (inclusive) and end (exclusive) of the period shown.
  ({DateTime from, DateTime to}) get range => _rangeFor(_period, _offset);

  bool get canGoNext => _offset > 0;

  bool get canGoPrevious {
    final earliest = startOfDay(_clock.now())
        .subtract(const Duration(days: historyDays));
    return range.from.isAfter(earliest);
  }

  String get rangeLabel {
    final (:from, :to) = range;
    final last = to.subtract(const Duration(days: 1));
    return switch (_period) {
      EarningsPeriod.day => switch (_offset) {
        0 => 'Today',
        1 => 'Yesterday',
        _ => '${_weekdays[from.weekday - 1]}, ${from.day} ${_short(from)}',
      },
      EarningsPeriod.week => switch (_offset) {
        0 => 'This week',
        1 => 'Last week',
        _ =>
          from.month == last.month
              ? '${from.day}–${last.day} ${_short(from)}'
              : '${from.day} ${_short(from)} – ${last.day} ${_short(last)}',
      },
      EarningsPeriod.month => '${_months[from.month - 1]} ${from.year}',
    };
  }

  int get totalPaise => _entries.fold(0, (sum, e) => sum + e.amountPaise);

  /// Distinct orders paid in the period.
  int get orderCount => _orderIds(_entries).length;

  int get todayPaise => _todayEntries.fold(0, (sum, e) => sum + e.amountPaise);

  int get todayOrders => _orderIds(_todayEntries).length;

  /// Period total per earning type, largest first.
  List<(EarningType, int)> get breakdown {
    final totals = <EarningType, int>{};
    for (final entry in _entries) {
      totals.update(
        entry.type,
        (sum) => sum + entry.amountPaise,
        ifAbsent: () => entry.amountPaise,
      );
    }
    return totals.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// Per-order totals, newest first. Incentives and adjustments that aren't
  /// tied to an order are left out.
  List<OrderEarnings> get orders {
    final byOrder = <String, OrderEarnings>{};
    for (final entry in _entries) {
      final orderId = entry.orderId;
      if (orderId == null) continue;
      final current = byOrder[orderId];
      byOrder[orderId] = OrderEarnings(
        orderId: orderId,
        label: entry.label.split(' · ').last,
        at: current == null || entry.at.isBefore(current.at)
            ? entry.at
            : current.at,
        totalPaise: (current?.totalPaise ?? 0) + entry.amountPaise,
      );
    }
    return byOrder.values.toList()..sort((a, b) => b.at.compareTo(a.at));
  }

  /// Chart bars: 4-hour blocks for a day, days for a week or month.
  List<EarningsBucket> get buckets {
    final (:from, :to) = range;
    final now = _clock.now();
    final today = startOfDay(now);
    final starts = switch (_period) {
      EarningsPeriod.day => [
        for (var h = 0; h < 24; h += 4) from.add(Duration(hours: h)),
      ],
      _ => [
        for (
          var day = from;
          day.isBefore(to);
          day = DateTime(day.year, day.month, day.day + 1)
        )
          day,
      ],
    };
    return [
      for (var i = 0; i < starts.length; i++)
        _bucket(
          starts[i],
          i + 1 < starts.length ? starts[i + 1] : to,
          isCurrent: _period == EarningsPeriod.day
              ? !now.isBefore(starts[i]) &&
                    (i + 1 == starts.length || now.isBefore(starts[i + 1]))
              : starts[i] == today,
        ),
    ];
  }

  EarningsBucket _bucket(
    DateTime from,
    DateTime to, {
    required bool isCurrent,
  }) {
    final total = _entries
        .where((e) => !e.at.isBefore(from) && e.at.isBefore(to))
        .fold(0, (sum, e) => sum + e.amountPaise);
    final (label, spoken) = switch (_period) {
      EarningsPeriod.day => (
        _hour(from.hour),
        '${_hour(from.hour)} to ${_hour(to.hour == 0 ? 24 : to.hour)}',
      ),
      EarningsPeriod.week => (
        _weekdays[from.weekday - 1],
        '${_weekdays[from.weekday - 1]} ${from.day} ${_short(from)}',
      ),
      EarningsPeriod.month => (
        from.day == 1 || from.day % 5 == 0 ? '${from.day}' : '',
        '${from.day} ${_short(from)}',
      ),
    };
    return EarningsBucket(
      from: from,
      label: label,
      spokenLabel: spoken,
      totalPaise: total,
      isCurrent: isCurrent,
    );
  }

  static String _hour(int hour) => switch (hour % 24) {
    0 => '12a',
    12 => '12p',
    final h when h < 12 => '${h}a',
    final h => '${h - 12}p',
  };

  static String _short(DateTime date) =>
      _months[date.month - 1].substring(0, 3);

  static Set<String> _orderIds(List<EarningEntry> entries) => {
    for (final e in entries)
      if (e.type == EarningType.orderPay && e.orderId != null) e.orderId!,
  };

  ({DateTime from, DateTime to}) _rangeFor(EarningsPeriod period, int offset) {
    final today = startOfDay(_clock.now());
    switch (period) {
      case EarningsPeriod.day:
        final from = DateTime(today.year, today.month, today.day - offset);
        return (from: from, to: DateTime(from.year, from.month, from.day + 1));
      case EarningsPeriod.week:
        final from = DateTime(
          today.year,
          today.month,
          today.day - (today.weekday - 1) - 7 * offset,
        );
        return (from: from, to: DateTime(from.year, from.month, from.day + 7));
      case EarningsPeriod.month:
        final from = DateTime(today.year, today.month - offset);
        return (from: from, to: DateTime(from.year, from.month + 1));
    }
  }

  Future<void> setPeriod(EarningsPeriod period) async {
    if (period == _period) return;
    _period = period;
    _offset = 0;
    await load();
  }

  Future<void> previous() async {
    if (!canGoPrevious) return;
    _offset++;
    await load();
  }

  Future<void> next() async {
    if (!canGoNext) return;
    _offset--;
    await load();
  }

  @override
  Future<void> fetch() async {
    final today = _rangeFor(EarningsPeriod.day, 0);
    final (:from, :to) = range;
    final results = await Future.wait([
      _repository.entries(from: from, to: to),
      _repository.entries(from: today.from, to: today.to),
    ]);
    _entries = results[0].where((e) => e.type != EarningType.payout).toList();
    _todayEntries = results[1]
        .where((e) => e.type != EarningType.payout)
        .toList();
  }

  @override
  void clearData() {
    _entries = const [];
    _todayEntries = const [];
  }

  @override
  bool shouldRefresh(DomainEvent event) => event is LedgerChanged;
}
