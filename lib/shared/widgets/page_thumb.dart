import 'dart:io';

import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flutter/material.dart';

/// Thumbnail with a selected ring and a number badge. Used on the viewer
/// strip, Enhance, and batch review.
class PageThumb extends StatelessWidget {
  const PageThumb({
    required this.path,
    super.key,
    this.number,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.size = 64,
    this.aspect = 0.75,
    this.cacheKey,
  });

  final String? path;
  final int? number;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double size;
  final double aspect;

  /// Changes when the file at [path] is rewritten, to bust the image cache.
  final Object? cacheKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final file = path == null ? null : File(path!);
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: Motion.fast,
          width: size,
          height: size / aspect,
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: Radii.smR,
            border: Border.all(
              color: selected ? c.accent : c.border,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (file != null && file.existsSync())
                Image.file(
                  file,
                  key: ValueKey(cacheKey ?? path),
                  fit: BoxFit.cover,
                  cacheWidth: (size * 2).round(),
                  gaplessPlayback: true,
                )
              else
                Icon(Icons.image_rounded, color: c.muted),
              if (number != null)
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? c.accent : c.bg.withValues(alpha: 0.8),
                      borderRadius: Radii.pillR,
                    ),
                    child: Text(
                      '$number',
                      style: context.text.labelSmall?.copyWith(
                        color: selected ? c.onAccent : c.text,
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
