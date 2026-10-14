import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../controllers/history_controller.dart';
import '../../controllers/loadable_controller.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../models/order.dart';
import '../../utils/app_colors.dart';
import '../../widgets/order_card.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/state_views.dart';

/// Shown inside the Orders tab of the home screen.
class OrderHistoryView extends StatefulWidget {
  const OrderHistoryView({super.key, this.onOpenOrder, this.selectedOrderId});

  /// Shows the order beside the list (two-pane) instead of pushing it.
  final ValueChanged<String>? onOpenOrder;
  final String? selectedOrderId;

  @override
  State<OrderHistoryView> createState() => _OrderHistoryViewState();
}

class _OrderHistoryViewState extends State<OrderHistoryView> {
  late final HistoryController _history = context.services.history;
  late final _searchController = TextEditingController(text: _history.search);
  int _resets = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _rangeLabel(DayRange range) {
    final now = context.services.clock.now();
    return '${formatDate(range.from, now: now)} – '
        '${formatDate(range.to, now: now)}';
  }

  String _emptyTitle() {
    final status = _history.filter == HistoryFilter.all
        ? 'orders'
        : '${_history.filter.label.toLowerCase()} orders';
    if (_history.search.isNotEmpty) {
      return 'No $status match "${_history.search}"';
    }
    return switch (_history.period) {
      HistoryPeriod.all => 'No $status',
      HistoryPeriod.custom => 'No $status in this range',
      final period => 'No $status ${period.label.toLowerCase()}',
    };
  }

  Future<void> _clearFilters() async {
    _searchController.clear();
    await _history.clearFilters();
  }

  Future<void> _choosePeriod(HistoryPeriod period) async {
    if (period != HistoryPeriod.custom) {
      await _history.setPeriod(period);
      return;
    }
    final now = context.services.clock.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 90)),
      lastDate: now,
      currentDate: now,
    );
    if (picked == null) {
      // Puts the dropdown back on the period still in use.
      setState(() => _resets++);
      return;
    }
    await _history.setPeriod(
      period,
      range: (from: picked.start, to: picked.end),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _history.ensureLoaded();
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 400) _history.loadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _history,
      builder: (context, _) => NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: RefreshIndicator(
          onRefresh: _history.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: _buildContent(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent() {
    final summary = _history.filteredSummary;
    final orders = _history.items;
    final loadMoreError = _history.loadMoreError;

    return [
      Semantics(
        header: true,
        child: Text(
          'My Orders',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: StatTile(
              value: summary == null
                  ? StatTile.placeholder
                  : '${summary.deliveredCount}',
              label: 'Delivered',
              valueColor: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              value: summary == null
                  ? StatTile.placeholder
                  : formatPaise(summary.earnedPaise),
              semanticValue: summary == null
                  ? null
                  : spokenPaise(summary.earnedPaise),
              label: 'Earned',
              valueColor: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              value: summary == null
                  ? StatTile.placeholder
                  : formatDistance(summary.distanceM),
              label: 'Distance',
              valueColor: AppColors.primary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: _history.setSearch,
        decoration: InputDecoration(
          hintText: 'Search by order ID',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _history.search.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _searchController.clear();
                    _history.setSearch('');
                  },
                ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<HistoryPeriod>(
              key: ValueKey((_history.period, _history.customRange, _resets)),
              initialValue: _history.period,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Period'),
              items: [
                for (final period in HistoryPeriod.values)
                  DropdownMenuItem(
                    value: period,
                    child: Text(
                      period == HistoryPeriod.custom &&
                              _history.customRange != null
                          ? _rangeLabel(_history.customRange!)
                          : period.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (period) {
                if (period != null) _choosePeriod(period);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final filter in HistoryFilter.values) ...[
              _buildFilterChip(filter),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (_history.isLoading)
        const SkeletonList()
      else if (_history.status == LoadStatus.error)
        ErrorState(message: _history.error!, onRetry: _history.load)
      else if (orders.isEmpty)
        EmptyState(
          icon: Icons.receipt_long_outlined,
          title: _history.hasFilters ? _emptyTitle() : 'No orders yet',
          message: _history.hasFilters
              ? 'Try a different period or status.'
              : 'Orders you complete will appear here.',
          actionLabel: _history.hasFilters ? 'Clear filters' : null,
          onAction: _clearFilters,
        )
      else ...[
        ..._buildGroupedList(orders),
        if (_history.isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (loadMoreError != null)
          ErrorState(
            message: loadMoreError,
            onRetry: _history.loadMore,
            compact: true,
          )
        else if (_history.hasMore)
          Center(
            child: TextButton(
              onPressed: _history.loadMore,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Load more'),
            ),
          ),
      ],
    ];
  }

  List<Widget> _buildGroupedList(List<DeliveryTask> orders) {
    final now = context.services.clock.now();
    final byDay = _history.filteredSummary?.byDay ?? const {};
    final widgets = <Widget>[];
    DateTime? lastDay;

    for (final order in orders) {
      final day = startOfDay(order.endedAt);
      if (day != lastDay) {
        final total = byDay[day];
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: Semantics(
              header: true,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      formatDate(day, now: now),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (total != null)
                    Flexible(
                      child: Text(
                        '${total.orders} '
                        '${total.orders == 1 ? 'order' : 'orders'} · '
                        '${formatPaise(total.earnedPaise)}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        lastDay = day;
      }
      final onOpen = widget.onOpenOrder;
      final card = OrderCard(
        order: order,
        when: formatTime(order.endedAt),
        onTap: onOpen != null
            ? () => onOpen(order.orderId)
            : () => Navigator.pushNamed(
                context,
                AppRoutes.orderDetails,
                arguments: order.orderId,
              ),
      );
      widgets.add(
        order.orderId == widget.selectedOrderId
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                child: card,
              )
            : card,
      );
    }
    return widgets;
  }

  Widget _buildFilterChip(HistoryFilter filter) {
    final selected = _history.filter == filter;

    return ChoiceChip(
      label: Text(filter.label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => _history.setFilter(filter),
      selectedColor: AppColors.primary,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textDark,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
