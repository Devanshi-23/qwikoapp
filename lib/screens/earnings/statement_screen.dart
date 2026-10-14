import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../models/money.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/money_text.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';

/// Every ledger credit in a period, with totals by type.
class StatementScreen extends StatelessWidget {
  const StatementScreen({
    super.key,
    required this.title,
    required this.entries,
  });

  final String title;

  /// Newest first.
  final List<EarningEntry> entries;

  @override
  Widget build(BuildContext context) {
    final now = context.services.clock.now();
    final textTheme = Theme.of(context).textTheme;
    final total = entries.fold(0, (sum, e) => sum + e.amountPaise);
    final byType = <EarningType, int>{};
    for (final entry in entries) {
      byType[entry.type] = (byType[entry.type] ?? 0) + entry.amountPaise;
    }
    final rows = <Widget>[];
    DateTime? day;
    for (final entry in entries) {
      final entryDay = startOfDay(entry.at);
      if (entryDay != day) {
        day = entryDay;
        rows.add(
          SectionHeader(
            formatDate(entryDay, now: now),
            padding: const EdgeInsets.only(top: AppSpacing.md, bottom: 4),
          ),
        );
      }
      rows.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(entry.label),
          subtitle: Text(formatTime(entry.at)),
          trailing: MoneyText(entry.amountPaise, style: textTheme.titleSmall),
        ),
      );
    }

    return AppScaffold(
      title: 'Statement · $title',
      showDemoBadge: true,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          AppCard(
            title: 'Summary',
            child: Column(
              children: [
                for (final MapEntry(key: type, value: amount) in byType.entries)
                  _Line(type.label, amount),
                const Divider(),
                _Line('Total', total, bold: true),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const PrimaryButton(
            label: 'Download PDF',
            icon: Icons.picture_as_pdf_outlined,
            variant: ButtonVariant.outlined,
            onPressed: null,
          ),
          const DisabledReason(
            'Statement downloads will be available when payouts are '
            'connected.',
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.paise, {this.bold = false});

  final String label;
  final int paise;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          MoneyText(paise, style: style),
        ],
      ),
    );
  }
}
