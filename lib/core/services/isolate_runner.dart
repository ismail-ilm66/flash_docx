import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

/// Which queue a job waits in (round 4, P0-4). Interactive jobs (what the
/// user is looking at right now) always start before background jobs (cache
/// warm-up, exports), but never interrupt a job that is already running.
enum JobPriority { interactive, background }

/// Cancels a queued job before it starts (a superseded preview request).
/// A job that has already started runs to the end; its result is dropped.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Thrown for a job whose [CancelToken] was cancelled before it started.
class JobCancelled implements Exception {
  const JobCancelled();
  @override
  String toString() => 'JobCancelled';
}

/// One long-lived background isolate that runs heavy jobs (OpenCV, PDF)
/// strictly one at a time. Jobs wait on the main isolate in two queues and
/// are sent to the worker one by one, interactive first, so a preview never
/// waits behind a queue of exports.
///
/// Spawning an isolate per job (what `compute` does) costs tens of
/// milliseconds on older phones and repeats the warm-up every time; a single
/// worker pays that once. If the worker dies, pending jobs fail and the next
/// job starts a fresh worker.
@lazySingleton
class IsolateRunner {
  /// Runs once on each new worker before its first job, e.g. OpenCV thread
  /// settings. A top-level or static function (it's sent to the isolate).
  static void Function()? workerInit;

  _Worker? _worker;
  Future<_Worker>? _starting;
  final _interactive = <_Pending>[];
  final _background = <_Pending>[];
  bool _busy = false;

  Future<R> run<Q, R>(
    ComputeCallback<Q, R> fn,
    Q arg, {
    String? debugLabel,
    JobPriority priority = JobPriority.background,
    CancelToken? cancel,
  }) {
    final ahead = _interactive.length + (priority == JobPriority.background ? _background.length : 0) + (_busy ? 1 : 0);
    final pending = _Pending(_Job<Q, R>(fn, arg), cancel, debugLabel ?? 'job', ahead);
    (priority == JobPriority.interactive ? _interactive : _background).add(pending);
    unawaited(_pump());
    return pending.completer.future.then((v) => v as R);
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_interactive.isNotEmpty || _background.isNotEmpty) {
        final next = _interactive.isNotEmpty ? _interactive.removeAt(0) : _background.removeAt(0);
        if (next.cancel?.isCancelled ?? false) {
          next.completer.completeError(const JobCancelled());
          continue;
        }
        final waited = next.queued.elapsedMilliseconds;
        try {
          final w = await _ensureWorker();
          final ran = Stopwatch()..start();
          final result = await w.run<Object?>(next.job);
          _log(next, waited, ran.elapsedMilliseconds);
          next.completer.complete(result);
        } catch (e, s) {
          next.completer.completeError(e, s);
        }
      }
    } finally {
      _busy = false;
    }
  }

  /// `[queue] look waited 2400 ms (1 ahead), ran 310 ms`: time spent behind
  /// other jobs vs on the worker. Dev and profile builds only.
  void _log(_Pending job, int waited, int ran) {
    if (kReleaseMode) return;
    debugPrint('[queue] ${job.label} waited $waited ms (${job.ahead} ahead), ran $ran ms');
  }

  Future<_Worker> _ensureWorker() {
    final w = _worker;
    if (w != null && !w.dead) return Future.value(w);
    final sw = Stopwatch()..start();
    return _starting ??= _Worker.spawn(workerInit).then((w) {
      if (!kReleaseMode) debugPrint('[queue] worker started in ${sw.elapsedMilliseconds} ms');
      _worker = w;
      _starting = null;
      return w;
    }, onError: (Object e, StackTrace s) {
      _starting = null;
      Error.throwWithStackTrace(e, s);
    });
  }
}

class _Pending {
  _Pending(this.job, this.cancel, this.label, this.ahead);
  final _Job<dynamic, dynamic> job;
  final CancelToken? cancel;
  final String label;

  /// Jobs queued or running ahead of this one when it was added.
  final int ahead;
  final Stopwatch queued = Stopwatch()..start();
  final Completer<Object?> completer = Completer<Object?>();
}

/// A unit of work sent to the worker. Holds a top-level function and its
/// argument; both are sendable within the same isolate group.
class _Job<Q, R> {
  _Job(this.fn, this.arg);
  final ComputeCallback<Q, R> fn;
  final Q arg;

  FutureOr<R> call() => fn(arg);
}

class _Request {
  _Request(this.id, this.job);
  final int id;
  final _Job<dynamic, dynamic> job;
}

class _Response {
  _Response(this.id, this.result, this.error, this.stack);
  final int id;
  final Object? result;
  final Object? error;
  final String? stack;
}

class _Worker {
  _Worker._(this._isolate, this._send, this._responses, this._exit);

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _responses;
  final ReceivePort _exit;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  bool dead = false;

  static Future<_Worker> spawn(void Function()? init) async {
    final responses = ReceivePort();
    final exit = ReceivePort();
    final handshake = Completer<SendPort>();
    late _Worker worker;
    responses.listen((msg) {
      if (msg is SendPort) {
        handshake.complete(msg);
      } else if (msg is _Response) {
        worker._complete(msg);
      }
    });
    final isolate = await Isolate.spawn(
      _workerMain,
      (responses.sendPort, init),
      debugName: 'flashdox-worker',
      onExit: exit.sendPort,
      onError: exit.sendPort,
      errorsAreFatal: false,
    );
    final send = await handshake.future;
    worker = _Worker._(isolate, send, responses, exit);
    exit.listen((_) => worker._die('worker isolate exited'));
    return worker;
  }

  Future<R> run<R>(_Job<dynamic, R> job) {
    if (dead) return Future.error(StateError('worker is dead'));
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _send.send(_Request(id, job));
    return c.future.then((v) => v as R);
  }

  void _complete(_Response r) {
    final c = _pending.remove(r.id);
    if (c == null) return;
    if (r.error != null) {
      c.completeError(r.error!, r.stack == null ? null : StackTrace.fromString(r.stack!));
    } else {
      c.complete(r.result);
    }
  }

  void _die(String reason) {
    if (dead) return;
    dead = true;
    for (final c in _pending.values) {
      c.completeError(StateError(reason));
    }
    _pending.clear();
    _responses.close();
    _exit.close();
    _isolate.kill();
  }
}

Future<void> _workerMain((SendPort, void Function()?) start) async {
  final (replyTo, init) = start;
  try {
    init?.call();
  } catch (_) {
    // A failed tweak must not take the worker down.
  }
  final inbox = ReceivePort();
  replyTo.send(inbox.sendPort);
  // `await for` keeps jobs strictly serial even if one is async.
  await for (final msg in inbox) {
    if (msg is! _Request) continue;
    try {
      final result = await msg.job();
      replyTo.send(_Response(msg.id, result, null, null));
    } catch (e, s) {
      // Send the error object if it can cross isolates, else its text.
      try {
        replyTo.send(_Response(msg.id, null, e, s.toString()));
      } catch (_) {
        replyTo.send(_Response(msg.id, null, StateError(e.toString()), s.toString()));
      }
    }
  }
}
