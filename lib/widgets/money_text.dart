import 'package:flutter/material.dart';

import '../core/formatters.dart';

/// Paise shown as whole rupees with Indian grouping; screen readers hear
/// "1,295 rupees" instead of "rupee sign one comma two nine five".
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.paise, {
    super.key,
    this.style,
    this.textAlign,
    this.prefix = '',
  });

  final int paise;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// Shown and spoken before the amount, for example `+` or `Collect `.
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$prefix${spokenPaise(paise)}',
      excludeSemantics: true,
      child: Text(
        '$prefix${formatPaise(paise)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}
