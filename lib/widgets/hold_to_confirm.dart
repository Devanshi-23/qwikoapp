import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_colors.dart';

/// A round button that fires only after being held for [holdFor], so a
/// stray tap does nothing. Screen readers trigger it with the long-press
/// action.
class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton({
    super.key,
    required this.label,
    required this.hint,
    required this.onConfirmed,
    this.holdFor = const Duration(seconds: 3),
    this.color = AppColors.error,
    this.size = 148,
  });

  final String label;

  /// Shown under the button, for example "Press and hold for 3 seconds".
  final String hint;
  final VoidCallback onConfirmed;
  final Duration holdFor;
  final Color color;
  final double size;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.holdFor,
  )..addStatusListener(_onStatus);

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    HapticFeedback.heavyImpact();
    _progress.value = 0;
    widget.onConfirmed();
  }

  void _start() {
    HapticFeedback.selectionClick();
    _progress.forward(from: 0);
  }

  void _cancel() {
    if (_progress.isAnimating) _progress.reverse();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: widget.label,
          hint: widget.hint,
          onLongPress: widget.onConfirmed,
          excludeSemantics: true,
          child: GestureDetector(
            onTapDown: (_) => _start(),
            onTapUp: (_) => _cancel(),
            onTapCancel: _cancel,
            child: SizedBox.square(
              dimension: widget.size,
              child: AnimatedBuilder(
                animation: _progress,
                builder: (context, child) => Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: _progress.value,
                      strokeWidth: 8,
                      color: widget.color,
                      backgroundColor: widget.color.withValues(alpha: 0.15),
                    ),
                    child!,
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.hint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
