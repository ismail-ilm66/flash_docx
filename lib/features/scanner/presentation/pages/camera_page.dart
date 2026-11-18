import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/services/storage_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/presentation/tools/tool_target.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/scanner/data/device_orientation_tracker.dart';
import 'package:flash_dox/features/scanner/data/import_service.dart';
import 'package:flash_dox/features/scanner/data/motion_monitor.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/presentation/add_pages.dart';
import 'package:flash_dox/features/scanner/presentation/bloc/scan_session_bloc.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/camera_overlay.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/preview_geometry.dart';
import 'package:flash_dox/l10n/gen/app_localizations.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// What a retake hands back to Adjust edges (P0-3).
class RetakeShot {
  const RetakeShot(this.path, {this.guide, this.capture});
  final String path;

  /// The ID / passport guide frame in photo coordinates (search area and
  /// fallback crop).
  final Quad? guide;

  /// What the camera knew at the shutter, for making it upright (P0-1).
  final CaptureMeta? capture;
}

/// The hint over the shutter, per entry point (round 5, P1-7). Without one,
/// it follows the scan mode.
enum CameraHint { document, idCard, passport, passportPhoto, signature, extractText }

class CameraArgs {
  const CameraArgs({
    this.mode,
    this.addToDocumentId,
    this.retake = false,
    this.retakeSide,
    this.returnPages = false,
    this.hint,
    this.tool,
  });

  final CameraHint? hint;

  /// A scan made for a Home tool (P1-4), handed on to the editor.
  final ToolTarget? tool;

  final ScanMode? mode;

  /// When set, finished pages are appended to this document.
  final String? addToDocumentId;

