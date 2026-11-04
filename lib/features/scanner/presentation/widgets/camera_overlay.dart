import 'dart:io';

import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// Everything drawn on top of the camera preview: top controls, card frame,
/// guide label, mode pills, shutter row.
class CameraOverlay extends StatelessWidget {
  const CameraOverlay({
    required this.rules,
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
    this.onFiles,
    this.onRemoveLast,
  });

  final ScanModeRules rules;
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
  final VoidCallback? onFiles;
  final VoidCallback onFinish;
  final VoidCallback? onRemoveLast;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final aspect = rules.aspectRatio;
    return SafeArea(
      child: Column(
        children: [
          // ---- top controls ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x1),
            child: Row(
              children: [
                _RoundIconButton(icon: AppIcons.close, onTap: onClose, tooltip: l.commonClose),
                const Spacer(),
                _RoundIconButton(
                  icon: flashOn ? AppIcons.flashOn : AppIcons.flashOff,
                  onTap: onFlash,
                  tooltip: flashOn ? l.cameraFlashOn : l.cameraFlashOff,
                  active: flashOn,
                ),
              ],
            ),
          ),
          // ---- frame + guide ----
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (aspect != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x8),
                    child: AspectRatio(
                      aspectRatio: aspect,
                      child: CustomPaint(painter: _CornerFramePainter(color: c.accent)),
                    ),
                  ),
                const SizedBox(height: Space.x5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: Radii.pillR,
                  ),
                  child: Text(guide, style: context.text.labelLarge?.copyWith(color: Colors.white)),
                ),
              ],
            ),
          ),
          // ---- modes ----
          if (showModes)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
              child: SegmentedPills<ScanMode>(
                values: ScanMode.values,
                selected: rules.mode,
                labelOf: (m) => modeLabel(context, m),
                onChanged: onMode,
              ),
            ),
          // ---- shutter row ----
          Container(
            padding: const EdgeInsets.fromLTRB(Space.x5, Space.x3, Space.x5, Space.x4),
            color: Colors.black.withValues(alpha: 0.6),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: onGallery == null
                      ? null
                      : Row(
                          children: [
                            _RoundIconButton(icon: AppIcons.gallery, onTap: onGallery!, tooltip: l.homeImportGallery),
                            if (onFiles != null)
                              _RoundIconButton(icon: AppIcons.files, onTap: onFiles!, tooltip: l.homeImportFiles, small: true),
                          ],
                        ),
                ),
                Expanded(
                  child: Center(
                    child: _Shutter(onTap: capturing ? null : onShutter, busy: capturing),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: captureCount == 0
                      ? null
                      : _PageStack(
                          count: captureCount,
                          path: lastCapturePath,
                          onTap: canFinish ? onFinish : onRemoveLast,
                          label: canFinish ? l.cameraDone : null,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = false,
    this.small = false,
  });

  final AppIcons icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = small ? 36.0 : Sizes.tap;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? c.accent : Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: AppIcon(
              icon,
              size: small ? 18 : 22,
              color: active ? c.onAccent : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.onTap, required this.busy});
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.navScan,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          padding: const EdgeInsets.all(5),
          child: AnimatedContainer(
            duration: Motion.fast,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: busy ? c.accent.withValues(alpha: 0.5) : c.accent,
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _PageStack extends StatelessWidget {
  const _PageStack({required this.count, required this.onTap, this.path, this.label});
  final int count;
  final String? path;
  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final file = path == null ? null : File(path!);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 56,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: Radii.smR,
                  border: Border.all(color: Colors.white70),
                ),
                clipBehavior: Clip.antiAlias,
                child: file != null && file.existsSync()
                    ? Image.file(file, fit: BoxFit.cover, cacheWidth: 120)
                    : null,
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: c.accent, borderRadius: Radii.pillR),
                  child: Text('$count', style: context.text.labelSmall?.copyWith(color: c.onAccent)),
                ),
              ),
            ],
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(label!, style: context.text.labelSmall?.copyWith(color: c.accent)),
          ],
        ],
      ),
    );
  }
}

class _CornerFramePainter extends CustomPainter {
  _CornerFramePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const len = 28.0;
    final r = Offset.zero & size;
    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o + Offset(dx * len, 0), paint);
      canvas.drawLine(o, o + Offset(0, dy * len), paint);
    }
    corner(r.topLeft, 1, 1);
    corner(r.topRight, -1, 1);
    corner(r.bottomRight, -1, -1);
    corner(r.bottomLeft, 1, -1);
    // Soft dim outside the frame
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.12);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), dim);
  }

  @override
  bool shouldRepaint(covariant _CornerFramePainter old) => old.color != color;
}
