import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../controllers/active_trip_controller.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/order.dart';
import '../../utils/app_colors.dart';
import '../../widgets/state_views.dart';
import 'customer_call_sheet.dart';

/// Simulated chat with the current customer. Messages live on the order's
/// timeline, so they are kept (and queued offline) like any other step.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.controller});

  final ActiveTripController controller;

  static const int maxLength = 200;

  static const List<String> quickReplies = [
    'On my way',
    "I've arrived",
    'Please share your exact location',
    "I'm at the gate",
  ];

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  int _shown = 0;

  ActiveTripController get _controller => widget.controller;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _controller.sendChat(text);
      if (mounted) _textController.clear();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final task = _controller.currentTask;
        final open = task != null && _controller.trip!.isPickedUp;
        final messages = task?.chat.toList() ?? const <OrderEvent>[];
        if (messages.length != _shown) {
          _shown = messages.length;
          _scrollToBottom();
        }
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0.5,
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task?.customer.firstName ?? 'Customer',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  task == null
                      ? 'Simulated chat'
                      : 'Simulated chat · ${task.displayId}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            actions: [
              if (open)
                IconButton(
                  tooltip: 'Call ${task.customer.firstName}',
                  onPressed: () => showCustomerCallSheet(
                    context,
                    name: task.customer.firstName,
                    onCall: _controller.callCustomer,
                  ),
                  icon: const Icon(
                    Icons.call_rounded,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? const Center(
                        child: EmptyState(
                          icon: Icons.chat_bubble_outline_rounded,
                          iconColor: AppColors.primary,
                          title: 'Let the customer know you are coming',
                          message:
                              'Tap a quick message below or type your '
                              'own.',
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: messages.length,
                        itemBuilder: (context, index) =>
                            _Bubble(event: messages[index]),
                      ),
              ),
              if (open) ...[
                _buildQuickReplies(),
                _buildInputBar(),
              ] else
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('Chat is closed for this order.'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickReplies() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        itemCount: ChatScreen.quickReplies.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final text = ChatScreen.quickReplies[index];
          return ActionChip(
            label: Text(text),
            labelStyle: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            backgroundColor: AppColors.primaryLight,
            side: BorderSide.none,
            shape: const StadiumBorder(),
            onPressed: _controller.isBusy ? null : () => _send(text),
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              maxLength: ChatScreen.maxLength,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: 'Type a message',
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: () => _send(_textController.text),
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.event});

  final OrderEvent event;

  @override
  Widget build(BuildContext context) {
    final mine = event.type == OrderEventType.chatSent;
    final foreground = mine ? Colors.white : AppColors.textDark;
    final faint = mine
        ? Colors.white.withValues(alpha: 0.8)
        : AppColors.textSecondary;
    final status = event.queued ? 'Waiting for network' : 'Delivered';
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
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(16),
              topEnd: const Radius.circular(16),
              bottomStart: Radius.circular(mine ? 16 : 4),
              bottomEnd: Radius.circular(mine ? 4 : 16),
            ),
            border: mine ? null : Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                event.note ?? '',
                style: TextStyle(color: foreground, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatTime(event.at),
                    style: TextStyle(color: faint, fontSize: 10),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      event.queued
                          ? Icons.schedule_rounded
                          : Icons.done_all_rounded,
                      size: 14,
                      color: faint,
                      semanticLabel: status,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