  /// Single capture that pops with a [RetakeShot] (used by "Retake"). The
  /// camera opens in [mode] with the frame and label of [retakeSide].
  final bool retake;
  final CardSide? retakeSide;

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
    final mode = a.mode ?? ScanMode.document;
    // Round 7, P0-3: only a new scan is kept as a draft.
    final draft = !a.retake && !a.returnPages && a.addToDocumentId == null && a.tool == null;
    return BlocProvider(
      create: (_) => getIt<ScanSessionBloc>(param1: mode, param2: draft),
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
  final DeviceOrientationTracker _orientation = getIt<DeviceOrientationTracker>();
  CameraController? _controller;
  bool _permissionDenied = false;
  bool _initializing = true;
  bool _capturing = false;

  /// Passport photo (P1-3.1): the lens in use, the 3 s self-timer and its
  /// countdown.
  CameraLensDirection _lens = CameraLensDirection.back;
  bool _timerOn = false;
  int? _countdown;

  bool get _selfieTools => widget.args.hint == CameraHint.passportPhoto;

  // Feedback + focus state (P0-4 / P0-5).
  final GlobalKey _stackKey = GlobalKey();
  final AudioPlayer _shutterPlayer = AudioPlayer();
  Offset? _focusPoint; // fractions of the preview well
  DateTime? _focusedAt;
  int _flashTick = 0;
  int _flyTick = 0;
  Timer? _focusRingTimer;
  StorageLevel _storage = StorageLevel.ok;

  /// Round 7, P0-1: the gyroscope shows "Hold still" while the phone moves
  /// (never blocks the shutter) and tells focus when to go back to the page.
  final MotionMonitor _motion = MotionMonitor();
  StreamSubscription<GyroscopeEvent>? _gyro;
  Timer? _focusTimer;
  bool _moving = false;

  /// The photo is being saved after the tap: "Hold still…" on the preview.
  bool _saving = false;

  /// Portrait aspect (width / height) of the capture, or 3:4 until known.
  double get _photoAspect {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return PreviewGeometry.defaultPhotoAspect;
    }
    return 1 / c.value.aspectRatio;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // P1-4: the camera screen is portrait only; EXIF uprights the photos.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _orientation.start();
    unawaited(_init(lens: _lens));
    unawaited(_checkStorage());
    unawaited(_loadShutterSound());
    _gyro = gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval).listen(
      (e) {
        if (_motion.add((x: e.x, y: e.y, z: e.z, at: e.timestamp)) && mounted) {
          setState(() => _moving = _motion.isMoving);
        }
      },
      onError: (Object _) {}, // no gyroscope: no hint
      cancelOnError: true,
    );
    // Focus before the tap: continuous autofocus, and every ~1.5 s, if the
    // phone moved, focus and exposure go back to the page.
    _focusTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _refocusOnPage());
  }

  /// Preloaded so the click is heard with the flash, not after it.
  Future<void> _loadShutterSound() async {
    try {
      await _shutterPlayer.setReleaseMode(ReleaseMode.stop);
      await _shutterPlayer.setSource(AssetSource('sounds/shutter.wav'));
      await _shutterPlayer.setVolume(0.9);
    } catch (e) {
      debugPrint('[capture] shutter sound: $e');
    }
  }

  /// The page centre: the ID / passport frame, else the middle of the
  /// preview. Skipped right after a tap-to-focus, while shooting, and when
  /// the phone hasn't moved (re-aiming a steady phone only makes the lens
  /// hunt).
  Future<void> _refocusOnPage() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    final tapped = _focusedAt != null && DateTime.now().difference(_focusedAt!) < const Duration(seconds: 5);
    if (tapped || !_motion.takeFocusRefresh()) return;
    final point = _cardFocusPoint() ?? const Offset(0.5, 0.5);
    await _trySet(() => c.setFocusPoint(point));
    await _trySet(() => c.setExposurePoint(point));
  }

  Future<void> _checkStorage() async {
    final level = await getIt<StorageService>().level();
    debugPrint('[capture] storage level $level');
    if (mounted) setState(() => _storage = level);
  }

  Future<void> _init({CameraLensDirection lens = CameraLensDirection.back}) async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _initializing = false);
        return;
      }
      // The back camera unless the passport photo flip asked for the front.
      final back = cams.firstWhere(
        (c) => c.lensDirection == lens,
        orElse: () => cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first),
      );
      // Round 7, P0-1/P0-2: 3840 × 2160 instead of the full 16 MP sensor.
      // Pages are resized to 3000 px anyway, and old phones save it much
      // faster. Preview and photo share the 16:9 shape, and the preview is
      // shown whole, so what you see is what you get.
      final ctrl = CameraController(
        back,
        ResolutionPreset.ultraHigh,
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
      // A new controller (resume, lens flip) starts at 1×: apply the mode again.
      _cameraMode = null;
      final session = context.read<ScanSessionBloc>().state;
      await _applyFlash(session.flashOn);
      await _applyModeCamera(session.mode);
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

  /// P1-3.1: reopen the camera on the other lens.
  Future<void> _flip() async {
    if (_capturing || _countdown != null) return;
    final old = _controller;
    setState(() {
      _controller = null;
      _initializing = true;
      _lens = _lens == CameraLensDirection.back ? CameraLensDirection.front : CameraLensDirection.back;
    });
    await old?.dispose();
    if (mounted) await _init(lens: _lens);
  }

  /// The shutter: straight away, or after the 3 s self-timer (P1-3.1).
  Future<void> _shutter() async {
    if (_countdown != null) return;
    if (!_timerOn) return _capture();
    for (var left = 3; left > 0; left--) {
      if (!mounted) return;
      setState(() => _countdown = left);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    setState(() => _countdown = null);
    await _capture();
  }

  Future<void> _trySet(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {
      // Not every device supports every control; ignore.
    }
  }

  /// Tap-to-focus: focus and exposure jump to the tapped point.
  Future<void> _onPreviewTap(Offset screen) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final photo = PreviewGeometry.viewportToPhoto(
      screen,
      photoAspect: _photoAspect,
      viewport: _layout.box.size,
    );
    setState(() => _focusPoint = screen);
    _focusedAt = DateTime.now();
    _focusRingTimer?.cancel();
    _focusRingTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusPoint = null);
    });
    // ID / passport: every tap refocuses on the card frame (P0-2).
    final target = _cardFocusPoint() ?? photo;
    await _trySet(() => c.setFocusPoint(target));
    await _trySet(() => c.setExposurePoint(target));
  }

  /// Sound, haptic and the white flash — before `takePicture()` (P0-C).
  void _captureFeedback() {
    unawaited(HapticFeedback.mediumImpact());
    if (getIt<PrefsService>().shutterSound) {
      unawaited(
        _shutterPlayer.seek(Duration.zero).then((_) => _shutterPlayer.resume()).catchError((Object _) {}),
      );
    }
    setState(() {
      _flashTick++;
      _saving = true;
    });
  }

  ScanMode? _cameraMode;

  /// ID / passport zoom. Round 4 (P0-2) used 1.5× against blur; users had
  /// to hold the phone too far away, so 14 Nov 2026 it came down 20 %.
  static const _cardZoom = 1.2;

  /// P0-2: [_cardZoom] in ID / passport (or the device maximum if lower) so
  /// the card fills more of the sensor; 1× for Document. Focus and exposure
  /// go to the frame centre.
  Future<void> _applyModeCamera(ScanMode mode) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || mode == _cameraMode) return;
    _cameraMode = mode;
    final card = ScanModeRules.of(mode).aspectRatio != null;
    try {
      final max = await c.getMaxZoomLevel();
      final min = await c.getMinZoomLevel();
      await c.setZoomLevel((card ? math.min(_cardZoom, max) : 1.0).clamp(min, max));
    } catch (_) {}
    final focus = _cardFocusPoint();
    if (focus != null) {
      await _trySet(() => c.setFocusPoint(focus));
      await _trySet(() => c.setExposurePoint(focus));
    } else {
      await _trySet(() => c.setFocusPoint(null));
      await _trySet(() => c.setExposurePoint(null));
    }
  }

  /// Centre of the ID / passport frame in photo coordinates; null in
  /// Document mode.
  Offset? _cardFocusPoint() {
    if (!mounted) return null;
    final aspect = context.read<ScanSessionBloc>().state.rules.aspectRatio;
    if (aspect == null) return null;
    final layout = _layout;
    final q = PreviewGeometry.guideQuad(
      aspect,
      photoAspect: _photoAspect,
      viewport: layout.box.size,
      area: layout.guideArea,
    );
    final pts = q.points;
    return Offset(
      pts.map((p) => p.x).reduce((a, b) => a + b) / 4,
      pts.map((p) => p.y).reduce((a, b) => a + b) / 4,
    );
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
      unawaited(_init(lens: _lens));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orientation.stop();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _focusRingTimer?.cancel();
    _focusTimer?.cancel();
    unawaited(_gyro?.cancel());
    _shutterPlayer.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// Round 7, P0-1: the photo is taken the moment the shutter is tapped.
  /// No waiting for the phone to hold still and no focus call here (focus
  /// is kept on the page before the tap). Within a frame: white flash,
  /// sound, vibration, then "Hold still…" until the file is saved, then the
  /// page flies to the stack. Everything else runs in the session's
  /// background queue (P0-C).
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
    final total = Stopwatch()..start();
    setState(() => _capturing = true);
    _captureFeedback();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => debugPrint('[perf] shutter tap → flash on screen ${total.elapsedMilliseconds} ms'),
    );
    try {
      // How the phone is held right now (round 5, P0-1): from the
      // accelerometer, since the plugin's orientation follows the UI, which
      // is locked to portrait. Applied with the sensor angle at ingest.
      final capture = CaptureMeta(
        sensorOrientation: c.description.sensorOrientation,
        deviceTurns: _orientation.turns,
        frontCamera: c.description.lensDirection == CameraLensDirection.front,
      );
      final shot = await c.takePicture();
      debugPrint('[perf] shutter tap → photo saved ${total.elapsedMilliseconds} ms');
      if (!mounted) return;
      // The guide frame in photo coordinates: searched first, and the
      // fallback crop if detection finds nothing (ID / passport only).
      final guideAspect = bloc.state.rules.aspectRatio;
      final layout = _layout;
      final guide = guideAspect == null
          ? null
          : PreviewGeometry.guideQuad(
              guideAspect,
              photoAspect: _photoAspect,
              viewport: layout.box.size,
              area: layout.guideArea,
            );
      if (widget.args.retake) {
        context.pop(RetakeShot(shot.path, guide: guide, capture: capture));
        return;
      }
      bloc.add(SessionCaptured(shot.path, guide: guide, capture: capture));
      setState(() {
        _saving = false;
        _flyTick++;
      });
      // ID card (2 sides) / passport (1 page) finish by themselves.
      if (bloc.state.isComplete) bloc.add(const SessionFinished());
    } catch (e) {
      debugPrint('[capture] failed: $e');
      if (mounted) context.showSnack(context.l10n.errorImage, error: true);
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
          _saving = false;
        });
      }
    }
  }

  /// Where the preview box and the frame are (round 7, P0-2).
  CameraLayout get _layout => CameraOverlay.layoutFor(MediaQuery.of(context), _photoAspect, modes: _showModes);

  bool get _showModes => !widget.args.retake && !widget.args.returnPages && widget.args.addToDocumentId == null;

  Widget? _banner(BuildContext context, ScanSessionState s) {
    final l = context.l10n;
    final bloc = context.read<ScanSessionBloc>();
    final n = s.notice;
    if (n != null) {
      return switch (n.kind) {
        NoticeKind.blurryCard => NoticeBanner(
          text: l.cameraCardBlurry,
          icon: AppIcons.warning,
          actions: [
            (
              l.cameraRetake,
              () => bloc.add(SessionRetakeRequested(n.captureId)),
            ),
            (l.cameraKeep, () => bloc.add(const SessionNoticeDismissed())),
          ],
        ),
        NoticeKind.blurry => NoticeBanner(
          text: l.cameraBlurryTitle,
          icon: AppIcons.warning,
          actions: [
            (
              l.cameraRetake,
              () => bloc.add(SessionRetakeRequested(n.captureId)),
            ),
            (l.cameraKeep, () => bloc.add(const SessionNoticeDismissed())),
          ],
        ),
        NoticeKind.unreadable => NoticeBanner(
          text: l.cameraUnreadable,
          icon: AppIcons.warning,
          actions: [
            (
              l.cameraRetake,
              () => bloc.add(SessionRetakeRequested(n.captureId)),
            ),
          ],
        ),
        NoticeKind.dark => NoticeBanner(
          text: l.cameraDark,
          icon: AppIcons.flashOn,
          actions: [
            (l.commonOk, () => bloc.add(const SessionNoticeDismissed())),
          ],
        ),
      };
    }
    return switch (_storage) {
      StorageLevel.critical => NoticeBanner(
        text: l.cameraStorageFull,
        icon: AppIcons.storage,
      ),
      StorageLevel.low => NoticeBanner(
        text: l.cameraStorageLow,
        icon: AppIcons.storage,
      ),
      StorageLevel.ok => null,
    };
  }

  /// "Import": Photos or Files, then the same pipeline as the camera.
  Future<void> _importFromSheet() async {
    final source = await pickPageSource(context, camera: false);
    if (source == null || !mounted) return;
    await _import(gallery: source == PageSource.photos);
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
      tool: widget.args.tool,
      blurryPages: s.blurryPages,
    );
    context.pushReplacement(Routes.adjust, extra: args);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return BlocConsumer<ScanSessionBloc, ScanSessionState>(
      listenWhen: (a, b) =>
          a.status != b.status || a.flashOn != b.flashOn || a.mode != b.mode,
      listener: (context, s) {
        if (s.status == SessionStatus.ready) _onReady(context, s);
        if (s.status == SessionStatus.failed) {
          context.showSnack(failureMessage(context, s.failure), error: true);
        }
        unawaited(_applyFlash(s.flashOn));
        unawaited(_applyModeCamera(s.mode));
      },
      builder: (context, s) {
        // "Document · 3 pages"; ID cards name the side being taken.
        final side = widget.args.retake ? widget.args.retakeSide : s.nextSide;
        final title = side != null
            ? '${modeLabel(context, s.mode)} · ${side == CardSide.back ? l.cameraGuideBack : l.cameraGuideFront}'
            : widget.args.retake
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
                  // The cropped page once processed (P0-3); a placeholder before.
                  lastCapturePath: s.captures.lastOrNull?.thumb,
                  canFinish: s.canFinish && !widget.args.retake,
                  showModes: _showModes,
                  photoAspect: _photoAspect,
                  saving: _saving,
                  capturing:
                      _capturing ||
                      s.status == SessionStatus.preparing ||
                      _storage == StorageLevel.critical,
                  onClose: () => Navigator.of(context).maybePop(),
                  onFlash: () => context.read<ScanSessionBloc>().add(
                    const SessionFlashToggled(),
                  ),
                  onMode: (m) => context.read<ScanSessionBloc>().add(
                    SessionModeChanged(m),
                  ),
                  onShutter: _shutter,
                  onFlip: _selfieTools ? _flip : null,
                  onTimer: _selfieTools ? () => setState(() => _timerOn = !_timerOn) : null,
                  timerOn: _timerOn,
                  countdown: _countdown,
                  onGallery: widget.args.retake ? null : _importFromSheet,
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
                    progress: s.waitingForQueue && s.count > 0
                        ? s.processed / s.count
                        : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _guideText(AppLocalizations l, ScanSessionState s) {
    // Round 7, P0-1: while the phone moves (a hint, never a wait); round 6:
    // after a dark shot until the flash is on or a shot is bright enough.
    if (_moving) return l.cameraHoldStill;
    if (s.lowLight) return l.cameraLowLight;
    final hint = widget.args.hint ??
        switch (s.guide) {
          GuideLabel.documentPage => CameraHint.document,
          GuideLabel.front || GuideLabel.back => CameraHint.idCard,
          GuideLabel.passport => CameraHint.passport,
        };
    return cameraHintText(l, hint);
  }

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
    // Round 7, P0-2: the whole preview in a box of its own shape, never
    // cover-cropped: the photo shows exactly what's on screen.
    return FittedBox(
      child: SizedBox(
        width: 1000,
        height: 1000 / _photoAspect,
        child: CameraPreview(c),
      ),
    );
  }
}

/// Storage, blur and low-light notices above the camera controls.
String cameraHintText(AppLocalizations l, CameraHint hint) => switch (hint) {
      CameraHint.document => l.cameraHintDocument,
      CameraHint.idCard => l.cameraHintCard,
      CameraHint.passport => l.cameraHintPassport,
      CameraHint.passportPhoto => l.cameraHintPassportPhoto,
      CameraHint.signature => l.cameraHintSignature,
      CameraHint.extractText => l.cameraHintExtractText,
    };
