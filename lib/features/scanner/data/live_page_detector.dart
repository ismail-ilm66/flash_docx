import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// Round 11b, P0-15: the page outline while aiming. Each camera frame is
/// turned into a small colour picture (long side [liveSize]) while it is
/// read from YUV — the full frame is never converted or scaled — and sent
/// to one long-lived isolate running the reference `detect_live()`. Only
/// one frame is in flight; frames that arrive meanwhile are dropped.
class LivePageDetector {
  /// The reference `LIVE_SIZE`.
  static const int liveSize = 320;

  final _quads = StreamController<Quad?>.broadcast();
  Isolate? _isolate;
  SendPort? _send;
  ReceivePort? _recv;
  bool _busy = false;
  bool _closed = false;

  /// The page found in each frame looked at (normalised to the upright
  /// frame), or null when there is none.
  Stream<Quad?> get quads => _quads.stream;

  /// Upright size of the last frame sent (width, height).
  (int, int) frameSize = (180, 320);

  Future<void> start() async {
    if (_isolate != null || _closed) return;
    final recv = _recv = ReceivePort();
    final ready = Completer<SendPort>();
    recv.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
        return;
      }
      _busy = false;
      if (!_quads.isClosed) _quads.add(msg is List ? _quadOf(msg.cast<double>()) : null);
    });
    _isolate = await Isolate.spawn(_main, recv.sendPort, debugName: 'live-outline');
    _send = await ready.future;
  }

  /// Offers a camera analysis frame (round 11c, B1: camerawesome's small
  /// stream, ~320 px): NV21 on Android ([nv21]), else BGRA. Dropped while
  /// the last one is still being looked at. [stride]: bytes per row of the
  /// luma (or BGRA) plane. [rotation]: the clockwise turn to the portrait
  /// screen.
  void offerFrame(Uint8List bytes, {required int w, required int h, required int stride, required bool nv21, required int rotation}) {
    final send = _send;
    if (send == null || _busy || _closed || w < 16 || h < 16) return;
    _busy = true;
    sentAt.reset();
    sentAt.start();
    final turned = rotation % 180 == 90;
    frameSize = turned ? (h, w) : (w, h);
    send.send((TransferableTypedData.fromList([bytes]), w, h, stride, nv21, rotation));
  }

  /// Time since the frame in flight was sent (the `live_detect` step).
  final Stopwatch sentAt = Stopwatch();

  /// Stops for good: the isolate is killed (Done, ✕, background).
  Future<void> dispose() async {
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _send = null;
    _recv?.close();
    await _quads.close();
  }

  static Quad _quadOf(List<double> v) => Quad(tl: Pt(v[0], v[1]), tr: Pt(v[2], v[3]), br: Pt(v[4], v[5]), bl: Pt(v[6], v[7]));

}

void _main(SendPort reply) {
  final port = ReceivePort();
  reply.send(port.sendPort);
  port.listen((msg) {
    final (data, w, h, stride, nv21, rotation) = msg as (TransferableTypedData, int, int, int, bool, int);
    try {
      reply.send(detectRaw(data.materialize().asUint8List(), w, h, stride, nv21: nv21, rotation: rotation));
    } catch (e) {
      reply.send(null);
    }
  });
}

/// [detectFrame] on a raw analysis frame: NV21 (Y rows then interleaved
/// V/U rows, [stride] bytes each) or BGRA, converted by OpenCV.
@visibleForTesting
List<double>? detectRaw(Uint8List bytes, int w, int h, int stride, {required bool nv21, required int rotation}) {
  final cv.Mat bgr;
  if (nv21) {
    final rows = h + h ~/ 2;
    final st = math.max(w, math.min(stride, bytes.length ~/ rows));
    final all = cv.Mat.fromList(rows, st, cv.MatType.CV_8UC1, bytes.sublist(0, rows * st));
    final yuv = st == w ? all : all.region(cv.Rect(0, 0, w, rows));
    bgr = cv.cvtColor(yuv, cv.COLOR_YUV2BGR_NV21);
    if (!identical(yuv, all)) yuv.dispose();
    all.dispose();
  } else {
    final st = math.max(w * 4, stride);
    final all = cv.Mat.fromList(h, st ~/ 4, cv.MatType.CV_8UC4, bytes.sublist(0, h * st));
    final px = st == w * 4 ? all : all.region(cv.Rect(0, 0, w, h));
    bgr = cv.cvtColor(px, cv.COLOR_BGRA2BGR);
    if (!identical(px, all)) px.dispose();
    all.dispose();
  }
  try {
    return _detectBgrMat(bgr, rotation);
  } finally {
    bgr.dispose();
  }
}

/// The page in one small BGR frame turned upright by [rotation]: its
/// corners (TL, TR, BR, BL as normalised x / y pairs), or null.
@visibleForTesting
List<double>? detectFrame(Uint8List bgr, int w, int h, int rotation) {
  final m = cv.Mat.fromList(h, w, cv.MatType.CV_8UC3, bgr);
  try {
    return _detectBgrMat(m, rotation);
  } finally {
    m.dispose();
  }
}

List<double>? _detectBgrMat(cv.Mat m, int rotation) {
  final turned = switch (rotation % 360) {
    90 => cv.rotate(m, cv.ROTATE_90_CLOCKWISE),
    180 => cv.rotate(m, cv.ROTATE_180),
    270 => cv.rotate(m, cv.ROTATE_90_COUNTERCLOCKWISE),
    _ => m,
  };
  try {
    final q = pipe.detectLive(turned);
    if (q == null) return null;
    return [for (final p in q.points) ...[p.x, p.y]];
  } finally {
    if (!identical(turned, m)) turned.dispose();
  }
}
