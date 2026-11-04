import 'dart:io';

import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flutter/material.dart';

/// Page thumbnail: white page with a hairline border inside a 2 px ring
/// that lights up when selected, plus a number badge that hangs off the
/// bottom edge. Used on the viewer strip.
class PageThumb extends StatelessWidget {
  const PageThumb({
    required this.path,
    super.key,
    this.number,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.size = 52,
    this.aspect = 52 / 68,
    this.cacheKey,
    this.semanticLabel,
  });

  final String? path;
  final int? number;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double size;
  final double aspect;
  final String? semanticLabel;

  /// Changes when the file at [path] is rewritten, to bust the image cache.
  final Object? cacheKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: size,
          height: size / aspect,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: AnimatedContainer(
                  duration: Motion.fast,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: selected ? c.accent : Colors.transparent, width: 2),
                  ),
                  child: PageImage(path: path, cacheKey: cacheKey, cacheWidth: (size * 2.5).round()),
                ),
              ),
              if (number != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -8,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? c.accent : c.chip,
                        borderRadius: Radii.pillR,
                      ),
                      child: Text(
                        '$number',
                        style: context.text.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: selected ? c.onAccent : c.text,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A page image on white paper with a hairline border; falls back to a
/// blank sheet while the file is missing.
class PageImage extends StatelessWidget {
  const PageImage({
    required this.path,
    super.key,
    this.cacheKey,
    this.cacheWidth,
    this.radius = 4,
    this.fit = BoxFit.cover,
    this.border = true,
  });

  final String? path;
  final Object? cacheKey;
  final int? cacheWidth;
  final double radius;
  final BoxFit fit;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final file = path == null ? null : File(path!);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: c.isDark ? c.border : c.borderStrong) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: file != null && file.existsSync()
          ? Image.file(
              file,
              key: ValueKey(cacheKey ?? path),
              fit: fit,
              cacheWidth: cacheWidth,
              gaplessPlayback: true,
            )
          : const _BlankPage(),
    );
  }
}

/// Stylised text lines, the canvas's placeholder for a page.
class _BlankPage extends StatelessWidget {
  const _BlankPage();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        if (!w.isFinite || w < 16) return const SizedBox.expand();
        final pad = w * 0.14;
        Widget line(double f, {bool heading = false}) => Container(
              margin: EdgeInsets.only(bottom: w * 0.08),
              height: heading ? (w * 0.07).clamp(2, 10) : (w * 0.045).clamp(1.5, 4),
              width: (w - pad * 2) * f,
              color: heading ? const Color(0xFF9FA3AA) : const Color(0xFFC9CCD1),
            );
        return ClipRect(
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [line(0.6, heading: true), line(1), line(1), line(0.8)],
              ),
            ),
          ),
        );
      },
    );
  }
}
