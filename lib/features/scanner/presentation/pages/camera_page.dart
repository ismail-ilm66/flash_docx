import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/id.dart';
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
    final mode = a.retake ? ScanMode.single : a.mode;
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
  String? _flyPath;
  Timer? _focusRingTimer;

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
    unawaited(_init());
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
        _permissionDenied = e.code.toLowerCase().contains('accessdenied') ||
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

  /// Lets focus settle on the frame centre before a capture, unless the
  /// user just tapped a point.
  Future<void> _settleFocus(CameraController c) async {
    final recent = _focusedAt != null &&
        DateTime.now().difference(_focusedAt!) < const Duration(seconds: 3);
    if (!recent) {
      await _trySet(() => c.setFocusPoint(const Offset(0.5, 0.5)));
      await _trySet(() => c.setExposurePoint(const Offset(0.5, 0.5)));
    }
    await Future<void>.delayed(const Duration(milliseconds: 280));
  }

  Future<void> _captureFeedback(String path) async {
    unawaited(HapticFeedback.mediumImpact());
    if (getIt<PrefsService>().shutterSound) {
      unawaited(_shutterPlayer.play(AssetSource('sounds/shutter.wav'), volume: 0.9));
    }
    if (!mounted) return;
    setState(() {
      _flashTick++;
      _flyPath = path;
    });
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
    _focusRingTimer?.cancel();
    _shutterPlayer.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final c = _controller;
    final bloc = context.read<ScanSessionBloc>();
    if (c == null || !c.value.isInitialized || _capturing || !bloc.state.canCapture) {
      return;
    }
    setState(() => _capturing = true);
    try {
      await _settleFocus(c);
      final shot = await c.takePicture();
      final target = getIt<FileStore>().newCapturePath('cap_${newId()}');
      await File(shot.path).rename(target).catchError((_) async {
        await File(shot.path).copy(target);
        return File(target);
      });
      if (!mounted) return;
      if (widget.args.retake) {
        context.pop(target);
        return;
      }
      await _captureFeedback(target);
      // The guide frame in photo coordinates is the fallback crop if edge
      // detection finds nothing (ID / passport use it; others inset 5%).
      final guideAspect = bloc.state.rules.aspectRatio;
      final guide = guideAspect == null
          ? null
          : PreviewGeometry.guideQuad(guideAspect, photoAspect: _photoAspect);
      bloc.add(SessionCaptured(target, guide: guide));
      // Single / passport / ID-card complete → finish automatically.
      if (bloc.state.isComplete) bloc.add(const SessionFinished());
    } catch (e) {
      if (mounted) context.showSnack(context.l10n.errorImage, error: true);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
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
        return AppScaffold(
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
                lastCapturePath: s.captures.lastOrNull?.path,
                canFinish: s.canFinish && !widget.args.retake,
                showModes: !widget.args.retake && !widget.args.returnPages && widget.args.addToDocumentId == null,
                capturing: _capturing || s.status == SessionStatus.preparing,
                onClose: () => context.pop(),
                onFlash: () => context.read<ScanSessionBloc>().add(const SessionFlashToggled()),
                onMode: (m) => context.read<ScanSessionBloc>().add(SessionModeChanged(m)),
                onShutter: _capture,
                onGallery: widget.args.retake ? null : () => _import(gallery: true),
                onFinish: () => context.read<ScanSessionBloc>().add(const SessionFinished()),
                onRemoveLast: s.count == 0
                    ? null
                    : () => context.read<ScanSessionBloc>().add(SessionCaptureRemoved(s.count - 1)),
                focusPoint: _focusPoint,
                flashTick: _flashTick,
                onPreviewTap: _onPreviewTap,
                stackKey: _stackKey,
                flyPath: _flyPath,
              ),
              if (s.status == SessionStatus.preparing)
                ProgressOverlay(label: l.sharePreparing),
            ],
          ),
        );
      },
    );
  }

  String _guideText(AppLocalizations l, ScanSessionState s) => switch (s.guide) {
        GuideLabel.single => l.cameraGuideSingle,
        GuideLabel.batchPage => l.cameraGuideBatch(s.count + 1),
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
