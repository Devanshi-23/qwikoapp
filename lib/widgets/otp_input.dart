import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_colors.dart';

/// Digit boxes backed by a single hidden text field, so paste, SMS autofill
/// and screen readers work like a normal field. Shared by the sign-in OTP
/// and the delivery OTP.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    this.length = 6,
    this.controller,
    this.onChanged,
    this.onCompleted,
    this.enabled = true,
    this.autofocus = false,
    this.errorText,
    this.semanticLabel = 'One-time password',
  });

  final int length;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  /// Called once all [length] digits are entered.
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final bool autofocus;
  final String? errorText;
  final String semanticLabel;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  TextEditingController? _ownController;
  final FocusNode _focus = FocusNode();

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
    _focus.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(OtpInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownController)?.removeListener(_rebuild);
      _controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    _ownController?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _onChanged(String value) {
    widget.onChanged?.call(value);
    if (value.length == widget.length) widget.onCompleted?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    final errorText = widget.errorText;
    final hasError = errorText != null;
    final activeIndex = text.length.clamp(0, widget.length - 1);

    Widget box(int index) {
      final digit = index < text.length ? text[index] : '';
      final active = _focus.hasFocus && index == activeIndex;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 52),
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: !widget.enabled
                  ? AppColors.background
                  : digit.isEmpty
                  ? AppColors.inputFill
                  : AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasError
                    ? AppColors.error
                    : active
                    ? AppColors.primary
                    : AppColors.border,
                width: active || hasError ? 1.8 : 1,
              ),
            ),
            child: Text(
              digit,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < widget.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: box(i),
                      ),
                    ),
                ],
              ),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                alwaysIncludeSemantics: true,
                child: Semantics(
                  label: '${widget.semanticLabel}, ${widget.length} digits',
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    autofocus: widget.autofocus,
                    enabled: widget.enabled,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(widget.length),
                    ],
                    showCursor: false,
                    enableInteractiveSelection: false,
                    onChanged: _onChanged,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                errorText,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}
