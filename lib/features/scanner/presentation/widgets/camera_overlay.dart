import 'dart:io';

import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/preview_geometry.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/preview_well.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// The camera screen chrome: top controls, the preview well (with the
/// corner frame and guide), mode pills and the shutter row.
class CameraOverlay extends StatelessWidget {
  const CameraOverlay({
    required this.preview,
    required this.rules,
    required this.title,
    required this.guide,
    required this.flashOn,
    required this.captureCount,
    required this.canFinish,
    required this.showModes,
    required this.capturing,
    required this.onClose,
    required this.onFlash,
    required this.onMode,
    required this.onShutter,
    required this.onFinish,
    super.key,
    this.lastCapturePath,
    this.onGallery,
    this.onRemoveLast,
    this.focusPoint,
    this.flashTick = 0,
    this.onPreviewTap,
    this.stackKey,
    this.flyPath,
  });

  final Widget preview;
  final ScanModeRules rules;
  final String title;
  final String guide;
  final bool flashOn;
  final int captureCount;
  final String? lastCapturePath;
  final bool canFinish;
  final bool showModes;
  final bool capturing;
  final VoidCallback onClose;
  final VoidCallback onFlash;
  final ValueChanged<ScanMode> onMode;
  final VoidCallback onShutter;
  final VoidCallback? onGallery;
  final VoidCallback onFinish;
  final VoidCallback? onRemoveLast;

  /// Tap-to-focus point as fractions of the well, shown as a ring.
  final Offset? focusPoint;

  /// Increment to play the white capture flash.
  final int flashTick;
  final ValueChanged<Offset>? onPreviewTap;

  /// Key on the page-stack widget so the captured thumbnail can fly to it.
  final GlobalKey? stackKey;

  /// Path of the just-captured image to fly into the stack (null = none).
  final String? flyPath;

