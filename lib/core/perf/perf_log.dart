import 'dart:io';

import 'package:flutter/foundation.dart';

/// Round 11c, section 0: one line per step of the scan flow,
///
///     [FD-PERF] page=3 step=detect ms=412 in=1000x750 out=4pts isolate=worker
///
/// printed and appended to a file in app storage (Settings → About →
/// long-press the version → "Share performance log"). On in debug and
/// profile builds and in a release build made with
/// `--dart-define=FD_TEST=true` (the test build); a normal release build
/// writes nothing.
abstract final class PerfLog {
  static const bool _testBuild = bool.fromEnvironment('FD_TEST');

  /// Whether lines are written (and the test switches are shown).
  static bool get enabled => !kReleaseMode || _testBuild;

  static String? _path;
  static String _isolate = 'main';

  /// The log file, in every isolate that logs (the worker gets it at start).
  static String? get path => _path;

  static void init(String path, {String isolate = 'main'}) {
    _path = path;
    _isolate = isolate;
  }

  /// One step: [ms] milliseconds; [page] (1-based) when it's about one
  /// page; [input] / [output] sizes or results.
  static void step(String step, int ms, {Object? page, String? input, String? output, String? isolate}) {
    if (!enabled) return;
    final line = StringBuffer('[FD-PERF]');
    if (page != null) line.write(' page=$page');
    line.write(' step=$step ms=$ms');
    if (input != null) line.write(' in=$input');
    if (output != null) line.write(' out=$output');
    line.write(' isolate=${isolate ?? _isolate}');
    final text = line.toString();
    if (!kReleaseMode) debugPrint(text);
    final p = _path;
    if (p == null) return;
    try {
      File(p).writeAsStringSync('${DateTime.now().toIso8601String()} $text\n', mode: FileMode.append, flush: false);
    } catch (_) {}
  }

  /// Times [run] as [name].
  static Future<T> time<T>(String name, Future<T> Function() run, {Object? page, String? input, String Function(T)? output}) async {
    final sw = Stopwatch()..start();
    final r = await run();
    step(name, sw.elapsedMilliseconds, page: page, input: input, output: output?.call(r));
    return r;
  }

  /// Times [run] as [name] (synchronous, e.g. inside the worker).
  static T timeSync<T>(String name, T Function() run, {Object? page, String? input, String Function(T)? output}) {
    final sw = Stopwatch()..start();
    final r = run();
    step(name, sw.elapsedMilliseconds, page: page, input: input, output: output?.call(r));
    return r;
  }

  static final _open = <String, Stopwatch>{};

  /// Starts timing [name] across screens (Done → Adjust edges shown…).
  static void begin(String name) {
    if (enabled) _open[name] = Stopwatch()..start();
  }

  /// Ends [name] if [begin] started it (once).
  static void end(String name, {Object? page, String? input, String? output}) {
    final sw = _open.remove(name);
    if (sw != null) step(name, sw.elapsedMilliseconds, page: page, input: input, output: output, isolate: 'main');
  }

  /// Starts a new run's section in the file (a scan, a debug-switch run).
  static void mark(String what) {
    final p = _path;
    if (!enabled || p == null) return;
    try {
      File(p).writeAsStringSync('---- ${DateTime.now().toIso8601String()} $what\n', mode: FileMode.append);
    } catch (_) {}
  }

  static Future<void> clear() async {
    final p = _path;
    if (p == null) return;
    try {
      await File(p).writeAsString('');
    } catch (_) {}
  }
}
