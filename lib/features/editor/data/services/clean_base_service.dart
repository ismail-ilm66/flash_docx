import 'dart:async';
import 'dart:io';

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/services/device_profile.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:injectable/injectable.dart';

/// Round 6, P0-2: every page is cleaned (denoised, the slow step) once, at
/// export size, and every filter, preview and export starts from that file.
/// This service owns those jobs: one per page and size, joined by whoever
/// needs it next, moved up the queue when the user is waiting for it, and
/// dropped while still queued when its page is deleted.
@lazySingleton
class CleanBaseService {
  CleanBaseService(this._processor, this._files, this._device, this._prefs);

  final ImageProcessor _processor;
  final FileStore _files;
  final DeviceProfile _device;
  final PrefsService _prefs;

  /// The base's long edge for High quality (600 DPI cards, High PDFs).
  static const int highLongEdge = 2400;

  final _jobs = <String, _CleanJob>{};

  /// Pages whose look comes from a cleaned base: every filter but
  /// `original` (the raw page), and not passport photos (their own finish).
  static bool covers(PageEdits e) =>
      e.filter != FilterType.original && e.photoWidthMm == null;

  /// Export size: 2400 px when High quality is wanted (by default, or
  /// [high]), else 2000; always 2000 on a low-RAM phone (P0-4).
  int longEdgeFor({bool? high}) {
    final wantHigh = high ?? (_prefs.defaultQuality == 'high');
    return wantHigh && !_device.isLowRam ? highLongEdge : RenderPx.standardExportLongEdge;
  }

  String basePath(ScanPage page, {required bool card, int? longEdge}) => _files.cleanBasePath(
    page.id,
    page.originalPath,
    page.edits,
    longEdge: longEdge ?? longEdgeFor(),
    card: card,
  );

  String previewPath(ScanPage page, {required bool card}) =>
      _files.cleanPreviewPath(page.id, page.originalPath, page.edits, card: card);

  /// [page]'s cleaned base, made if needed. Joins a job already queued or
  /// running for it; [priority] interactive moves a job still waiting on the
  /// background lane to the front. Throws [JobCancelled] if the page was
  /// deleted ([cancel]) before its job started.
  Future<String> ensure(
    ScanPage page, {
    required bool card,
    int? longEdge,
    JobPriority priority = JobPriority.background,
  }) async {
    final size = longEdge ?? longEdgeFor();
    final out = basePath(page, card: card, longEdge: size);
    var lane = priority;
    while (true) {
      if (File(out).existsSync()) return out;
      var job = _jobs[out];
      if (job == null) {
        job = _start(page, out, size, card: card, priority: lane);
      } else if (lane == JobPriority.interactive && job.priority == JobPriority.background) {
        // Leaves the queue at once if it hasn't started; the loop then
        // queues it again on the interactive lane.
        job
          ..promoted = true
          ..cancel.cancel();
      }
      try {
        return await job.future;
      } on JobCancelled {
        if (job.dropped || !job.promoted) rethrow;
        // Promoted: whoever gets here first queues it again, interactive;
        // the others join that.
        lane = JobPriority.interactive;
      }
    }
  }

  _CleanJob _start(ScanPage page, String out, int size, {required bool card, required JobPriority priority}) {
    // An older crop of this page that hasn't started is not needed now (a
    // job for the same crop at another size is).
    final preview = previewPath(page, card: card);
    for (final j in _jobs.values) {
      if (j.pageId == page.id && j.preview != preview) {
        j
          ..dropped = true
          ..cancel.cancel();
      }
    }
    final cancel = CancelToken();
    late final Future<String> future;
    future = _processor
        .renderCleanBase(
          page.originalPath,
          page.edits,
          longEdge: size,
          outputPath: out,
          previewPath: preview,
          card: card,
          quick: _device.isLowRam,
          priority: priority,
          cancel: cancel,
        )
        .whenComplete(() {
          if (identical(_jobs[out]?.future, future)) _jobs.remove(out);
        });
    // Nobody may be listening when a dropped job fails.
    future.ignore();
    return _jobs[out] = _CleanJob(out, preview, page.id, priority, cancel, future);
  }

  /// The page was deleted: drop its jobs that haven't started (a running
  /// one finishes; its file is cleared with the temp folder).
  void cancel(String pageId) {
    for (final j in [..._jobs.values]) {
      if (j.pageId != pageId) continue;
      j.dropped = true;
      j.cancel.cancel();
    }
  }
}

class _CleanJob {
  _CleanJob(this.path, this.preview, this.pageId, this.priority, this.cancel, this.future);
  final String path;

  /// Same crop, any size.
  final String preview;
  final String pageId;
  final JobPriority priority;
  final CancelToken cancel;
  final Future<String> future;

  /// Cancelled to be queued again interactive (waiters re-join).
  bool promoted = false;

  /// Cancelled for good (page deleted, crop replaced).
  bool dropped = false;
}
