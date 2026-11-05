import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/services/storage_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/scanner/data/import_service.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/presentation/bloc/scan_session_bloc.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/camera_overlay.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/preview_geometry.dart';
import 'package:flash_dox/l10n/gen/app_localizations.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class CameraArgs {
  const CameraArgs({
    this.mode,
    this.addToDocumentId,
    this.retake = false,
    this.returnPages = false,
  });

  final ScanMode? mode;

  /// When set, finished pages are appended to this document.
  final String? addToDocumentId;

  /// Single capture that pops with the new file path (used by "Retake").
  final bool retake;

  /// Pops with the prepared draft pages instead of opening Adjust edges
  /// (adding pages to a scan that is already being edited).
  final bool returnPages;
}

class CameraPage extends StatelessWidget {
  const CameraPage({super.key, this.args});

  final CameraArgs? args;

  @override
  Widget build(BuildContext context) {
    final a = args ?? const CameraArgs();
    final mode = a.retake ? ScanMode.document : a.mode;
    return BlocProvider(
      create: (_) => getIt<ScanSessionBloc>(param1: mode),
      child: _CameraView(args: a),
    );
  }
}

class _CameraView extends StatefulWidget {
  const _CameraView({required this.args});
  final CameraArgs args;

  @override
  State<_CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<_CameraView> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _permissionDenied = false;
  bool _initializing = true;
  bool _capturing = false;

  // Feedback + focus state (P0-4 / P0-5).
  final GlobalKey _stackKey = GlobalKey();
  final AudioPlayer _shutterPlayer = AudioPlayer();
  Offset? _focusPoint; // fractions of the preview well
  DateTime? _focusedAt;
  int _flashTick = 0;
  int _flyTick = 0;
  Timer? _focusRingTimer;
  StorageLevel _storage = StorageLevel.ok;

  /// Portrait aspect (width / height) of the capture, or 3:4 until known.
  double get _photoAspect {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return PreviewGeometry.wellAspect;
    return 1 / c.value.aspectRatio;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // P1-4: the camera screen is portrait only; EXIF uprights the photos.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    unawaited(_init());
    unawaited(_checkStorage());
  }

