import '../core/clock.dart';
import '../core/domain_events.dart';
import '../core/failures.dart';
import '../data/repositories/history_repository.dart';
import '../models/order.dart';
import 'loadable_controller.dart';

/// Filters offered on the order history screen.
enum HistoryFilter {
  all('All', null),
  delivered('Delivered', {OrderStatus.delivered}),
  cancelled('Cancelled', {OrderStatus.cancelled}),
  returned('Returned', {OrderStatus.returned});

  const HistoryFilter(this.label, this.statuses);

  final String label;
  final Set<OrderStatus>? statuses;
}

enum HistoryPeriod {
  all('All time'),
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This week'),
  thisMonth('This month'),
  custom('Custom range');

  const HistoryPeriod(this.label);

  final String label;
}

typedef DayRange = ({DateTime from, DateTime to});

const performanceDays = 7;

class HistoryController extends LoadableController {
  HistoryController({
    required this._repository,
    required this._clock,
    super.events,
    this.pageSize = 20,
  });

  final HistoryRepository _repository;
  final Clock _clock;
  final int pageSize;

  HistoryFilter _filter = HistoryFilter.all;
  HistoryPeriod _period = HistoryPeriod.all;
  DayRange? _customRange;
  String _search = '';
  List<DeliveryTask> _items = const [];
  List<DeliveryTask> _recent = const [];
  HistorySummary? _summary;
  HistorySummary? _filtered;
  HistorySummary? _lastWeek;
  int _page = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  String? _loadMoreError;

  HistoryFilter get filter => _filter;

  HistoryPeriod get period => _period;

  /// Inclusive first and last day of a custom range.
  DayRange? get customRange => _customRange;

  String get search => _search;

  bool get hasFilters =>
      _filter != HistoryFilter.all ||
      _period != HistoryPeriod.all ||
      _search.isNotEmpty;

  List<DeliveryTask> get items => _items;

  /// The latest few delivered orders, for the dashboard.
  List<DeliveryTask> get recent => _recent;

  /// Totals across all orders, independent of the filter.
  HistorySummary? get summary => _summary;

  /// Totals for the current filters, including per-day totals.
  HistorySummary? get filteredSummary => _filtered;

  /// Totals for the last [performanceDays] days, for completion and on-time
  /// rates.
  HistorySummary? get lastWeek => _lastWeek;

  bool get hasMore => _hasMore;

  bool get isLoadingMore => _loadingMore;

  String? get loadMoreError => _loadMoreError;

  /// The time window for [period]; `to` is exclusive.
  DayRange? get window {
    final today = startOfDay(_clock.now());
    final tomorrow = today.add(const Duration(days: 1));
    return switch (_period) {
      HistoryPeriod.all => null,
      HistoryPeriod.today => (from: today, to: tomorrow),
      HistoryPeriod.yesterday => (
        from: today.subtract(const Duration(days: 1)),
        to: today,
      ),
      HistoryPeriod.thisWeek => (
        from: today.subtract(Duration(days: today.weekday - 1)),
        to: tomorrow,
      ),
      HistoryPeriod.thisMonth => (
        from: DateTime(today.year, today.month),
        to: tomorrow,
      ),
      HistoryPeriod.custom => switch (_customRange) {
        null => null,
        final range => (
          from: startOfDay(range.from),
          to: startOfDay(range.to).add(const Duration(days: 1)),
        ),
      },
    };
  }

  HistoryQuery get _query {
    final range = window;
    return HistoryQuery(
      statuses: _filter.statuses,
      from: range?.from,
      to: range?.to,
      search: _search,
    );
  }

  @override
  Future<void> fetch() async {
    final results = await Future.wait<Object>([
      _repository.fetchPage(_query, page: 0, pageSize: pageSize),
      _repository.summary(const HistoryQuery()),
      _repository.fetchPage(
        HistoryQuery(statuses: HistoryFilter.delivered.statuses),
        page: 0,
        pageSize: 3,
      ),
      _repository.summary(_query),
      _repository.summary(
        HistoryQuery(
          from: startOfDay(_clock.now())
              .subtract(Duration(days: performanceDays - 1)),
        ),
      ),
    ]);
    final page = results[0] as HistoryPage;
    _items = page.items;
    _hasMore = page.hasMore;
    _page = 0;
    _summary = results[1] as HistorySummary;
    _recent = (results[2] as HistoryPage).items;
    _filtered = results[3] as HistorySummary;
    _lastWeek = results[4] as HistorySummary;
    _loadMoreError = null;
  }

  @override
  void clearData() {
    _items = const [];
    _recent = const [];
    _summary = null;
    _filtered = null;
    _lastWeek = null;
    _page = 0;
    _hasMore = false;
    _loadMoreError = null;
  }

  @override
  bool shouldRefresh(DomainEvent event) =>
      event is OrderCompleted || event is LedgerChanged;

  Future<void> setFilter(HistoryFilter filter) async {
    if (filter == _filter) return;
    _filter = filter;
    await load();
  }

  /// [range] is required for [HistoryPeriod.custom].
  Future<void> setPeriod(HistoryPeriod period, {DayRange? range}) async {
    if (period == HistoryPeriod.custom && range == null) return;
    _period = period;
    _customRange = period == HistoryPeriod.custom ? range : null;
    await load();
  }

  Future<void> setSearch(String text) async {
    final search = text.trim();
    if (search == _search) return;
    _search = search;
    await load();
  }

  Future<void> clearFilters() async {
    _filter = HistoryFilter.all;
    _period = HistoryPeriod.all;
    _customRange = null;
    _search = '';
    await load();
  }

  Future<void> loadMore() async {
    if (!_hasMore || _loadingMore || !isReady) return;
    _loadingMore = true;
    _loadMoreError = null;
    notify();
    try {
      final next = await _repository.fetchPage(
        _query,
        page: _page + 1,
        pageSize: pageSize,
      );
      _items = [..._items, ...next.items];
      _hasMore = next.hasMore;
      _page++;
    } on AppFailure catch (failure) {
      _loadMoreError = failure.message;
    } finally {
      _loadingMore = false;
      notify();
    }
  }

  /// Any order the rider has handled, including ones on the current trip.
  Future<DeliveryTask> orderById(String orderId) =>
      _repository.fetchOrder(orderId);
}
