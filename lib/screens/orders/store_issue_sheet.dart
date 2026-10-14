import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../models/order.dart';
import '../../models/store_issue.dart';
import '../../models/trip.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/primary_button.dart';

/// "Report a store issue": pick the problem and, for missing or damaged
/// items, which items and what the store does. Returns null if dismissed.
Future<StoreIssueRequest?> showStoreIssueSheet(
  BuildContext context, {
  required DeliveryTrip trip,
  required bool nearStore,
}) => showAppBottomSheet<StoreIssueRequest>(
  context,
  title: 'Report a store issue',
  subtitle: 'The store and Qwiko support see this right away.',
  builder: (context) => _StoreIssueForm(trip: trip, nearStore: nearStore),
);

class _StoreIssueForm extends StatefulWidget {
  const _StoreIssueForm({required this.trip, required this.nearStore});

  final DeliveryTrip trip;
  final bool nearStore;

  @override
  State<_StoreIssueForm> createState() => _StoreIssueFormState();
}

class _StoreIssueFormState extends State<_StoreIssueForm> {
  IssueType? _type;
  final Set<ItemRef> _items = {};
  ItemResolution? _resolution;

  bool get _atStore => widget.trip.status == TripStatus.atStore;

  /// Why [type] can't be reported yet, or null.
  String? _unavailable(IssueType type) {
    if (type == IssueType.storeClosed) {
      return widget.nearStore || _atStore
          ? null
          : 'Available within ${DeliveryTrip.pickupGeofenceM} m of the store';
    }
    return _atStore ? null : "Available after you tap \"I've arrived\"";
  }

  bool get _valid {
    final type = _type;
    if (type == null || _unavailable(type) != null) return false;
    if (!type.needsItems) return true;
    return _items.isNotEmpty && _resolution != null;
  }

  void _submit() {
    final type = _type;
    if (type == null || !_valid) return;
    Navigator.pop(
      context,
      StoreIssueRequest(
        type: type,
        items: type.needsItems ? _items.toList() : const [],
        resolution: type.needsItems ? _resolution : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final type = _type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<IssueType>(
          groupValue: _type,
          onChanged: (value) => setState(() => _type = value),
          child: Column(
            children: [
              for (final option in storeIssueTypes)
                RadioListTile<IssueType>(
                  value: option,
                  enabled: _unavailable(option) == null,
                  contentPadding: EdgeInsets.zero,
                  title: Text(option.storeLabel),
                  subtitle: Text(_unavailable(option) ?? option.storeHint),
                ),
            ],
          ),
        ),
        if (type != null && type.needsItems) ...[
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            header: true,
            child: Text('Which items?', style: textTheme.titleSmall),
          ),
          for (final task in widget.trip.tasks)
            for (final (index, item) in task.items.indexed)
              if (item.status != ItemStatus.removed)
                CheckboxListTile(
                  value: _items.contains((orderId: task.orderId, index: index)),
                  onChanged: (checked) => setState(() {
                    final ref = (orderId: task.orderId, index: index);
                    checked ?? false ? _items.add(ref) : _items.remove(ref);
                  }),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(item.label),
                  subtitle: widget.trip.tasks.length > 1
                      ? Text(task.displayId)
                      : null,
                ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            header: true,
            child: Text('What will the store do?', style: textTheme.titleSmall),
          ),
          RadioGroup<ItemResolution>(
            groupValue: _resolution,
            onChanged: (value) => setState(() => _resolution = value),
            child: Column(
              children: [
                for (final option in ItemResolution.values)
                  RadioListTile<ItemResolution>(
                    value: option,
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.label),
                    subtitle: option == ItemResolution.remove
                        ? const Text(
                            'The customer pays less. Your pay is unchanged.',
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: type == IssueType.storeClosed
              ? 'Cancel order'
              : 'Report issue',
          variant: type == IssueType.storeClosed
              ? ButtonVariant.destructive
              : ButtonVariant.filled,
          onPressed: _valid ? _submit : null,
        ),
        if (type != null && type.needsItems && !_valid)
          const DisabledReason('Choose the items and what the store will do.'),
      ],
    );
  }
}
