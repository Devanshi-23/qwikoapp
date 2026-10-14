import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../models/order.dart';
import '../utils/app_colors.dart';
import 'app_card.dart';
import 'money_text.dart';
import 'status_badge.dart';

/// One finished (or in-progress) order in a list.
class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.when,
    this.onTap,
  });

  final DeliveryTask order;

  /// Already formatted, for example "4:12 PM" or "Yesterday, 4:12 PM".
  final String when;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = orderStatusStyle(order.status);
    final earned = order.earnedPaise;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: onTap != null,
      onTap: onTap,
      label:
          'Order ${order.displayId}, ${style.label}, '
          '${order.store.name} to ${order.customer.fullName}, $when, '
          '${earned > 0 ? 'earned ${spokenPaise(earned)}' : 'no earnings'}',
      excludeSemantics: true,
      child: AppCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(style.icon, color: style.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${order.store.name} → ${order.customer.fullName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${order.displayId}  •  $when  •  ${formatDistance(order.distanceM)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  earned > 0
                      ? MoneyText(
                          earned,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : const Text(
                          '—',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                  const SizedBox(height: 3),
                  Text(
                    style.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: order.status == OrderStatus.delivered
                          ? AppColors.textSecondary
                          : style.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
