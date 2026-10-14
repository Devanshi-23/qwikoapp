import 'package:flutter/material.dart';

import '../models/money.dart';
import '../models/order.dart';
import '../models/partner.dart';
import '../models/support.dart';
import '../utils/app_colors.dart';

enum StatusTone {
  success(AppColors.primary, AppColors.primaryLight),
  warning(AppColors.warning, AppColors.warningLight),
  danger(AppColors.error, AppColors.errorLight),
  info(AppColors.info, AppColors.infoLight),
  neutral(AppColors.textSecondary, AppColors.neutralLight);

  const StatusTone(this.color, this.background);

  /// Text and icon colour; at least 4.5:1 on [background].
  final Color color;
  final Color background;
}

/// Colour never carries meaning alone, so every style has a label and icon.
class StatusStyle {
  const StatusStyle(this.label, this.tone, this.icon);

  final String label;
  final StatusTone tone;
  final IconData icon;

  Color get color => tone.color;
  Color get background => tone.background;
}

StatusStyle orderStatusStyle(OrderStatus status) => switch (status) {
  OrderStatus.delivered => StatusStyle(
    status.label,
    StatusTone.success,
    Icons.check_circle_rounded,
  ),
  OrderStatus.returned ||
  OrderStatus.disposed ||
  OrderStatus.handedOver => StatusStyle(
    status.label,
    StatusTone.warning,
    Icons.assignment_return_rounded,
  ),
  _ when !status.isFinal => StatusStyle(
    status.label,
    StatusTone.info,
    Icons.delivery_dining_rounded,
  ),
  _ => StatusStyle(status.label, StatusTone.danger, Icons.cancel_rounded),
};

StatusStyle documentStatusStyle(DocumentStatus status) => StatusStyle(
  status.label,
  switch (status) {
    DocumentStatus.verified => StatusTone.success,
    DocumentStatus.pending => StatusTone.info,
    DocumentStatus.expiringSoon => StatusTone.warning,
    DocumentStatus.rejected || DocumentStatus.expired => StatusTone.danger,
    DocumentStatus.notUploaded => StatusTone.neutral,
  },
  switch (status) {
    DocumentStatus.verified => Icons.verified_rounded,
    DocumentStatus.pending => Icons.hourglass_top_rounded,
    DocumentStatus.expiringSoon => Icons.event_busy_rounded,
    DocumentStatus.rejected => Icons.error_outline_rounded,
    DocumentStatus.expired => Icons.event_busy_rounded,
    DocumentStatus.notUploaded => Icons.upload_file_rounded,
  },
);

StatusStyle payoutStatusStyle(PayoutStatus status) => switch (status) {
  PayoutStatus.paid => StatusStyle(
    status.label,
    StatusTone.success,
    Icons.account_balance_rounded,
  ),
  PayoutStatus.failed => StatusStyle(
    status.label,
    StatusTone.danger,
    Icons.error_outline_rounded,
  ),
  PayoutStatus.requested || PayoutStatus.processing => StatusStyle(
    status.label,
    StatusTone.warning,
    Icons.schedule_rounded,
  ),
};

StatusStyle ticketStatusStyle(TicketStatus status) => switch (status) {
  TicketStatus.open => const StatusStyle(
    'Open',
    StatusTone.info,
    Icons.mark_chat_unread_outlined,
  ),
  TicketStatus.awaitingYou => const StatusStyle(
    'Awaiting you',
    StatusTone.warning,
    Icons.reply_rounded,
  ),
  TicketStatus.resolved => const StatusStyle(
    'Resolved',
    StatusTone.success,
    Icons.check_circle_rounded,
  ),
};

StatusStyle verificationStatusStyle(VerificationStatus status) =>
    switch (status) {
      VerificationStatus.verified => const StatusStyle(
        'Verified partner',
        StatusTone.success,
        Icons.verified_rounded,
      ),
      VerificationStatus.pending => const StatusStyle(
        'Verification pending',
        StatusTone.warning,
        Icons.pending_outlined,
      ),
      VerificationStatus.newSignup => const StatusStyle(
        'KYC not submitted',
        StatusTone.neutral,
        Icons.assignment_outlined,
      ),
      VerificationStatus.rejected => const StatusStyle(
        'Verification rejected',
        StatusTone.danger,
        Icons.error_outline_rounded,
      ),
      VerificationStatus.suspended => const StatusStyle(
        'Account suspended',
        StatusTone.danger,
        Icons.block_rounded,
      ),
    };

StatusStyle incentiveStatusStyle(IncentiveStatus status) => switch (status) {
  IncentiveStatus.upcoming => const StatusStyle(
    'Upcoming',
    StatusTone.neutral,
    Icons.schedule_rounded,
  ),
  IncentiveStatus.active => const StatusStyle(
    'Active',
    StatusTone.info,
    Icons.local_fire_department_rounded,
  ),
  IncentiveStatus.achieved => const StatusStyle(
    'Achieved',
    StatusTone.success,
    Icons.emoji_events_rounded,
  ),
  IncentiveStatus.missed => const StatusStyle(
    'Missed',
    StatusTone.danger,
    Icons.cancel_outlined,
  ),
};

/// Icon + label + colour pill for order, document, payout, ticket,
/// verification and incentive states.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.style, {super.key, this.dense = false});

  StatusBadge.order(OrderStatus status, {Key? key, bool dense = false})
    : this(orderStatusStyle(status), key: key, dense: dense);

  StatusBadge.document(DocumentStatus status, {Key? key, bool dense = false})
    : this(documentStatusStyle(status), key: key, dense: dense);

  StatusBadge.payout(PayoutStatus status, {Key? key, bool dense = false})
    : this(payoutStatusStyle(status), key: key, dense: dense);

  StatusBadge.ticket(TicketStatus status, {Key? key, bool dense = false})
    : this(ticketStatusStyle(status), key: key, dense: dense);

  StatusBadge.verification(
    VerificationStatus status, {
    Key? key,
    bool dense = false,
  }) : this(verificationStatusStyle(status), key: key, dense: dense);

  StatusBadge.incentive(IncentiveStatus status, {Key? key, bool dense = false})
    : this(incentiveStatusStyle(status), key: key, dense: dense);

  final StatusStyle style;

  /// Smaller padding and text for list rows.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Status: ${style.label}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10,
          vertical: dense ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: dense ? 13 : 15, color: style.color),
            SizedBox(width: dense ? 4 : 6),
            Flexible(
              child: Text(
                style.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: style.color,
                  fontSize: dense ? 11 : 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
