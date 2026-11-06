import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A short label that is never cut off (P1-5): it wraps between words up to
/// [maxLines], and if that still doesn't fit (a long word, a very large
/// system font) it shrinks just enough to fit. Never breaks inside a word and
/// never shrinks below the normal (1.0×) size.
class FitText extends StatelessWidget {
  const FitText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 2,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        var use = scaler;
        if (c.maxWidth.isFinite) {
          final fontSize = effective.fontSize ?? 14;
          final full = scaler.scale(fontSize) / fontSize;
          final words = text.split(RegExp(r'\s+'));
          bool fits(TextScaler s) {
            for (final w in words) {
              final tp = TextPainter(
                text: TextSpan(text: w, style: effective),
                textScaler: s,
                textDirection: direction,
                maxLines: 1,
              )..layout();
              final wide = tp.width > c.maxWidth;
              tp.dispose();
              if (wide) return false;
            }
            final tp = TextPainter(
              text: TextSpan(text: text, style: effective),
              textScaler: s,
              textDirection: direction,
              maxLines: maxLines,
              textAlign: textAlign,
            )..layout(maxWidth: c.maxWidth);
            final ok = !tp.didExceedMaxLines;
            tp.dispose();
            return ok;
          }

          if (!fits(scaler)) {
            for (var f = full * 0.92; f > 1; f *= 0.92) {
              use = TextScaler.linear(f);
              if (fits(use)) break;
            }
            if (!fits(use)) use = TextScaler.linear(math.min(1, full));
          }
        }
        return Text(
          text,
          style: style,
          textScaler: use,
          maxLines: maxLines,
          textAlign: textAlign,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