  /// Frame shape for free-form documents (roughly a portrait page).
  static const double docAspect = 310 / 410;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final aspect = rules.aspectRatio ?? docAspect;
    return SafeArea(
      child: Column(
        children: [
          // ---- top controls ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x3),
            child: Row(
              children: [
                IconButton(
                  tooltip: l.commonClose,
                  onPressed: onClose,
                  icon: const AppIcon(AppIcons.close, color: Colors.white),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: _ink),
                  ),
                ),
                _FlashPill(on: flashOn, onTap: onFlash),
              ],
            ),
          ),
          // ---- preview well (3:4, what you see is what you capture) ----
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: Space.x1),
              color: const Color(0xFF2A2622),
              child: Stack(
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: PreviewGeometry.wellAspect,
                      child: PreviewWell(
                        preview: preview,
                        guideAspect: aspect,
                        focusPoint: focusPoint,
                        flashTick: flashTick,
                        onTap: onPreviewTap,
                        stackKey: stackKey,
                        flyPath: flyPath,
                      ),
                    ),
                  ),
                  Positioned(
                    left: Space.x4,
                    right: Space.x4,
                    bottom: Space.x5,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          guide,
                          textAlign: TextAlign.center,
                          style: context.text.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ---- modes + shutter ----
          ColoredBox(
            color: Colors.black,
            child: Padding(
              padding: const EdgeInsets.only(top: 14, bottom: Space.x3),
              child: Column(
                children: [
                  if (showModes) ...[
                    _ModePills(selected: rules.mode, onMode: onMode),
                    const SizedBox(height: Space.x4),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SizedBox(
                          width: 52,
                          height: 52,
                          child: onGallery == null
                              ? null
                              : Tooltip(
                                  message: l.homeImportGallery,
                                  child: Material(
                                    color: const Color(0xFF24272D),
                                    borderRadius: BorderRadius.circular(14),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: onGallery,
                                      child: const Center(child: AppIcon(AppIcons.gallery, color: _ink)),
                                    ),
                                  ),
                                ),
                        ),
                        _Shutter(onTap: capturing ? null : onShutter, busy: capturing),
                        SizedBox(
                          width: 52,
                          height: 52,
                          child: captureCount == 0
                              ? null
                              : _PageStack(
                                  key: stackKey,
                                  count: captureCount,
                                  path: lastCapturePath,
                                  onTap: canFinish ? onFinish : onRemoveLast,
                                  onLongPress: onRemoveLast,
                                  label: canFinish ? l.cameraReview(captureCount) : l.cameraRemoveLast,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const Color _ink = Color(0xFFF3F3F1);
const Color _inkMuted = Color(0xFFA6AAB2);

class _FlashPill extends StatelessWidget {
  const _FlashPill({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    return Semantics(
      button: true,
      label: on ? l.cameraFlashOn : l.cameraFlashOff,
      excludeSemantics: true,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: Sizes.tap,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(on ? AppIcons.flashOn : AppIcons.flashOff, size: 18, color: on ? c.accent : _ink),
                const SizedBox(width: 6),
                Text(
                  on ? l.cameraFlashOnShort : l.cameraFlashOffShort,
                  style: context.text.labelMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: _ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModePills extends StatelessWidget {
  const _ModePills({required this.selected, required this.onMode});

  final ScanMode selected;
  final ValueChanged<ScanMode> onMode;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Space.x4),
      child: Row(
        children: [
          for (final (i, m) in ScanMode.values.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Semantics(
              button: true,
              selected: m == selected,
              child: Material(
                color: m == selected ? c.accent : Colors.transparent,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onMode(m),
                  child: AnimatedContainer(
                    duration: Motion.normal,
                    height: 36,
                    padding: EdgeInsets.symmetric(horizontal: m == selected ? Space.x4 : Space.x3),
                    alignment: Alignment.center,
                    child: Text(
                      modeLabel(context, m),
                      style: context.text.labelLarge?.copyWith(
                        color: m == selected ? c.onAccent : _inkMuted,
                        fontWeight: m == selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Shutter extends StatefulWidget {
  const _Shutter({required this.onTap, required this.busy});
  final VoidCallback? onTap;
  final bool busy;

  @override
  State<_Shutter> createState() => _ShutterState();
}

class _ShutterState extends State<_Shutter> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy;
    return Semantics(
      button: true,
      label: context.l10n.cameraTakePhoto,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1,
          duration: Motion.fast,
          curve: Curves.easeOut,
          child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          padding: const EdgeInsets.all(5),
          child: AnimatedContainer(
            duration: Motion.fast,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: busy ? Colors.white.withValues(alpha: 0.5) : Colors.white,
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                  )
                : null,
          ),
          ),
        ),
      ),
    );
  }
}

/// Fanned stack of captured pages with the count badge.
class _PageStack extends StatelessWidget {
  const _PageStack({
    required this.count,
    required this.onTap,
    required this.label,
    super.key,
    this.onLongPress,
    this.path,
  });

  final int count;
  final String? path;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final file = path == null ? null : File(path!);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 6,
              top: 0,
              child: Transform.rotate(
                angle: 0.105, // 6°
                child: Container(
                  width: 40,
                  height: 50,
                  decoration: BoxDecoration(color: const Color(0xFFD5D7DB), borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
            Positioned(
              left: 6,
              top: 1,
              child: Container(
                width: 40,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F2EE),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: file != null && file.existsSync()
                    ? Image.file(file, fit: BoxFit.cover, cacheWidth: 120, gaplessPlayback: true)
                    : null,
              ),
            ),
            Positioned(
              right: -6,
              top: -8,
              // Bumps when the count changes.
              child: TweenAnimationBuilder<double>(
                key: ValueKey(count),
                tween: Tween(begin: 1.35, end: 1),
                duration: Motion.slow,
                curve: Curves.elasticOut,
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 24),
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.accent, borderRadius: Radii.pillR),
                  child: Text(
                    '$count',
                    style: context.text.labelMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w800, height: 1, color: c.onAccent),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four white corner brackets with rounded outer corners.
