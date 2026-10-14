import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../models/order.dart';
import '../../models/support.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/primary_button.dart';

enum OrderIssue {
  payMissing('Pay missing'),
  wrongDistance('Wrong distance'),
  tipMissing('Tip missing'),
  customerComplaint('Customer complaint'),
  other('Something else');

  const OrderIssue(this.label);

  final String label;
}

/// Creates a support ticket linked to [order]; returns it once sent.
Future<SupportTicket?> showOrderIssueSheet(
  BuildContext context,
  DeliveryTask order,
) => showAppBottomSheet<SupportTicket>(
  context,
  title: 'Report an issue',
  subtitle: 'Order ${order.displayId}',
  builder: (_) => OrderIssueForm(order: order),
);

class OrderIssueForm extends StatefulWidget {
  const OrderIssueForm({super.key, required this.order});

  final DeliveryTask order;

  @override
  State<OrderIssueForm> createState() => _OrderIssueFormState();
}

class _OrderIssueFormState extends State<OrderIssueForm> {
  final _details = TextEditingController();
  OrderIssue? _issue;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send(OrderIssue issue) async {
    setState(() => _error = null);
    try {
      final ticket = await context.services.support.createTicket(
        category: issue.label,
        message: _details.text,
        source: TicketSource.order,
        orderId: widget.order.orderId,
      );
      if (mounted) Navigator.pop(context, ticket);
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final support = context.services.support;
    final issue = _issue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<OrderIssue>(
          groupValue: issue,
          onChanged: (value) => setState(() => _issue = value),
          child: Column(
            children: [
              for (final option in OrderIssue.values)
                RadioListTile<OrderIssue>(
                  value: option,
                  title: Text(option.label),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _details,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: 'What happened?',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
        ),
        ListenableBuilder(
          listenable: support,
          builder: (context, _) => PrimaryButton(
            label: 'Send to support',
            icon: Icons.send_rounded,
            isLoading: support.isSending,
            onPressed: issue == null ? null : () => _send(issue),
          ),
        ),
        if (issue == null) const DisabledReason('Choose what went wrong.'),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
