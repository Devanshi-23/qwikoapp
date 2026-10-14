import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/support.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_badge.dart';
import '../orders/order_issue_sheet.dart';

/// Opens Help with a support ticket ready to send.
class HelpRequest {
  const HelpRequest({required this.category, required this.message});

  final String category;
  final String message;
}

/// Help centre: searchable FAQs, chat, simulated call, order help and the
/// rider's requests. "Call 112" lives on the Safety screen only.
class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key, this.request});

  final HelpRequest? request;

  static const chatTopics = ['Payout delay', 'App issue', 'Something else'];

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final _search = TextEditingController();
  FaqCategory? _category;
  late HelpRequest? _request = widget.request;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.services.support.ensureLoaded();
      context.services.history.ensureLoaded();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openTicket(String id) =>
      Navigator.pushNamed(context, AppRoutes.ticket, arguments: id);

  Future<void> _startChat() async {
    final topic = await showAppBottomSheet<String>(
      context,
      title: 'Chat with support',
      subtitle: 'A simulated agent replies in a few seconds.',
      builder: (context) => Column(
        children: [
          for (final topic in HelpSupportScreen.chatTopics)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(topic),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, topic),
            ),
        ],
      ),
    );
    if (topic == null || !mounted) return;
    try {
      final chat = await context.services.support.startChat(topic);
      if (mounted) _openTicket(chat.id);
    } on AppFailure catch (failure) {
      if (mounted) _show(failure.message);
    }
  }

  void _call() {
    showAppBottomSheet<void>(
      context,
      title: 'Call support',
      builder: (context) => const _SimulatedCall(),
    );
  }

  Future<void> _orderHelp() async {
    final history = context.services.history;
    final recent = history.recent;
    final order = await showAppBottomSheet<String>(
      context,
      title: 'Which order?',
      subtitle: 'Pick a recent order to report a problem with it.',
      builder: (context) => recent.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No recent orders',
              message: 'Orders you deliver will show up here.',
            )
          : Column(
              children: [
                for (final task in recent)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${task.displayId} · ${task.store.name}'),
                    subtitle: Text(
                      formatDateTime(
                        task.lastUpdatedAt,
                        now: context.services.clock.now(),
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(context, task.orderId),
                  ),
              ],
            ),
    );
    if (order == null || !mounted) return;
    final task = recent.firstWhere((t) => t.orderId == order);
    final ticket = await showOrderIssueSheet(context, task);
    if (ticket != null && mounted) _openTicket(ticket.id);
  }

  void _openArticle(FaqArticle faq) {
    showAppBottomSheet<void>(
      context,
      title: faq.question,
      builder: (sheetContext) => _ArticleView(
        faq: faq,
        onHelpful: () {
          Navigator.pop(sheetContext);
          _show('Thanks for letting us know.');
        },
        onNotHelpful: () {
          Navigator.pop(sheetContext);
          setState(
            () => _request = HelpRequest(
              category: faq.category.label,
              message: 'About "${faq.question}": ',
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final support = context.services.support;
    final request = _request;
    return AppScaffold(
      title: 'Help & support',
      body: ListenableBuilder(
        listenable: support,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            if (request != null) ...[
              _ContactSupportCard(
                key: ValueKey(request),
                request: request,
                onSent: _openTicket,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Row(
              children: [
                Expanded(
                  child: _ContactTile(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Chat',
                    onTap: _startChat,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ContactTile(
                    icon: Icons.call_outlined,
                    label: 'Call',
                    onTap: _call,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ContactTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Order help',
                    onTap: _orderHelp,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              borderColor: AppColors.error.withValues(alpha: 0.4),
              onTap: () => Navigator.pushNamed(context, AppRoutes.safety),
              child: const Row(
                children: [
                  Icon(Icons.sos_rounded, color: AppColors.error),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'In danger? Open Safety for SOS and Call 112.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            ..._buildTickets(support.tickets),
            const SectionHeader('Frequently asked questions'),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search help articles',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final category in <FaqCategory?>[
                  null,
                  ...FaqCategory.values,
                ])
                  ChoiceChip(
                    label: Text(category?.label ?? 'All'),
                    selected: _category == category,
                    onSelected: (_) => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._buildFaqs(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTickets(List<SupportTicket> tickets) {
    if (tickets.isEmpty) return const [];
    final now = context.services.clock.now();
    return [
      const SectionHeader('Your requests'),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final ticket in tickets)
              ListTile(
                leading: Icon(
                  ticket.isChat
                      ? Icons.chat_bubble_outline_rounded
                      : Icons.confirmation_number_outlined,
                ),
                title: Text('${ticket.category} · ${ticket.id}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.agentTyping
                          ? 'Support is replying…'
                          : 'Updated ${timeAgo(ticket.updatedAt, now: now)}',
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    StatusBadge.ticket(ticket.status, dense: true),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openTicket(ticket.id),
              ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
    ];
  }

  List<Widget> _buildFaqs() {
    final support = context.services.support;
    if (!support.isReady && support.faqs.isEmpty) {
      return const [SkeletonList(count: 4)];
    }
    final results = support.searchFaqs(_search.text, category: _category);
    if (results.isEmpty) {
      return [
        EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No articles match',
          message: 'Try other words, or ask us directly.',
          actionLabel: 'Contact support',
          onAction: () => setState(
            () => _request = HelpRequest(
              category: _category?.label ?? 'Other',
              message: _search.text,
            ),
          ),
        ),
      ];
    }
    return [
      for (final faq in results)
        Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ListTile(
            title: Text(faq.question),
            subtitle: Text(faq.category.label),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openArticle(faq),
          ),
        ),
    ];
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleView extends StatelessWidget {
  const _ArticleView({
    required this.faq,
    required this.onHelpful,
    required this.onNotHelpful,
  });

  final FaqArticle faq;
  final VoidCallback onHelpful;
  final VoidCallback onNotHelpful;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(faq.answer, style: textTheme.bodyMedium?.copyWith(height: 1.5)),
        const SizedBox(height: AppSpacing.xl),
        Text('Was this helpful?', style: textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onHelpful,
                icon: const Icon(Icons.thumb_up_alt_outlined),
                label: const Text('Yes'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onNotHelpful,
                icon: const Icon(Icons.thumb_down_alt_outlined),
                label: const Text('No, contact support'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// No call is placed in the demo; the sheet shows what would happen.
class _SimulatedCall extends StatefulWidget {
  const _SimulatedCall();

  static const supportNumber = '1800 123 4567';

  @override
  State<_SimulatedCall> createState() => _SimulatedCallState();
}

class _SimulatedCallState extends State<_SimulatedCall> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _seconds++),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SimulatedLabel(text: 'Simulated call · no call is placed'),
        const SizedBox(height: AppSpacing.md),
        const Icon(
          Icons.support_agent_rounded,
          size: 56,
          color: AppColors.primary,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Qwiko partner support',
          textAlign: TextAlign.center,
          style: textTheme.titleMedium,
        ),
        Text(
          '${_SimulatedCall.supportNumber} · '
          '${formatClock(Duration(seconds: _seconds))}',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'In the live app this connects you to an agent. For an emergency, '
          'use Call 112 on the Safety screen.',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'End call',
          icon: Icons.call_end_rounded,
          variant: ButtonVariant.destructive,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _ContactSupportCard extends StatefulWidget {
  const _ContactSupportCard({
    super.key,
    required this.request,
    required this.onSent,
  });

  final HelpRequest request;
  final ValueChanged<String> onSent;

  @override
  State<_ContactSupportCard> createState() => _ContactSupportCardState();
}

class _ContactSupportCardState extends State<_ContactSupportCard> {
  late final _message = TextEditingController(text: widget.request.message);
  String? _error;
  String? _ticketId;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _error = null);
    try {
      final ticket = await context.services.support.createTicket(
        category: widget.request.category,
        message: _message.text,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Request ${ticket.id} sent to support'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => widget.onSent(ticket.id),
          ),
        ),
      );
      if (mounted) setState(() => _ticketId = ticket.id);
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ticketId = _ticketId;
    if (ticketId != null) {
      return AppCard(
        borderColor: AppColors.primary.withValues(alpha: 0.4),
        onTap: () => widget.onSent(ticketId),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Request $ticketId sent. An agent will reply here.',
                style: textTheme.bodyMedium,
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      );
    }
    final support = context.services.support;
    return AppCard(
      title: 'Contact support: ${widget.request.category}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _message,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'Message',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: support,
            builder: (context, _) => PrimaryButton(
              label: 'Send to support',
              icon: Icons.send_rounded,
              isLoading: support.isSending,
              onPressed: _send,
            ),
          ),
        ],
      ),
    );
  }
}