  Future<void> _checkStorage() async {
    final level = await getIt<StorageService>().level();
    debugPrint('[capture] storage level $level');
    if (mounted) setState(() => _storage = level);
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _initializing = false);
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      // `max` is the sensor's full 4:3 photo size on both platforms, which
      // matches the 3:4 preview well: what you see is what you capture.
      final ctrl = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await _trySet(() => ctrl.setFocusMode(FocusMode.auto));
      await _trySet(() => ctrl.setExposureMode(ExposureMode.auto));
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      _controller = ctrl;
      await _applyFlash(context.read<ScanSessionBloc>().state.flashOn);
      setState(() => _initializing = false);
    } on CameraException catch (e) {
      setState(() {
        _initializing = false;
        _permissionDenied =
            e.code.toLowerCase().contains('accessdenied') ||
            e.code.toLowerCase().contains('permission');
      });
    } catch (_) {
      setState(() => _initializing = false);
    }
  }

  Future<void> _trySet(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {
      // Not every device supports every control; ignore.
    }
  }

  /// Tap-to-focus: focus and exposure jump to the tapped point.
  Future<void> _onPreviewTap(Offset well) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final photo = PreviewGeometry.wellToPhoto(well, photoAspect: _photoAspect);
    setState(() => _focusPoint = well);
    _focusedAt = DateTime.now();
    _focusRingTimer?.cancel();
    _focusRingTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusPoint = null);
    });
    await _trySet(() => c.setFocusPoint(photo));
    await _trySet(() => c.setExposurePoint(photo));
  }

  /// Continuous autofocus is always on. Only right after a tap-to-focus
  /// do we hold the shutter until focus has had ~300 ms to settle (A3).
  Future<void> _waitForTapFocus() async {
    final at = _focusedAt;
    if (at == null) return;
    final left = const Duration(milliseconds: 300) - DateTime.now().difference(at);
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  /// Sound, haptic and the white flash — before `takePicture()` (P0-C).
  void _captureFeedback() {
    unawaited(HapticFeedback.mediumImpact());
    if (getIt<PrefsService>().shutterSound) {
      unawaited(_shutterPlayer.play(AssetSource('sounds/shutter.wav'), volume: 0.9));
    }
    setState(() => _flashTick++);
  }

  Future<void> _applyFlash(bool on) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setFlashMode(on ? FlashMode.always : FlashMode.off);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
      if (c == null) return;
      c.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _initializing = true);
      unawaited(_init());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _focusRingTimer?.cancel();
    _shutterPlayer.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// The shutter path does only: feedback → takePicture() → queue → ready
  /// (P0-C). Moving, uprighting, detection and previews run in the session's
  /// background queue.
  Future<void> _capture() async {
    final c = _controller;
    final bloc = context.read<ScanSessionBloc>();
    if (c == null ||
        !c.value.isInitialized ||
        _capturing ||
        _storage == StorageLevel.critical ||
        !bloc.state.canCapture) {
      return;
    }
    setState(() => _capturing = true);
    final total = Stopwatch()..start();
    try {
      await _waitForTapFocus();
      _captureFeedback();
      final take = Stopwatch()..start();
      final shot = await c.takePicture();
      take.stop();
      if (!mounted) return;
      if (widget.args.retake) {
        context.pop(shot.path);
        return;
      }
      // The guide frame in photo coordinates: searched first, and the
      // fallback crop if detection finds nothing (ID / passport only).
      final guideAspect = bloc.state.rules.aspectRatio;
      final guide = guideAspect == null
          ? null
          : PreviewGeometry.guideQuad(guideAspect, photoAspect: _photoAspect);
      bloc.add(SessionCaptured(shot.path, guide: guide));
      setState(() => _flyTick++);
      debugPrint(
        '[capture] takePicture ${take.elapsedMilliseconds} ms; '
        'shutter ready again after ${total.elapsedMilliseconds} ms',
      );
      // ID card (2 sides) / passport (1 page) finish by themselves.
      if (bloc.state.isComplete) bloc.add(const SessionFinished());
    } catch (e) {
      debugPrint('[capture] failed: $e');
      if (mounted) context.showSnack(context.l10n.errorImage, error: true);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Widget? _banner(BuildContext context, ScanSessionState s) {
    final l = context.l10n;
    final bloc = context.read<ScanSessionBloc>();
    final n = s.notice;
    if (n != null) {
      return switch (n.kind) {
        NoticeKind.blurry => _NoticeBanner(
            text: l.cameraBlurryTitle,
            icon: AppIcons.warning,
            actions: [
              (l.cameraRetake, () => bloc.add(SessionRetakeRequested(n.captureId))),
              (l.cameraKeep, () => bloc.add(const SessionNoticeDismissed())),
            ],
          ),
        NoticeKind.unreadable => _NoticeBanner(
            text: l.cameraUnreadable,
            icon: AppIcons.warning,
            actions: [(l.cameraRetake, () => bloc.add(SessionRetakeRequested(n.captureId)))],
          ),
        NoticeKind.dark => _NoticeBanner(
            text: l.cameraDark,
            icon: AppIcons.flashOn,
            actions: [(l.commonOk, () => bloc.add(const SessionNoticeDismissed()))],
          ),
      };
    }
    return switch (_storage) {
      StorageLevel.critical => _NoticeBanner(text: l.cameraStorageFull, icon: AppIcons.storage),
      StorageLevel.low => _NoticeBanner(text: l.cameraStorageLow, icon: AppIcons.storage),
      StorageLevel.ok => null,
    };
  }

  Future<void> _import({required bool gallery}) async {
    final svc = getIt<ImportService>();
    final r = gallery ? await svc.fromGallery() : await svc.fromFiles();
    if (!mounted) return;
    r.fold(
      (f) {
        if (f is! CancelledFailure) {
          context.showSnack(failureMessage(context, f), error: true);
        }
      },
      (paths) => context.read<ScanSessionBloc>().add(SessionImported(paths)),
    );
  }

  void _onReady(BuildContext context, ScanSessionState s) {
    final pages = s.result!;
    if (widget.args.returnPages) {
      context.pop(pages);
      return;
    }
    final args = EditorArgs(
      pages: pages,
      mode: s.mode,
      documentId: widget.args.addToDocumentId,
      addingPages: widget.args.addToDocumentId != null,
    );
    context.pushReplacement(Routes.adjust, extra: args);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return BlocConsumer<ScanSessionBloc, ScanSessionState>(
      listenWhen: (a, b) => a.status != b.status || a.flashOn != b.flashOn,
      listener: (context, s) {
        if (s.status == SessionStatus.ready) _onReady(context, s);
        if (s.status == SessionStatus.failed) {
          context.showSnack(failureMessage(context, s.failure), error: true);
        }
        unawaited(_applyFlash(s.flashOn));
      },
      builder: (context, s) {
        final title = widget.args.retake
            ? l.adjustRetake
            : s.count == 0
            ? modeLabel(context, s.mode)
            : '${modeLabel(context, s.mode)} · ${l.pagesCount(s.count)}';
        final guard =
            !widget.args.retake &&
            s.count > 0 &&
            s.status != SessionStatus.ready;
        return DiscardScanGuard(
          guard: guard,
          pageCount: s.count,
          onDiscard: () {
            context.read<ScanSessionBloc>().add(const SessionReset());
            context.pop();
          },
          child: AppScaffold(
            forceDark: true,
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                CameraOverlay(
                  preview: _preview(context),
                  rules: s.rules,
                  title: title,
                  guide: _guideText(l, s),
                  flashOn: s.flashOn,
                  captureCount: s.count,
                  // The 1200 px preview once processed; a placeholder before.
                  lastCapturePath: s.captures.lastOrNull?.thumbPath(getIt<FileStore>()),
                  canFinish: s.canFinish && !widget.args.retake,
                  showModes:
                      !widget.args.retake &&
                      !widget.args.returnPages &&
                      widget.args.addToDocumentId == null,
                  capturing: _capturing ||
                      s.status == SessionStatus.preparing ||
                      _storage == StorageLevel.critical,
                  onClose: () => Navigator.of(context).maybePop(),
                  onFlash: () => context.read<ScanSessionBloc>().add(
                    const SessionFlashToggled(),
                  ),
                  onMode: (m) => context.read<ScanSessionBloc>().add(
                    SessionModeChanged(m),
                  ),
                  onShutter: _capture,
                  onGallery: widget.args.retake
                      ? null
                      : () => _import(gallery: true),
                  onFinish: () => context.read<ScanSessionBloc>().add(
                    const SessionFinished(),
                  ),
                  onRemoveLast: s.count == 0
                      ? null
                      : () => context.read<ScanSessionBloc>().add(
                          SessionCaptureRemoved(s.count - 1),
                        ),
                  focusPoint: _focusPoint,
                  flashTick: _flashTick,
                  onPreviewTap: _onPreviewTap,
                  stackKey: _stackKey,
                  flyTick: _flyTick,
                  banner: _banner(context, s),
                ),
                if (s.status == SessionStatus.preparing)
                  ProgressOverlay(
                    label: s.waitingForQueue && s.count > 0
                        ? l.cameraPreparingProgress(s.processed, s.count)
                        : l.sharePreparing,
                    progress: s.waitingForQueue && s.count > 0 ? s.processed / s.count : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _guideText(AppLocalizations l, ScanSessionState s) =>
      switch (s.guide) {
        GuideLabel.documentPage => l.cameraGuideDocument(s.count + 1),
        GuideLabel.front => l.cameraGuideFront,
        GuideLabel.back => l.cameraGuideBack,
        GuideLabel.passport => l.cameraGuidePassport,
      };

  Widget _preview(BuildContext context) {
    final c = _controller;
    final l = context.l10n;
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_permissionDenied || c == null) {
      return EmptyState(
        icon: AppIcons.camera,
        title: l.cameraPermissionTitle,
        body: l.cameraPermissionBody,
        action: SecondaryButton(
          label: l.cameraImportInstead,
          icon: AppIcons.gallery,
          expand: false,
          onPressed: () => _import(gallery: true),
        ),
      );
    }
    // Cover-fit the 4:3 capture into the 3:4 well (an exact fit on most
    // devices; a hair of cropping on the rest, see PreviewGeometry).
    final portraitAspect = 1 / c.value.aspectRatio;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 1000,
          height: 1000 / portraitAspect,
          child: CameraPreview(c),
        ),
      ),
    );
  }
}

/// Storage, blur and low-light notices above the camera controls.
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.text, required this.icon, this.actions = const []});

  final String text;
  final AppIcons icon;
  final List<(String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: const Color(0xE6202226),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x1, Space.x2),
        child: Row(
          children: [
            AppIcon(icon, size: 20, color: c.accent),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(text, style: context.text.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            for (final (label, onTap) in actions)
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(foregroundColor: c.accent, minimumSize: const Size(Sizes.tap, Sizes.tap)),
                child: Text(label),
              ),
          ],
        ),
      ),
    );
  }
}
