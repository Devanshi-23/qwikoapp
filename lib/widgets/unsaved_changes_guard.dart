import 'package:flutter/material.dart';

import 'dialogs.dart';

/// Asks "Discard changes?" before back navigation leaves a form with
/// unsaved edits. `Navigator.pop` after a save is not intercepted.
class UnsavedChangesGuard extends StatelessWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.isDirty,
    required this.child,
  });

  final bool Function() isDirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (!isDirty()) {
          navigator.pop(result);
          return;
        }
        final discard = await showConfirmDialog(
          context,
          title: 'Discard changes?',
          message: "Your changes haven't been saved.",
          confirmLabel: 'Discard',
          cancelLabel: 'Keep editing',
          destructive: true,
        );
        if (discard) navigator.pop(result);
      },
      child: child,
    );
  }
}
