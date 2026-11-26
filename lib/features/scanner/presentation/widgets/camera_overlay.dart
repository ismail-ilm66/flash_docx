import 'dart:io';

import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/camera_viewport.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/preview_geometry.dart';
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
    this.flyTick = 0,
    this.banner,
    this.onFlip,
    this.timerOn = false,
    this.onTimer,
    this.countdown,
    this.photoAspect = PreviewGeometry.defaultPhotoAspect,
    this.saving = false,
    this.ready = true,
    this.onUndo,
    this.onSettings,
    this.autoCapture = false,
    this.onAutoCapture,
    this.hd = false,
    this.onHd,
    this.outline,
    this.grid = false,
    this.level,
    this.captureProgress = 0,
    this.preparing = false,
    this.onSwipe,
  });

  /// Round 11, P1-3: ↶ removes the last photo (once there is one).
  final VoidCallback? onUndo;

  /// ⋮: camera settings (P1-6).
  final VoidCallback? onSettings;

  /// **A**: auto capture, amber when on (P1-8); **HD** (P1-9). Hidden when
  /// the callback is null.
  final bool autoCapture;
  final VoidCallback? onAutoCapture;
  final bool hd;
  final VoidCallback? onHd;

  /// The live page outline (P1-7), normalised to the preview.
  final Quad? outline;

  /// Rule-of-thirds lines on the preview.
  final bool grid;

  /// The tilt guide's level (P1-5): how far from flat, in degrees; null
  /// hides it.
  final double? level;

  /// Auto capture's ring on the shutter, 0..1.
  final double captureProgress;

  /// Pages are being finished: a small spinner on the stack (P1-2).
  final bool preparing;

  /// A swipe across the preview: +1 for the next mode, -1 for the previous.
  final ValueChanged<int>? onSwipe;

  /// The camera is live (round 10, P0-2). Until then the shutter is dimmed
  /// and can't be pressed, so a tap is never lost.
  final bool ready;

  /// Portrait aspect (width / height) of the photo: the preview box's shape.
  final double photoAspect;

  /// The shutter fired and the photo is being saved: "Hold still…".
  final bool saving;

  /// Passport photo only (P1-3.1): switch between back and front camera,
  /// and a 3 s self-timer. Hidden when null.
  final VoidCallback? onFlip;
  final bool timerOn;
  final VoidCallback? onTimer;

  /// Seconds left on the self-timer, shown large over the preview.
  final int? countdown;

  final Widget preview;
  final ScanModeRules rules;
  final String title;
  /// The hint over the modes; null shows none (round 11, P1-5).
  final String? guide;
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

  /// Increment to fly a page into the stack after a capture.
  final int flyTick;

  /// Storage / blur / dark notice shown above the hint.
  final Widget? banner;

  /// Round 7, P0-2: where the preview box and the frame go on this screen.
  static CameraLayout layoutFor(MediaQueryData mq, double photoAspect, {required bool modes}) =>
      CameraLayout.of(mq.size, mq.padding, photoAspect, modes: modes);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final mq = MediaQuery.of(context);
    // P1-4: Document has no frame guide; ID / passport frames are always
    // landscape and a constant in screen space.
    final aspect = rules.aspectRatio;
    final layout = layoutFor(mq, photoAspect, modes: showModes);
    final box = layout.box;
    return Stack(
      children: [
        // ---- preview: the whole photo, uncropped (round 7, P0-2) ----
        Positioned.fromRect(
          rect: box,
          child: CameraViewport(
            preview: preview,
            guideAspect: aspect,
            guideArea: layout.guideArea,
            focusPoint: focusPoint,
            flashTick: flashTick,
            onTap: onPreviewTap,
            stackKey: stackKey,
            flyTick: flyTick,
            saving: saving,
            outline: outline,
            grid: grid,
            level: level,
            onSwipe: onSwipe,
          ),
        ),
        if (countdown != null)
          Positioned.fromRect(
            rect: box,
            child: IgnorePointer(
              child: Center(
                child: Text(
                  '$countdown',
                  style: const TextStyle(fontSize: 120, fontWeight: FontWeight.w800, color: Colors.white, shadows: [Shadow(blurRadius: 24)]),
                ),
              ),
            ),
          ),
        // ---- top fade: ✕ · flash · A · HD · ⋮ (round 11), the title under ----
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(Space.x2, mq.padding.top + 10, Space.x2, Space.x4),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x00000000)],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _RoundButton(icon: AppIcons.close, label: l.commonClose, onTap: onClose, plain: true),
                    const Spacer(),
                    if (onTimer != null) ...[
                      _RoundButton(
                        icon: AppIcons.timer,
                        label: timerOn ? l.cameraTimerOn : l.cameraTimerOff,
                        active: timerOn,
                        onTap: onTimer!,
                      ),
                      const SizedBox(width: Space.x1),
                    ],
                    if (onFlip != null) ...[
                      _RoundButton(icon: AppIcons.flipCamera, label: l.cameraFlip, onTap: onFlip!),
                      const SizedBox(width: Space.x1),
                    ],
                    _RoundButton(
                      icon: flashOn ? AppIcons.flashOn : AppIcons.flashOff,
                      label: flashOn ? l.cameraFlashOn : l.cameraFlashOff,
                      active: flashOn,
                      onTap: onFlash,
                    ),
                    if (onAutoCapture != null) ...[
                      const SizedBox(width: Space.x1),
                      _RoundButton(text: l.cameraAutoShort, label: l.cameraAutoCapture, active: autoCapture, onTap: onAutoCapture!),
                    ],
                    if (onHd != null) ...[
                      const SizedBox(width: Space.x1),
                      _RoundButton(text: l.cameraHdShort, label: l.cameraHdPhotos, active: hd, onTap: onHd!),
                    ],
                    if (onSettings != null) ...[
                      const SizedBox(width: Space.x1),
                      _RoundButton(icon: AppIcons.more, label: l.cameraSettings, onTap: onSettings!),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                FitText(
                  title,
                  maxLines: 1,
                  style: context.text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: _ink),
                ),
              ],
            ),
          ),
        ),
        // ---- over the bottom of the box: notices, the hint, the modes ----
        Positioned(
          left: box.left,
          width: box.width,
          bottom: mq.size.height - box.bottom,
          child: IgnorePointer(
            ignoring: false,
            child: Container(
              padding: const EdgeInsets.only(top: Space.x6, bottom: CameraLayout.gap),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x8C000000)],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (banner != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, Space.x2),
                      child: banner,
                    ),
                  // Round 11: the hint only when needed (P1-5), else "Page
                  // found · hold still" while the outline is on a page.
                  SizedBox(
                    height: CameraLayout.hintChip,
                    child: Center(
                      child: guide != null
                          ? _Chip(text: guide!, level: level)
                          : outline != null
                          ? _Chip(text: l.cameraPageFound, accent: true)
                          : null,
                    ),
                  ),
                  if (showModes) ...[
                    const SizedBox(height: CameraLayout.gap),
                    _ModeStrip(selected: rules.mode, onMode: onMode),
                  ],
                ],
              ),
            ),
          ),
        ),
        // ---- below the box: Import · shutter · stack ----
        Positioned(
          left: 0,
          right: 0,
          top: box.bottom,
          bottom: mq.padding.bottom,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ↶ Undo once there is a page (P1-3), else Import.
                SizedBox(
                  width: 64,
                  height: 64,
                  child: captureCount > 0 && onUndo != null
                      ? _UndoButton(onTap: onUndo!)
                      : onGallery == null
                      ? null
                      : _ImportButton(onTap: onGallery!),
                ),
                AnimatedOpacity(
                  opacity: ready ? 1 : 0.6,
                  duration: Motion.fast,
                  child: _Shutter(onTap: capturing || !ready ? null : onShutter, busy: capturing && ready, progress: captureProgress),
                ),
                // The pages with their count and a clear Done (P1-4).
                SizedBox(
                  width: 64,
                  child: captureCount == 0
                      ? null
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 56,
                              height: 54,
                              child: _PageStack(
                                key: stackKey,
                                count: captureCount,
                                path: lastCapturePath,
                                busy: preparing,
                                onTap: canFinish ? onFinish : null,
                                onLongPress: onRemoveLast,
                                label: canFinish ? l.cameraDone : l.cameraRemoveLast,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _DoneButton(onTap: canFinish && !preparing ? onFinish : null),
                          ],
                        ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Import" (Photos / Files), 56 px, icon over label.
class _ImportButton extends StatelessWidget {
  const _ImportButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Semantics(
      button: true,
      label: l.homeImport,
      excludeSemantics: true,
      child: Material(
        color: const Color(0xFF24272D),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppIcon(AppIcons.gallery, color: _ink, size: 22),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  l.homeImport,
                  maxLines: 1,
                  style: context.text.labelSmall?.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: _ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const Color _ink = Color(0xFFF3F3F1);
const Color _inkMuted = Color(0xFFA6AAB2);

/// Round 11, P1-10: Passport · ID Card · Document · Passport photo,
/// scrolling sideways; the selected mode always snaps to the centre
/// (amber, bold, underlined). Tap a mode or swipe the strip.
class _ModeStrip extends StatefulWidget {
  const _ModeStrip({required this.selected, required this.onMode});

  final ScanMode selected;
  final ValueChanged<ScanMode> onMode;

  static const List<ScanMode> modes = [ScanMode.passport, ScanMode.idCard, ScanMode.document, ScanMode.photo];

  @override
  State<_ModeStrip> createState() => _ModeStripState();
}

class _ModeStripState extends State<_ModeStrip> {
  late final PageController _ctrl = PageController(
    viewportFraction: 0.3,
    initialPage: _ModeStrip.modes.indexOf(widget.selected).clamp(0, 3),
  );

  @override
  void didUpdateWidget(_ModeStrip old) {
    super.didUpdateWidget(old);
    final i = _ModeStrip.modes.indexOf(widget.selected);
    if (i >= 0 && _ctrl.hasClients && (_ctrl.page ?? i).round() != i) {
      _ctrl.animateToPage(i, duration: Motion.normal, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    // Capped like a nav bar label: the strip has a fixed height.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: SizedBox(
      height: CameraLayout.modePills,
      child: PageView.builder(
        controller: _ctrl,
        itemCount: _ModeStrip.modes.length,
        onPageChanged: (i) => widget.onMode(_ModeStrip.modes[i]),
        itemBuilder: (context, i) {
          final m = _ModeStrip.modes[i];
          final on = m == widget.selected;
          return Semantics(
            button: true,
            selected: on,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _ctrl.animateToPage(i, duration: Motion.normal, curve: Curves.easeOutCubic),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      m == ScanMode.photo ? l.toolPassportPhoto : modeLabel(context, m),
                      maxLines: 1,
                      style: context.text.labelLarge?.copyWith(
                        fontSize: 14,
                        color: on ? c.accent : _inkMuted,
                        fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedContainer(
                    duration: Motion.fast,
                    width: on ? 22 : 0,
                    height: 2.5,
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(2)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}

/// The hint (or "Page found · hold still") over the modes; with [level], a
/// small dot that turns green when the phone is flat (P1-5).
class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.level, this.accent = false});

  final String text;
  final double? level;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lvl = level;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lvl != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: lvl < 8 ? const Color(0xFF22C55E) : c.accent,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: context.text.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: accent ? c.accent : _ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ↶ Undo (P1-3), 64 dp, icon over label.
class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Semantics(
      button: true,
      label: l.cameraUndo,
      excludeSemantics: true,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: Material(
        color: const Color(0xFF24272D),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.undo_rounded, color: _ink, size: 24),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  l.cameraUndo,
                  maxLines: 1,
                  style: context.text.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: _ink),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// The filled amber Done under the page stack (P1-4).
class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: onTap == null ? c.accent.withValues(alpha: 0.5) : c.accent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 32,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                context.l10n.cameraDone,
                maxLines: 1,
                style: context.text.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w800, color: c.onAccent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Shutter extends StatefulWidget {
  const _Shutter({required this.onTap, required this.busy, this.progress = 0});
  final VoidCallback? onTap;
  final bool busy;

  /// Auto capture (P1-8): an amber ring that fills over 0.8 s.
  final double progress;

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
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.progress > 0)
                SizedBox(
                  width: 88,
                  height: 88,
                  child: CircularProgressIndicator(value: widget.progress, strokeWidth: 4, color: context.colors.accent),
                ),
              Container(
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
            ],
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
    this.busy = false,
  });

  /// Pages are being finished (round 11, P1-2): a small spinner on the top
  /// page instead of a box over the preview.
  final bool busy;
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (file != null && file.existsSync()) Image.file(file, fit: BoxFit.cover, cacheWidth: 120, gaplessPlayback: true),
                    if (busy)
                      const ColoredBox(
                        color: Color(0x66000000),
                        child: Center(
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        ),
                      ),
                  ],
                ),
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

/// A round icon button in the top bar (flip, timer); [label] is for screen
/// readers.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.label, required this.onTap, this.icon, this.text, this.active = false, this.plain = false});
  final AppIcons? icon;

  /// A letter button (A, HD) instead of an icon.
  final String? text;
  final String label;
  final VoidCallback onTap;
  final bool active;

  /// No disc behind it (✕).
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: plain ? Colors.transparent : (active ? c.accent.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.12)),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: Sizes.tap,
            height: Sizes.tap,
            child: Center(
              child: text != null
                  ? MediaQuery.withNoTextScaling(
                      child: Text(
                        text!,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: active ? c.accent : _ink),
                      ),
                    )
                  : AppIcon(icon!, size: 20, color: active ? c.accent : _ink),
            ),
          ),
        ),
      ),
    );
  }
}
