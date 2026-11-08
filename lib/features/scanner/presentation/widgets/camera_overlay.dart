import 'dart:io';

import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/camera_viewport.dart';
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
  });

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

  /// Increment to fly a page into the stack after a capture.
  final int flyTick;

  /// Storage / blur / dark notice shown above the hint.
  final Widget? banner;

  /// Heights from the artboard (round 4, P1-2).
  static const double topFade = 96;
  static const double bottomFade = 250;

  /// The visible part of the full-screen preview between the top bar and
  /// the controls, as fractions of the screen. The guide frame is centred in
  /// it; the camera page uses the same area to map the frame into the photo.
  static Rect guideAreaFor(MediaQueryData mq) {
    final h = mq.size.height;
    final top = mq.padding.top + 70;
    final bottom = h - mq.padding.bottom - bottomFade;
    return Rect.fromLTRB(0, top / h, 1, (bottom > top ? bottom : h) / h);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final mq = MediaQuery.of(context);
    // P1-4: Document has no frame guide; ID / passport frames are always
    // landscape and a constant in screen space.
    final aspect = rules.aspectRatio;
    return Stack(
      children: [
        // ---- preview: the whole screen, under a transparent status bar ----
        Positioned.fill(
          child: CameraViewport(
            preview: preview,
            guideAspect: aspect,
            guideArea: guideAreaFor(mq),
            focusPoint: focusPoint,
            flashTick: flashTick,
            onTap: onPreviewTap,
            stackKey: stackKey,
            flyTick: flyTick,
          ),
        ),
        if (countdown != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Text(
                  '$countdown',
                  style: const TextStyle(fontSize: 120, fontWeight: FontWeight.w800, color: Colors.white, shadows: [Shadow(blurRadius: 24)]),
                ),
              ),
            ),
          ),
        // ---- top fade: ✕ · title · flash ----
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: false,
            child: Container(
              height: topFade + mq.padding.top,
              padding: EdgeInsets.fromLTRB(Space.x2, mq.padding.top + 14, Space.x2, 0),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Color(0x00000000)],
                ),
              ),
              alignment: Alignment.topCenter,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: Sizes.tap,
                    height: Sizes.tap,
                    child: IconButton(
                      tooltip: l.commonClose,
                      onPressed: onClose,
                      icon: const AppIcon(AppIcons.close, color: _ink),
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: Sizes.tap,
                      child: Center(
                        child: FitText(
                          title,
                          maxLines: 1,
                          style: context.text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: _ink),
                        ),
                      ),
                    ),
                  ),
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
                  _FlashPill(on: flashOn, onTap: onFlash),
                ],
              ),
            ),
          ),
        ),
        // ---- hint chip (and notices) just above the bottom fade ----
        Positioned(
          left: Space.x4,
          right: Space.x4,
          bottom: mq.padding.bottom + bottomFade + 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (banner != null) ...[banner!, const SizedBox(height: Space.x2)],
              Container(
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
            ],
          ),
        ),
        // ---- bottom fade: modes, then Import · shutter · stack ----
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: bottomFade + mq.padding.bottom,
            padding: EdgeInsets.only(bottom: 28 + mq.padding.bottom),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xC7000000)],
                stops: [0, 0.32],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (showModes) ...[
                  _ModePills(selected: rules.mode, onMode: onMode),
                  const SizedBox(height: 22),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: onGallery == null ? null : _ImportButton(onTap: onGallery!),
                      ),
                      _Shutter(onTap: capturing ? null : onShutter, busy: capturing),
                      SizedBox(
                        width: 56,
                        height: 64,
                        child: captureCount == 0
                            ? null
                            : _PageStack(
                                key: stackKey,
                                count: captureCount,
                                path: lastCapturePath,
                                onTap: canFinish ? onFinish : onRemoveLast,
                                onLongPress: onRemoveLast,
                                label: canFinish ? l.cameraDone : l.cameraRemoveLast,
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
          for (final (i, m) in ScanMode.values.where((m) => m.isCameraMode).indexed) ...[
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

/// A round icon button in the top bar (flip, timer); [label] is for screen
/// readers.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, this.active = false});
  final AppIcons icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: active ? c.accent.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: Sizes.tap,
            height: Sizes.tap,
            child: Center(child: AppIcon(icon, size: 20, color: active ? c.accent : _ink)),
          ),
        ),
      ),
    );
  }
}
