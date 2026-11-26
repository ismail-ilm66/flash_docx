import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
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

  /// Offers a camera frame; dropped while the last one is still being
  /// looked at. [rotation]: the sensor's clockwise turn to upright.
  void offer(CameraImage image, int rotation) {
    final send = _send;
    if (send == null || _busy || _closed) return;
    final small = smallBgr(image);
    if (small == null) return;
    _busy = true;
    final turned = rotation % 180 == 90;
    frameSize = turned ? (small.h, small.w) : (small.w, small.h);
    send.send((TransferableTypedData.fromList([small.bytes]), small.w, small.h, rotation));
  }

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

  /// The frame as interleaved BGR, long side [liveSize] (nearest pixel),
  /// read straight from YUV420 (Y plus the U / V planes) or BGRA.
  @visibleForTesting
  static ({Uint8List bytes, int w, int h})? smallBgr(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final step = (math.max(image.width, image.height) / liveSize).ceil().clamp(1, 64);
    final w = image.width ~/ step;
    final h = image.height ~/ step;
    if (w < 16 || h < 16) return null;
    final out = Uint8List(w * h * 3);
    if (image.format.group == ImageFormatGroup.bgra8888 || image.planes.length < 3) {
      final pl = image.planes.first;
      final px = pl.bytesPerPixel ?? 4;
      final src = pl.bytes;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * step * pl.bytesPerRow + x * step * px;
          final o = (y * w + x) * 3;
          if (px >= 3 && i + 2 < src.length) {
            out[o] = src[i];
            out[o + 1] = src[i + 1];
            out[o + 2] = src[i + 2];
          } else if (i < src.length) {
            out[o] = out[o + 1] = out[o + 2] = src[i];
          }
        }
      }
      return (bytes: out, w: w, h: h);
    }
    final yp = image.planes[0];
    final up = image.planes[1];
    final vp = image.planes[2];
    final uvPx = up.bytesPerPixel ?? 1;
    for (var y = 0; y < h; y++) {
      final sy = y * step;
      for (var x = 0; x < w; x++) {
        final sx = x * step;
        final yi = sy * yp.bytesPerRow + sx;
        final ci = (sy >> 1) * up.bytesPerRow + (sx >> 1) * uvPx;
        if (yi >= yp.bytes.length || ci >= up.bytes.length || ci >= vp.bytes.length) continue;
        final yy = yp.bytes[yi].toDouble();
        final u = up.bytes[ci] - 128.0;
        final v = vp.bytes[ci] - 128.0;
        final o = (y * w + x) * 3;
        out[o] = (yy + 1.772 * u).round().clamp(0, 255);
        out[o + 1] = (yy - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
        out[o + 2] = (yy + 1.402 * v).round().clamp(0, 255);
      }
    }
    return (bytes: out, w: w, h: h);
  }
}

void _main(SendPort reply) {
  final port = ReceivePort();
  reply.send(port.sendPort);
  port.listen((msg) {
    final (data, w, h, rotation) = msg as (TransferableTypedData, int, int, int);
    try {
      reply.send(detectFrame(data.materialize().asUint8List(), w, h, rotation));
    } catch (e) {
      reply.send(null);
    }
  });
}

/// The page in one small BGR frame turned upright by [rotation]: its
/// corners (TL, TR, BR, BL as normalised x / y pairs), or null.
@visibleForTesting
List<double>? detectFrame(Uint8List bgr, int w, int h, int rotation) {
  final m = cv.Mat.fromList(h, w, cv.MatType.CV_8UC3, bgr);
  final turned = switch (rotation % 360) {
    90 => cv.rotate(m, cv.ROTATE_90_CLOCKWISE),
    180 => cv.rotate(m, cv.ROTATE_180),
    270 => cv.rotate(m, cv.ROTATE_90_COUNTERCLOCKWISE),
    _ => m,
  };
  if (!identical(turned, m)) m.dispose();
  try {
    final q = pipe.detectLive(turned);
    if (q == null) return null;
    return [for (final p in q.points) ...[p.x, p.y]];
  } finally {
    turned.dispose();
  }
}
