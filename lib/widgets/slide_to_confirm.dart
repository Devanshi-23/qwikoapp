import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_colors.dart';

/// Slide the thumb to the end to confirm a consequential action. Pressing
/// and holding anywhere on the track also confirms (for switch access), and
/// screen readers confirm with a double tap via the semantics tap action.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.enabled = true,
    this.color = AppColors.primary,
    this.holdDuration = const Duration(milliseconds: 1200),
  });

  /// The action, for example "Slide to accept".
  final String label;
  final FutureOr<void> Function() onConfirmed;
  final bool enabled;
  final Color color;
  final Duration holdDuration;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
    with SingleTickerProviderStateMixin {
  static const double _height = 56;
  static const double _inset = 4;
  static const double _thumb = _height - _inset * 2;

  /// How far the thumb must travel before letting go confirms.
  static const double _threshold = 0.9;

  late final AnimationController _position = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  double _travel = 1;
  bool _busy = false;

  bool get _active => widget.enabled && !_busy;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  void _reset() {
    if (_reduceMotion) {
      _position.value = 0;
    } else {
      _position.animateBack(0, curve: Curves.easeOut);
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _position.value += (details.primaryDelta ?? 0) / _travel;
  }

  void _onDragEnd(DragEndDetails details) {
    _position.value >= _threshold ? _confirm() : _reset();
  }

  void _startHold() {
    final remaining = widget.holdDuration * (1 - _position.value);
    _position.animateTo(1, duration: remaining, curve: Curves.linear).then((_) {
      if (mounted && _position.value >= 1) _confirm();
    });
  }

  void _endHold() {
    if (!_busy && _position.value < 1) _reset();
  }

  Future<void> _confirm() async {
    if (!_active) return;
    setState(() => _busy = true);
    _position.value = 1;
    unawaited(HapticFeedback.mediumImpact());
    try {
      await widget.onConfirmed();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final trackColor = enabled ? widget.color : AppColors.border;
    final fillColor = Color.lerp(trackColor, Colors.black, 0.18)!;
    final labelColor = enabled ? Colors.white : AppColors.textSecondary;

    return Semantics(
      button: true,
      enabled: _active,
      label: widget.label,
      hint: 'Double tap to confirm',
      onTap: _active ? _confirm : null,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _travel = (constraints.maxWidth - _thumb - _inset * 2).clamp(
            1.0,
            double.infinity,
          );
          return GestureDetector(
            onHorizontalDragUpdate: _active ? _onDragUpdate : null,
            onHorizontalDragEnd: _active ? _onDragEnd : null,
            onLongPressStart: _active ? (_) => _startHold() : null,
            onLongPressEnd: _active ? (_) => _endHold() : null,
            child: AnimatedBuilder(
              animation: _position,
              builder: (context, _) {
                final offset = _travel * _position.value;
                return Container(
                  height: _height,
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(_height / 2),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: offset + _thumb + _inset * 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: fillColor,
                            borderRadius: BorderRadius.circular(_height / 2),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        left: _thumb + _inset * 2,
                        right: _inset * 4,
                        child: Center(
                          child: Opacity(
                            opacity: (1 - _position.value * 1.4).clamp(0, 1),
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: labelColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: _inset + offset,
                        top: _inset,
                        child: Container(
                          width: _thumb,
                          height: _thumb,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: _busy
                              ? Padding(
                                  padding: const EdgeInsets.all(13),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: trackColor,
                                  ),
                                )
                              : Icon(
                                  Icons.double_arrow_rounded,
                                  color: enabled
                                      ? widget.color
                                      : AppColors.textGrey,
                                ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
