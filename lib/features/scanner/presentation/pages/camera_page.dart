import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/scanner/data/import_service.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/presentation/bloc/scan_session_bloc.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/camera_overlay.dart';
import 'package:flash_dox/l10n/gen/app_localizations.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class CameraArgs {
  const CameraArgs({this.mode, this.addToDocumentId, this.retake = false});

  final ScanMode? mode;

  /// When set, finished pages are appended to this document.
  final String? addToDocumentId;

  /// Single capture that pops with the new file path (used by "Retake").
  final bool retake;
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
      final ctrl = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
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
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_init());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      await HapticFeedback.lightImpact();
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
      bloc.add(SessionCaptured(target));
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
        return AppScaffold(
          forceDark: true,
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _preview(context),
              CameraOverlay(
                rules: s.rules,
                guide: _guideText(l, s),
                flashOn: s.flashOn,
                captureCount: s.count,
                lastCapturePath: s.captures.lastOrNull?.path,
                canFinish: s.canFinish && !widget.args.retake,
                showModes: !widget.args.retake && widget.args.addToDocumentId == null,
                capturing: _capturing || s.status == SessionStatus.preparing,
                onClose: () => context.pop(),
                onFlash: () => context.read<ScanSessionBloc>().add(const SessionFlashToggled()),
                onMode: (m) => context.read<ScanSessionBloc>().add(SessionModeChanged(m)),
                onShutter: _capture,
                onGallery: widget.args.retake ? null : () => _import(gallery: true),
                onFiles: widget.args.retake ? null : () => _import(gallery: false),
                onFinish: () => context.read<ScanSessionBloc>().add(const SessionFinished()),
                onRemoveLast: s.count == 0
                    ? null
                    : () => context.read<ScanSessionBloc>().add(SessionCaptureRemoved(s.count - 1)),
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
    // Fill the screen, cropping the preview rather than letterboxing it.
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewAspect = 1 / c.value.aspectRatio; // portrait
        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxWidth / previewAspect,
              child: CameraPreview(c),
            ),
          ),
        );
      },
    );
  }
}
