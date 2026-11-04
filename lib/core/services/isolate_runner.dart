import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

/// One shared background queue so two heavy jobs never run at once.
///
/// Uses `compute` under the hood (fresh isolate per job). The queue keeps the
/// pipeline serial, which is what the plan asks for and avoids OpenCV
/// contention; the isolate spin-up is ~a few ms which is negligible next to
/// the work itself.
@lazySingleton
class IsolateRunner {
  final Queue<_Job<dynamic>> _queue = Queue();
  bool _running = false;

  Future<R> run<Q, R>(ComputeCallback<Q, R> fn, Q arg, {String? debugLabel}) {
    final job = _Job<R>(() => compute(fn, arg, debugLabel: debugLabel));
    _queue.add(job);
    _pump();
    return job.completer.future;
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      try {
        job.completer.complete(await job.body());
      } catch (e, s) {
        job.completer.completeError(e, s);
      }
    }
    _running = false;
  }
}

class _Job<R> {
  _Job(this.body);
  final Future<R> Function() body;
  final Completer<R> completer = Completer<R>();
}
