import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../core/formatters.dart';
import '../../models/trip.dart';
import '../../utils/app_colors.dart';

/// Opens the active order and, when it comes back with the amount earned
/// or a cancellation, says so.
Future<void> openActiveOrder(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await Navigator.pushNamed<Object?>(
    context,
    AppRoutes.activeOrder,
  );
  final message = switch (result) {
    final int earned => 'Order delivered! You earned ${formatPaise(earned)}',
    TripCancellation(:final totalPaise) when totalPaise > 0 =>
      'Order cancelled. ${formatPaise(totalPaise)} added to your earnings.',
    TripCancellation() => "Order cancelled. You're ready for new offers.",
    _ => null,
  };
  if (message == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.primary),
    );
}
