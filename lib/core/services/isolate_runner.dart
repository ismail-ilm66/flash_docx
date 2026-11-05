import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

/// One long-lived background isolate that runs heavy jobs (OpenCV, PDF)
/// strictly one at a time, in the order they were queued.
///
/// Spawning an isolate per job (what `compute` does) costs tens of
/// milliseconds on older phones and repeats the warm-up every time; a single
/// worker pays that once. If the worker dies, pending jobs fail and the next
/// job starts a fresh worker.
@lazySingleton
class IsolateRunner {
  _Worker? _worker;
  Future<_Worker>? _starting;

  Future<R> run<Q, R>(ComputeCallback<Q, R> fn, Q arg, {String? debugLabel}) async {
    final w = await _ensureWorker();
    return w.run(_Job<Q, R>(fn, arg));
  }

  Future<_Worker> _ensureWorker() {
    final w = _worker;
    if (w != null && !w.dead) return Future.value(w);
    return _starting ??= _Worker.spawn().then((w) {
      _worker = w;
      _starting = null;
      return w;
    }, onError: (Object e, StackTrace s) {
      _starting = null;
      Error.throwWithStackTrace(e, s);
    });
  }
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

  static Future<_Worker> spawn() async {
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
      responses.sendPort,
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

Future<void> _workerMain(SendPort replyTo) async {
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
