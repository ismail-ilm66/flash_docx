import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// Round 11, P1-7: the page outline while aiming. Camera frames (brightness
/// only, about 320 px wide) go to one long-lived isolate that runs the same
/// detection as a photo. A frame is sent only when the isolate is free and
/// at most [fps] times a second; the rest are dropped, so the preview and
/// the shutter never wait for it.
class LivePageDetector {
  LivePageDetector({this.fps = 5});

  /// Frames looked at per second, at most (3 on a low-RAM phone).
  final int fps;

  static const int _width = 320;

  final _quads = StreamController<Quad?>.broadcast();
  Isolate? _isolate;
  SendPort? _send;
  ReceivePort? _recv;
  bool _busy = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// The page found in each frame looked at (normalised to the upright
  /// preview), or null when there is none.
  Stream<Quad?> get quads => _quads.stream;

  Future<void> start() async {
    if (_isolate != null) return;
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

  /// Offers a camera frame; dropped while the last one is being looked at or
  /// when it comes sooner than [fps] allows. [rotation]: the sensor's
  /// clockwise turn to upright (its `sensorOrientation`).
  void offer(CameraImage image, int rotation) {
    final send = _send;
    if (send == null || _busy) return;
    final now = DateTime.now();
    if (now.difference(_last) < Duration(milliseconds: 1000 ~/ fps)) return;
    final small = _brightness(image);
    if (small == null) return;
    _busy = true;
    _last = now;
    send.send((TransferableTypedData.fromList([small.bytes]), small.w, small.h, rotation));
  }

  Future<void> dispose() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _send = null;
    _recv?.close();
    await _quads.close();
  }

  static Quad _quadOf(List<double> v) => Quad(tl: Pt(v[0], v[1]), tr: Pt(v[2], v[3]), br: Pt(v[4], v[5]), bl: Pt(v[6], v[7]));

  /// The frame's brightness at about [_width] px wide (nearest pixel): the
  /// Y plane of YUV, or the average of BGRA.
  static ({Uint8List bytes, int w, int h})? _brightness(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final step = (image.width / _width).ceil().clamp(1, 64);
    final w = image.width ~/ step;
    final h = image.height ~/ step;
    if (w < 16 || h < 16) return null;
    final out = Uint8List(w * h);
    final src = plane.bytes;
    final stride = plane.bytesPerRow;
    final bgra = image.format.group == ImageFormatGroup.bgra8888;
    final px = plane.bytesPerPixel ?? (bgra ? 4 : 1);
    for (var y = 0; y < h; y++) {
      final row = y * step * stride;
      for (var x = 0; x < w; x++) {
        final i = row + x * step * px;
        if (i + (bgra ? 2 : 0) >= src.length) continue;
        out[y * w + x] = bgra ? (src[i] + src[i + 1] + src[i + 2]) ~/ 3 : src[i];
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

/// The page in one brightness frame, turned upright by [rotation]: its
/// corners (TL, TR, BR, BL, normalised x / y pairs), or null.
@visibleForTesting
List<double>? detectFrame(Uint8List gray, int w, int h, int rotation) {
  final m = cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, gray);
  final turned = switch (rotation % 360) {
    90 => cv.rotate(m, cv.ROTATE_90_CLOCKWISE),
    180 => cv.rotate(m, cv.ROTATE_180),
    270 => cv.rotate(m, cv.ROTATE_90_COUNTERCLOCKWISE),
    _ => m,
  };
  final bgr = cv.cvtColor(turned, cv.COLOR_GRAY2BGR);
  if (!identical(turned, m)) turned.dispose();
  m.dispose();
  try {
    // A live guide: real edges only, never "the page fills the photo".
    final q = pipe.detectDocument(bgr, fillsFrame: false).quad;
    if (q == null) return null;
    return [for (final p in q.points) ...[p.x, p.y]];
  } finally {
    bgr.dispose();
  }
}
