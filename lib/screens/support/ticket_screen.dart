import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../controllers/support_controller.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/media_ref.dart';
import '../../models/support.dart';
import '../../services/image_service.dart';
import '../../utils/app_colors.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/media_image.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_badge.dart';

/// A support request or live chat: the message thread, a reply box and
/// "Mark resolved".
class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  late final SupportController _support = context.services.support;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  MediaRef? _attachment;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _support.ensureLoaded();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send() async {
    final attachment = _attachment;
    try {
      await _support.reply(
        widget.ticketId,
        _text.text,
        attachments: [?attachment],
      );
      if (!mounted) return;
      _text.clear();
      setState(() => _attachment = null);
    } on AppFailure catch (failure) {
      if (mounted) _show(failure.message);
    }
  }

  Future<void> _attach() async {
    final path = await ImageService.pickImage(context);
    if (path != null && mounted) {
      setState(() => _attachment = MediaRef.file(path));
    }
  }

  Future<void> _resolve() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Mark as resolved?',
      message: 'You can still open a new request if the problem comes back.',
      confirmLabel: 'Resolve',
    );
    if (!confirmed || !mounted) return;
    try {
      await _support.resolve(widget.ticketId);
      if (mounted) _show('Marked as resolved');
    } on AppFailure catch (failure) {
      if (mounted) _show(failure.message);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _support,
      builder: (context, _) {
        final ticket = _support.ticketById(widget.ticketId);
        if (ticket == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Support')),
            body: Center(
              child: _support.isReady
                  ? const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Request not found',
                      message: 'It may have been closed.',
                    )
                  : const CircularProgressIndicator(),
            ),
          );
        }
        final count = ticket.messages.length + (ticket.agentTyping ? 1 : 0);
        if (count != _shown) {
          _shown = count;
          _scrollToEnd();
        }
        final resolved = ticket.status == TicketStatus.resolved;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.isChat ? 'Chat with support' : ticket.category,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  ticket.isChat
                      ? 'Simulated chat · ${ticket.category}'
                      : '${ticket.id} · ${ticket.status.label}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              if (!resolved)
                TextButton(
                  onPressed: _support.isSending ? null : _resolve,
                  child: const Text('Mark resolved'),
                ),
            ],
          ),
          body: Column(
            children: [
              if (ticket.orderId case final orderId?)
                Material(
                  color: AppColors.primaryLight,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text('About order $orderId'),
                    trailing: const Text('View order'),
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.orderDetails,
                      arguments: orderId,
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    for (final message in ticket.messages)
                      _MessageBubble(message: message),
                    if (ticket.agentTyping) const _TypingBubble(),
                  ],
                ),
              ),
              if (resolved)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      StatusBadge.ticket(ticket.status),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(
                        child: Text(
                          'This request is closed. Open a new one from Help.',
                        ),
                      ),
                    ],
                  ),
                )
              else
                _buildInputBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    final attachment = _attachment;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachment != null)
            ListTile(
              dense: true,
              leading: SizedBox.square(
                dimension: 40,
                child: MediaImage(media: attachment),
              ),
              title: const Text('Photo attached'),
              trailing: IconButton(
                tooltip: 'Remove photo',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => _attachment = null),
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Attach a photo',
                onPressed: _attach,
                icon: const Icon(Icons.attach_file_rounded),
              ),
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Write a reply',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: _support.isSending ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final now = context.services.clock.now();
    if (message.from == MessageAuthor.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final mine = message.from == MessageAuthor.rider;
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: mine ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: mine ? null : Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                const Text(
                  'Qwiko support',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              for (final media in message.attachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SizedBox(
                    height: 120,
                    width: 160,
                    child: MediaImage(media: media),
                  ),
                ),
              if (message.text.isNotEmpty)
                Text(
                  message.text,
                  style: TextStyle(
                    color: mine ? Colors.white : AppColors.textDark,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                formatDateTime(message.at, now: now),
                style: TextStyle(
                  color: mine ? Colors.white70 : AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'Support is typing…',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
