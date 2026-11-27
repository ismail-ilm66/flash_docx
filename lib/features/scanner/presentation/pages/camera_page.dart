import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:camerawesome/camerawesome_plugin.dart' as aw;
import 'package:camerawesome/pigeon.dart' as awp;
import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/app_router.dart' show rootNavigatorKey;
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/perf/debug_switches.dart';
import 'package:flash_dox/core/perf/perf_log.dart';
import 'package:flash_dox/core/services/device_profile.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/services/storage_service.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/presentation/tools/tool_target.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/photo/presentation/photo_crop_page.dart';
import 'package:flash_dox/features/scanner/data/device_orientation_tracker.dart';
import 'package:flash_dox/features/scanner/data/import_service.dart';
import 'package:flash_dox/features/scanner/data/live_page_detector.dart';
import 'package:flash_dox/features/scanner/data/motion_monitor.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/domain/live_outline.dart';
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
enum CameraHint {
  document,
  idCard,
  passport,
  passportPhoto,
  signature,
  extractText,
}

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
    final draft =
        !a.retake &&
        !a.returnPages &&
        a.addToDocumentId == null &&
        a.tool == null;
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
  final DeviceOrientationTracker _orientation =
      getIt<DeviceOrientationTracker>();

  /// Round 11c, B1: camerawesome. Its widget owns the camera; [_cam] is its
  /// photo state once the preview runs. A new [_camKey] opens the camera
  /// again (lens flip, back from the background); [_camOn] false closes it.
  aw.PhotoCameraState? _cam;
  int _camKey = 0;
  bool _camOn = false;
  aw.SensorConfig? _sensorConfig;

  /// Where the next photo is written (camerawesome asks when it saves).
  String? _nextShot;

  /// The analysis frame's turn to the portrait screen, learned while the
  /// phone is upright (the stream follows how the phone is held).
  int? _portraitRotation;
  bool _permissionDenied = false;
  bool _initializing = true;
  bool _capturing = false;

  /// Passport photo (P1-3.1): the lens in use, the 3 s self-timer and its
  /// countdown.
  bool _front = false;
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

  // ---- round 11 (section G) ----
  final PrefsService _prefs = getIt<PrefsService>();

  /// Camera settings (⋮), saved.
  late bool _autoCapture = _prefs.autoCapture;
  late bool _hd = _prefs.hdPhotos;
  late bool _tiltGuide = _prefs.tiltGuide;
  late bool _grid = _prefs.grid;

  /// Round 11b, P0-15: the live outline (reference `LiveOutline`: eased,
  /// shown after 2 frames, hidden after 4 misses) and auto capture.
  LivePageDetector? _live;
  StreamSubscription<Quad?>? _liveSub;
  bool _streaming = false;
  Quad? _outline;
  double _autoProgress = 0;
  LiveOutline? _tracker;
  final Stopwatch _clock = Stopwatch()..start();

  /// When a page was last seen (P0-16: "Hold the phone flat" only after
  /// 1 s without one).
  DateTime _lastPage = DateTime.fromMillisecondsSinceEpoch(0);

  /// P0-16: the one status line, and when it last changed (each message
  /// stays at least 1.5 s).
  String? _status;
  DateTime _statusSince = DateTime.fromMillisecondsSinceEpoch(0);

  /// P0-17: taps while a photo is being taken, shot right after it.
  int _queuedShots = 0;

  /// P1-5: how far from flat the phone is, in degrees.
  double _tilt = 0;
  StreamSubscription<AccelerometerEvent>? _accel;

  /// Portrait aspect (width / height) of the capture: the camera runs at
  /// 4:3 (round 11c).
  double get _photoAspect => PreviewGeometry.defaultPhotoAspect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // P1-4: the camera screen is portrait only; EXIF uprights the photos.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _orientation.start();
    unawaited(_openCamera());
    unawaited(_checkStorage());
    unawaited(_loadShutterSound());
    _gyro = gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval)
        .listen(
          (e) {
            if (_motion.add((x: e.x, y: e.y, z: e.z, at: e.timestamp)) &&
                mounted) {
              setState(() => _moving = _motion.isMoving);
            }
          },
          onError: (Object _) {}, // no gyroscope: no hint
          cancelOnError: true,
        );
    // Focus before the tap: continuous autofocus, and every ~1.5 s, if the
    // phone moved, focus and exposure go back to the page.
    _focusTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _refocusOnPage(),
    );
    // P1-5: the tilt guide (angle between the screen and the floor).
    _accel = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .listen(
          (e) {
            final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
            if (g < 1) return;
            final tilt =
                math.acos((e.z.abs() / g).clamp(0.0, 1.0)) * 180 / math.pi;
            // Redraw only when it matters (the 20° line, the 8° green dot).
            if ((tilt > 20) != (_tilt > 20) || (tilt < 8) != (_tilt < 8)) {
              if (mounted) setState(() => _tilt = tilt);
            } else {
              _tilt = tilt;
            }
          },
          onError: (Object _) {},
          cancelOnError: true,
        );
  }

  /// Round 11b, C1: the live outline runs in Document mode only (in ID /
  /// passport it sat on the table or grabbed the document under the card;
  /// those keep the frame guide).
  bool get _outlineWanted =>
      DebugSwitches.liveOutline &&
      !_selfieTools &&
      widget.args.hint != CameraHint.signature &&
      context.read<ScanSessionBloc>().state.mode == ScanMode.document;

  Future<void> _startOutline() async {
    final cam = _cam;
    if (!_outlineWanted || cam == null || _streaming || _leaving) return;
    final live = _live ??= LivePageDetector();
    await live.start();
    _liveSub ??= live.quads.listen(_onOutline);
    try {
      await cam.analysisController?.start();
      _streaming = true;
    } catch (e) {
      debugPrint('[camera] no analysis stream: $e');
    }
  }

  Future<void> _stopOutline() async {
    final cam = _cam;
    if (!_streaming || cam == null) return;
    _streaming = false;
    try {
      await cam.analysisController?.stop();
    } catch (_) {}
  }

  /// Round 11c, B1: one small analysis frame (320 px, ~8 a second) to the
  /// live isolate; frames that come while one is being looked at are
  /// dropped there.
  Future<void> _onFrame(aw.AnalysisImage img) async {
    final live = _live;
    if (!_streaming || live == null || _leaving) return;
    final sw = Stopwatch()..start();
    final reported = switch (img.rotation) {
      aw.InputAnalysisImageRotation.rotation90deg => 90,
      aw.InputAnalysisImageRotation.rotation180deg => 180,
      aw.InputAnalysisImageRotation.rotation270deg => 270,
      _ => 0,
    };
    if (_orientation.turns == 0) _portraitRotation = reported;
    final rotation = _portraitRotation ?? (_front ? 270 : 90);
    img.when(
      nv21: (f) => live.offerFrame(
        f.bytes,
        w: f.width,
        h: f.height,
        stride: f.planes.isEmpty ? f.width : f.planes.first.bytesPerRow,
        nv21: true,
        rotation: rotation,
      ),
      bgra8888: (f) => live.offerFrame(
        f.bytes,
        w: f.width,
        h: f.height,
        stride: f.planes.isEmpty ? f.width * 4 : f.planes.first.bytesPerRow,
        nv21: false,
        rotation: rotation,
      ),
    );
    PerfLog.step(
      'stream_frame',
      sw.elapsedMilliseconds,
      input: '${img.width}x${img.height}',
    );
  }

  /// Each frame's page through [LiveOutline]: the eased outline, and auto
  /// capture once it has been steady for 0.8 s.
  void _onOutline(Quad? q) {
    if (!mounted || _leaving) return;
    final (fw, fh) = _live!.frameSize;
    PerfLog.step(
      'live_detect',
      _live!.sentAt.elapsedMilliseconds,
      input: '${fw}x$fh',
      output: q == null ? 'none' : '4pts',
      isolate: 'live',
    );
    final tracker = _tracker ??= LiveOutline(fw.toDouble(), fh.toDouble());
    final s = tracker.update(
      q,
      _clock.elapsedMicroseconds / 1e6,
      phoneStill: !_moving,
    );
    if (q != null) _lastPage = DateTime.now();
    final auto =
        _autoCapture &&
        context.read<ScanSessionBloc>().state.mode == ScanMode.document &&
        _ready;
    setState(() {
      _outline = s.outline;
      _autoProgress = auto ? s.progress : 0;
    });
    if (auto && s.capture && !_capturing) {
      tracker.shot();
      unawaited(_capture(auto: true));
    }
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
    if (_cam == null || _capturing) return;
    final tapped =
        _focusedAt != null &&
        DateTime.now().difference(_focusedAt!) < const Duration(seconds: 5);
    if (tapped || !_motion.takeFocusRefresh()) return;
    await _focusAt(_cardFocusPoint() ?? const Offset(0.5, 0.5));
  }

  /// Focus and exposure on [photo] (fractions of the portrait photo);
  /// camerawesome goes back to continuous focus after 5 s.
  Future<void> _focusAt(Offset photo) async {
    final cam = _cam;
    if (cam == null) return;
    const w = 1000.0;
    final h = w / _photoAspect;
    final size = awp.PreviewSize(width: w, height: h);
    await _trySet(
      () => cam.focusOnPoint(
        flutterPosition: Offset(photo.dx * w, photo.dy * h),
        pixelPreviewSize: size,
        flutterPreviewSize: size,
      ),
    );
  }

  Future<void> _checkStorage() async {
    final level = await getIt<StorageService>().level();
    debugPrint('[capture] storage level $level');
    if (mounted) setState(() => _storage = level);
  }

  /// Round 11c, B1: asks for the camera permission, then mounts the
  /// camerawesome preview ([_preview]); [_onCameraState] finishes the
  /// set-up once it runs.
  Future<void> _openCamera() async {
    try {
      final granted = await aw.CamerawesomePlugin.checkAndRequestPermissions(
        false,
        checkMicrophonePermissions: false,
      );
      if (!mounted) return;
      if (granted != null &&
          !granted.contains(awp.CamerAwesomePermission.camera)) {
        setState(() {
          _initializing = false;
          _permissionDenied = true;
        });
        return;
      }
    } catch (_) {
      // No permission API on this platform: let the camera ask.
    }
    if (!mounted || _leaving) return;
    _sensorConfig?.dispose();
    _sensorConfig = aw.SensorConfig.single(
      sensor: aw.Sensor.position(
        _front ? aw.SensorPosition.front : aw.SensorPosition.back,
      ),
      aspectRatio: aw.CameraAspectRatios.ratio_4_3,
      flashMode: aw.FlashMode.none,
    );
    setState(() {
      _cam = null;
      _camOn = true;
      _camKey++;
      _initializing = true;
    });
  }

  /// The camera is running: photo size, flash, the mode's zoom and focus,
  /// then the live outline. Once per opening.
  void _onCameraState(aw.CameraState state) {
    state.when(
      onPhotoMode: (photo) {
        if (identical(_cam, photo)) return;
        _cam = photo;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || !identical(_cam, photo)) return;
          setState(() => _initializing = false);
          await _applyPhotoSize();
          // A new camera starts at 1×: apply the mode again.
          _cameraMode = null;
          if (!mounted) return;
          final session = context.read<ScanSessionBloc>().state;
          await _applyFlash(session.flashOn);
          await _applyModeCamera(session.mode);
          unawaited(_startOutline());
        });
      },
    );
  }

  /// Round 11c, B1: about 8 MP (the largest 4:3 size up to 8.5 MP); HD the
  /// sensor's largest. Needs the patched camerawesome on Android
  /// (packages/camerawesome/FLASHDOX_PATCH.md).
  Future<void> _applyPhotoSize() async {
    try {
      final sizes = await aw.CamerawesomePlugin.getSizes();
      if (sizes.isEmpty) return;
      bool fourThree(Size s) =>
          ((s.longestSide / s.shortestSide) - 4 / 3).abs() < 0.02;
      final candidates = sizes.where(fourThree).toList()
        ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
      if (candidates.isEmpty) return;
      final pick = _hd
          ? candidates.first
          : candidates.firstWhere(
              (s) => s.width * s.height <= 8.5e6,
              orElse: () => candidates.last,
            );
      debugPrint(
        '[camera] photo size ${pick.width.toInt()}×${pick.height.toInt()}${_hd ? ' (HD)' : ''}',
      );
      await aw.CamerawesomePlugin.setPhotoSize(
        pick.width.toInt(),
        pick.height.toInt(),
      );
    } catch (e) {
      debugPrint('[camera] photo size: $e');
    }
  }

  /// P1-3.1: reopen the camera on the other lens.
  Future<void> _flip() async {
    if (_capturing || _countdown != null) return;
    await _stopOutline();
    _front = !_front;
    _portraitRotation = null;
    if (mounted) await _openCamera();
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
    if (_cam == null) return;
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
    await _focusAt(_cardFocusPoint() ?? photo);
  }

  /// Sound, haptic and the white flash — before `takePicture()` (P0-C).
  void _captureFeedback() {
    unawaited(HapticFeedback.mediumImpact());
    if (getIt<PrefsService>().shutterSound) {
      unawaited(
        _shutterPlayer
            .seek(Duration.zero)
            .then((_) => _shutterPlayer.resume())
            .catchError((Object _) {}),
      );
    }
    // Round 11b, P0-17: a short flash and the thumbnail are the only
    // feedback; no "Hold still…" box, the shutter stays white.
    setState(() => _flashTick++);
  }

  ScanMode? _cameraMode;

  /// ID / passport zoom. Round 4 (P0-2) used 1.5× against blur; users had
  /// to hold the phone too far away, so 14 Nov 2026 it came down 20 %.
  static const _cardZoom = 1.2;

  /// P0-2: [_cardZoom] in ID / passport (or the device maximum if lower) so
  /// the card fills more of the sensor; 1× for Document. Focus and exposure
  /// go to the frame centre.
  Future<void> _applyModeCamera(ScanMode mode) async {
    final cam = _cam;
    if (cam == null || mode == _cameraMode) return;
    _cameraMode = mode;
    final card = ScanModeRules.of(mode).aspectRatio != null;
    try {
      // camerawesome zooms linearly (0..1 of the field of view between 1×
      // and the maximum): 1.2× is 1 − 1/1.2 of the way to 1 − 1/max.
      final max = (await aw.CamerawesomePlugin.getMaxZoom()) ?? 1.0;
      final ratio = card ? math.min(_cardZoom, max) : 1.0;
      final linear = max <= 1
          ? 0.0
          : ((1 - 1 / ratio) / (1 - 1 / max)).clamp(0.0, 1.0);
      await cam.sensorConfig.setZoom(linear);
    } catch (_) {}
    await _focusAt(_cardFocusPoint() ?? const Offset(0.5, 0.5));
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
    final cam = _cam;
    if (cam == null) return;
    try {
      await cam.sensorConfig.setFlashMode(
        on ? aw.FlashMode.on : aw.FlashMode.none,
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Round 10, P0-2: released when the app is really in the background
    // (paused), not on every brief "inactive" (the notification shade, a
    // system dialog), which restarted the camera.
    if (state == AppLifecycleState.paused) {
      if (!_camOn) return;
      setState(() => _outline = null);
      unawaited(_shutDown(forGood: false));
    } else if (state == AppLifecycleState.resumed &&
        !_camOn &&
        !_permissionDenied &&
        !_leaving) {
      unawaited(_openCamera());
    }
  }

  /// The preview is live: shutter enabled, hints shown.
  bool get _ready => !_initializing && _cam != null;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orientation.stop();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _focusRingTimer?.cancel();
    _focusTimer?.cancel();
    unawaited(_gyro?.cancel());
    unawaited(_accel?.cancel());
    unawaited(_liveSub?.cancel());
    unawaited(_live?.dispose());
    _shutterPlayer.dispose();
    _sensorConfig?.dispose();
    super.dispose();
  }

  /// Round 7, P0-1: the photo is taken the moment the shutter is tapped.
  /// No waiting for the phone to hold still and no focus call here (focus
  /// is kept on the page before the tap). Within a frame: white flash,
  /// sound, vibration, then "Hold still…" until the file is saved, then the
  /// page flies to the stack. Everything else runs in the session's
  /// background queue (P0-C).
  Future<void> _capture({bool auto = false}) async {
    if (!auto) _tracker?.shot();
    // P0-17: the shutter is never blocked: a tap during a shot is taken
    // right after it.
    if (_capturing) {
      if (!auto) _queuedShots++;
      return;
    }
    final cam = _cam;
    final bloc = context.read<ScanSessionBloc>();
    if (cam == null ||
        _capturing ||
        _storage == StorageLevel.critical ||
        !bloc.state.canCapture) {
      return;
    }
    final total = Stopwatch()..start();
    setState(() => _capturing = true);
    _captureFeedback();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => debugPrint(
        '[perf] shutter tap → flash on screen ${total.elapsedMilliseconds} ms',
      ),
    );
    try {
      // How the phone is held right now (round 5, P0-1): from the
      // accelerometer, since the plugin's orientation follows the UI, which
      // is locked to portrait. Applied with the sensor angle at ingest.
      // camerawesome turns the photo for how the phone is held and says so
      // in its EXIF tag; the turns here only map the guide and the live
      // outline into the photo.
      final capture = CaptureMeta(
        sensorOrientation: _front ? 270 : 90,
        deviceTurns: _orientation.turns,
        frontCamera: _front,
        deviceInExif: true,
      );
      // Round 11c, B2: the live outline at the shutter, the page's corners
      // if detection finds none.
      final live = _outline;
      final shot = await _takePhoto(cam);
      debugPrint(
        '[perf] shutter tap → photo saved ${total.elapsedMilliseconds} ms',
      );
      PerfLog.step(
        'capture',
        total.elapsedMilliseconds,
        page: bloc.state.count + 1,
        output: '${(File(shot).lengthSync() / 1024).round()} KB',
      );
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
        context.pop(RetakeShot(shot, guide: guide, capture: capture));
        return;
      }
      bloc.add(
        SessionCaptured(shot, guide: guide, capture: capture, live: live),
      );
      setState(() => _flyTick++);
      // ID card (2 sides) / passport (1 page) finish by themselves.
      if (bloc.state.isComplete) {
        bloc.add(SessionFinished(waitAll: widget.args.returnPages));
      }
    } catch (e) {
      debugPrint('[capture] failed: $e');
      if (mounted) context.showSnack(context.l10n.errorImage, error: true);
    } finally {
      if (mounted) {
        setState(() => _capturing = false);
        // A tap that came while this photo was being taken.
        if (_queuedShots > 0 && !_leaving) {
          _queuedShots--;
          unawaited(_capture());
        }
      }
    }
  }

  /// One photo to a new file; a phone that can't take one while the
  /// analysis stream runs gets a second try without it (P1-7).
  Future<String> _takePhoto(aw.PhotoCameraState cam) async {
    Future<String> once() async {
      final path = _nextShot = getIt<FileStore>().newCapturePath(
        'shot_${newId()}',
      );
      Object? failure;
      await cam.takePhoto(onPhotoFailed: (e) => failure = e);
      final f = File(path);
      if (failure != null || !f.existsSync() || f.lengthSync() == 0) {
        throw StateError('photo failed: $failure');
      }
      return path;
    }

    try {
      return await once();
    } catch (e) {
      if (!_streaming) rethrow;
      debugPrint('[capture] retry without the outline stream: $e');
      await _stopOutline();
      try {
        return await once();
      } finally {
        unawaited(_startOutline());
      }
    }
  }

  /// Round 11b, P0-15.6: leaving the camera (Done, ✕, the app going to
  /// the background) stops everything: the image stream, the live isolate
  /// and the camera. No detection runs after this.
  bool _leaving = false;

  /// [forGood]: Done or ✕ (no restart); else the app went to the
  /// background and the camera comes back on resume.
  Future<void> _shutDown({bool forGood = true}) async {
    if (forGood) _leaving = true;
    await _stopOutline();
    unawaited(_liveSub?.cancel());
    _liveSub = null;
    unawaited(_live?.dispose());
    _live = null;
    _tracker = null;
    _cam = null;
    // Unmounting camerawesome's widget closes the camera.
    if (mounted) {
      setState(() {
        _camOn = false;
        _initializing = !forGood;
      });
    }
  }

  /// P0-16: one status line under the preview, by priority (tilted and no
  /// page for 1 s → page lost → page found); a new message stays at least
  /// 1.5 s. ID / passport show their hint; tools their own.
  String? _statusLine(AppLocalizations l, ScanSessionState s) {
    final given = widget.args.hint;
    String? want;
    if (given != null) {
      want = cameraHintText(l, given);
    } else if (s.guide != GuideLabel.documentPage) {
      want = cameraHintText(
        l,
        s.guide == GuideLabel.passport
            ? CameraHint.passport
            : CameraHint.idCard,
      );
    } else if (!_ready) {
      want = null;
    } else if (_outline != null) {
      want = l.cameraPageFound;
    } else if (_tiltGuide &&
        _tilt > 20 &&
        DateTime.now().difference(_lastPage) > const Duration(seconds: 1)) {
      want = l.cameraHoldFlat;
    } else {
      want = l.cameraPointAtPage;
    }
    final now = DateTime.now();
    if (want != _status &&
        (_status == null ||
            now.difference(_statusSince) >=
                const Duration(milliseconds: 1500))) {
      _status = want;
      _statusSince = now;
    } else if (want != _status) {
      // Check again once the current message has had its time.
      Future<void>.delayed(
        const Duration(milliseconds: 1500) - now.difference(_statusSince),
        () {
          if (mounted) setState(() {});
        },
      );
    }
    return _status;
  }

  /// P1-9: HD on / off reopens the camera at the other resolution.
  Future<void> _setHd(bool on) async {
    if (on == _hd || _capturing) return;
    // Round 11b, P0-20: once, on a phone with 4 GB or less.
    final ram = getIt<DeviceProfile>().totalBytes;
    if (on &&
        !_prefs.hdWarned &&
        (getIt<DeviceProfile>().isLowRam ||
            (ram != null && ram <= 4 * 1024 * 1024 * 1024 + (256 << 20)))) {
      unawaited(_prefs.setHdWarned());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.cameraHdSlow),
            persist: false,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    setState(() => _hd = on);
    unawaited(_prefs.setHdPhotos(on));
    // Only the photo size changes; the preview box stays as it is.
    await _applyPhotoSize();
  }

  void _setAutoCapture(bool on) {
    setState(() => _autoCapture = on);
    unawaited(_prefs.setAutoCapture(on));
  }

  /// P1-3: ↶ removes the last photo, "Page 4 removed" for 2 s.
  void _undo() {
    final bloc = context.read<ScanSessionBloc>();
    final n = bloc.state.count;
    if (n == 0) return;
    bloc.add(SessionCaptureRemoved(n - 1));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.cameraPageRemoved(n)),
          duration: const Duration(seconds: 2),
          persist: false,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// P1-10: a mode from the strip (or a swipe). Passport photo has its own
  /// camera and crop screen.
  Future<void> _onMode(ScanMode m) async {
    final bloc = context.read<ScanSessionBloc>();
    if (m == bloc.state.mode) return;
    if (m == ScanMode.photo) {
      final root = rootNavigatorKey.currentContext;
      context.pop();
      if (root != null && root.mounted) {
        await startPassportPhoto(root, fromCamera: true);
      }
      return;
    }
    bloc.add(SessionModeChanged(m));
  }

  void _onSwipe(int step) {
    const modes = [
      ScanMode.passport,
      ScanMode.idCard,
      ScanMode.document,
      ScanMode.photo,
    ];
    final i = modes.indexOf(context.read<ScanSessionBloc>().state.mode) + step;
    if (i >= 0 && i < modes.length) unawaited(_onMode(modes[i]));
  }

  /// P1-6 (artboard *CameraSettings*): toggles, all saved.
  Future<void> _openSettings() async {
    await AppBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final l = ctx.l10n;
          Widget toggle(
            String title,
            String hint,
            bool value,
            void Function(bool) onChanged,
          ) => SwitchListTile.adaptive(
            value: value,
            onChanged: (v) {
              onChanged(v);
              setSheet(() {});
            },
            title: Text(
              title,
              style: ctx.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(hint),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          );
          return AppBottomSheet(
            title: l.cameraSettings,
            child: Column(
              children: [
                toggle(
                  l.cameraAutoCapture,
                  l.cameraAutoCaptureHint,
                  _autoCapture,
                  _setAutoCapture,
                ),
                toggle(
                  l.cameraHdPhotos,
                  l.cameraHdPhotosHint,
                  _hd,
                  (v) => unawaited(_setHd(v)),
                ),
                toggle(l.cameraTiltGuide, l.cameraTiltGuideHint, _tiltGuide, (
                  v,
                ) {
                  setState(() => _tiltGuide = v);
                  unawaited(_prefs.setTiltGuide(v));
                }),
                toggle(l.cameraGrid, l.cameraGridHint, _grid, (v) {
                  setState(() => _grid = v);
                  unawaited(_prefs.setGrid(v));
                }),
                toggle(
                  l.cameraShutterSound,
                  l.cameraShutterSoundHint,
                  _prefs.shutterSound,
                  (v) => unawaited(_prefs.setShutterSound(v)),
                ),
                toggle(
                  l.cameraAutoCrop,
                  l.cameraAutoCropHint,
                  _prefs.autoCrop,
                  (v) => unawaited(_prefs.setAutoCrop(v)),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  /// Where the preview box and the frame are (round 7, P0-2).
  /// Round 11b, C2: the box has the same size and place in every mode and
  /// setting (HD changes the photo's shape on some phones); the camera
  /// stream is cover-fitted into it.
  CameraLayout get _layout => CameraOverlay.layoutFor(
    MediaQuery.of(context),
    PreviewGeometry.defaultPhotoAspect,
    modes: _showModes,
  );

  /// The live outline (photo fractions) where it shows in the box.
  Quad? _outlineOnScreen() {
    final q = _outline;
    if (q == null) return null;
    final box = _layout.box.size;
    Pt map(Pt p) {
      final o = PreviewGeometry.photoToViewport(
        Offset(p.x, p.y),
        photoAspect: _photoAspect,
        viewport: box,
      );
      return Pt(o.dx, o.dy);
    }

    return Quad(tl: map(q.tl), tr: map(q.tr), br: map(q.br), bl: map(q.bl));
  }

  bool get _showModes =>
      !widget.args.retake &&
      !widget.args.returnPages &&
      widget.args.addToDocumentId == null;

  Widget? _banner(BuildContext context, ScanSessionState s) {
    final l = context.l10n;
    final bloc = context.read<ScanSessionBloc>();
    final n = s.notice;
    if (n != null) {
      return switch (n.kind) {
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

  Future<void> _onReady(BuildContext context, ScanSessionState s) async {
    final pages = s.result!;
    if (widget.args.returnPages) {
      // The caller takes whole pages: imports still being prepared too.
      final more = await Future.wait([for (final p in s.pending) p.page]);
      if (!context.mounted) return;
      context.pop([
        ...pages,
        for (final r in more) ?r?.page,
      ]);
      return;
    }
    final args = EditorArgs(
      pages: pages,
      mode: s.mode,
      documentId: widget.args.addToDocumentId,
      addingPages: widget.args.addToDocumentId != null,
      tool: widget.args.tool,
      blurryPages: s.blurryPages,
      pending: s.pending,
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
        if (s.status == SessionStatus.ready) unawaited(_onReady(context, s));
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
                  guide: _statusLine(l, s),
                  flashOn: s.flashOn,
                  captureCount: s.count,
                  // The cropped page once processed (P0-3); a placeholder before.
                  lastCapturePath: s.captures.lastOrNull?.thumb,
                  canFinish: s.canFinish && !widget.args.retake,
                  showModes: _showModes,
                  photoAspect: PreviewGeometry.defaultPhotoAspect,
                  ready: _ready,
                  // P0-17: never grey while a photo is being taken.
                  capturing:
                      s.status == SessionStatus.preparing ||
                      _storage == StorageLevel.critical,
                  onClose: () => Navigator.of(context).maybePop(),
                  onFlash: () => context.read<ScanSessionBloc>().add(
                    const SessionFlashToggled(),
                  ),
                  onMode: (m) => unawaited(_onMode(m)),
                  onShutter: _shutter,
                  onFlip: _selfieTools ? _flip : null,
                  onTimer: _selfieTools
                      ? () => setState(() => _timerOn = !_timerOn)
                      : null,
                  timerOn: _timerOn,
                  countdown: _countdown,
                  onGallery: widget.args.retake ? null : _importFromSheet,
                  onFinish: () {
                    // P0-15.6: the camera and the live outline stop at once.
                    unawaited(_shutDown());
                    context.read<ScanSessionBloc>().add(
                      SessionFinished(waitAll: widget.args.returnPages),
                    );
                  },
                  onRemoveLast: s.count == 0 ? null : _undo,
                  onUndo: widget.args.retake ? null : _undo,
                  onSettings: _selfieTools ? null : _openSettings,
                  autoCapture: _autoCapture,
                  onAutoCapture:
                      s.mode == ScanMode.document && !widget.args.retake
                      ? () => _setAutoCapture(!_autoCapture)
                      : null,
                  hd: _hd,
                  onHd: _selfieTools ? null : () => unawaited(_setHd(!_hd)),
                  outline: _outlineWanted ? _outlineOnScreen() : null,
                  grid: _grid,
                  level: _status == l.cameraHoldFlat ? _tilt : null,
                  captureProgress: _autoCapture && s.mode == ScanMode.document
                      ? _autoProgress
                      : 0,
                  preparing: s.status == SessionStatus.preparing,
                  onSwipe: _showModes ? _onSwipe : null,
                  focusPoint: _focusPoint,
                  flashTick: _flashTick,
                  onPreviewTap: _onPreviewTap,
                  stackKey: _stackKey,
                  flyTick: _flyTick,
                  banner: _banner(context, s),
                ),
                // Round 11, P1-2: no box over the preview while the pages are
                // finished; a small spinner on the stack instead. (Imports,
                // with no stack yet, still say so.)
                if (s.status == SessionStatus.preparing && s.count == 0)
                  ProgressOverlay(label: l.sharePreparing),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _preview(BuildContext context) {
    final l = context.l10n;
    // Round 10, P0-2: while the camera starts, the box is plain black (no
    // spinner) and the preview fades in when it's live.
    if (_permissionDenied || (!_camOn && !_initializing)) {
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
    final config = _sensorConfig;
    // Round 7, P0-2: the whole preview in a box of its own shape (3:4, like
    // the photo), never cover-cropped: the photo shows what's on screen.
    return ColoredBox(
      color: Colors.black,
      child: !_camOn || config == null
          ? const SizedBox.expand()
          : AnimatedOpacity(
              opacity: _ready ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: KeyedSubtree(
                key: ValueKey(_camKey),
                child: aw.CameraAwesomeBuilder.custom(
                  sensorConfig: config,
                  saveConfig: aw.SaveConfig.photo(
                    pathBuilder: (sensors) async =>
                        aw.SingleCaptureRequest(_nextShot, sensors.first),
                  ),
                  previewFit: aw.CameraPreviewFit.cover,
                  progressIndicator: const SizedBox.expand(),
                  // Our own tap-to-focus and zoom (the overlay above it).
                  onPreviewTapBuilder: (_) =>
                      aw.OnPreviewTap(onTap: (_, _, _) {}, onTapPainter: null),
                  onPreviewScaleBuilder: (_) =>
                      aw.OnPreviewScale(onScale: (_) {}),
                  onImageForAnalysis: _onFrame,
                  imageAnalysisConfig: aw.AnalysisConfig(
                    androidOptions: const aw.AndroidAnalysisOptions.nv21(
                      width: LivePageDetector.liveSize,
                    ),
                    maxFramesPerSecond: 8,
                    autoStart: false,
                  ),
                  builder: (state, _) {
                    _onCameraState(state);
                    return const SizedBox.shrink();
                  },
                ),
              ),
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
