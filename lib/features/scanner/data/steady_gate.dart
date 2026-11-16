import 'dart:async';
import 'dart:math' as math;

/// One gyroscope reading: rotation rates (rad/s) and when it was taken.
typedef GyroSample = ({double x, double y, double z, DateTime at});

/// Round 6, P1-1: the shutter waits for the phone to hold still. Pressing
/// it in indoor light (a slow shutter) while the phone still moves smears
/// one side of the page and doubles its letters.
abstract final class SteadyGate {
  /// Still enough: under this rotation rate…
  static const double maxRate = 0.15;

  /// …for this long.
  static const Duration hold = Duration(milliseconds: 150);

  /// Never wait longer than this: the shot is taken anyway.
  static const Duration timeout = Duration(seconds: 1);

  /// True once the rate has stayed under [maxRate] for [hold]; false after
  /// [timeout], or straight away if the phone has no gyroscope.
  static Future<bool> wait(
    Stream<GyroSample> samples, {
    double maxRate = SteadyGate.maxRate,
    Duration hold = SteadyGate.hold,
    Duration timeout = SteadyGate.timeout,
  }) {
    final done = Completer<bool>();
    void finish(bool steady) {
      if (!done.isCompleted) done.complete(steady);
    }

    DateTime? stillSince;
    final timer = Timer(timeout, () => finish(false));
    final sub = samples.listen(
      (s) {
        final rate = math.sqrt(s.x * s.x + s.y * s.y + s.z * s.z);
        if (rate >= maxRate) {
          stillSince = null;
          return;
        }
        final since = stillSince ??= s.at;
        if (s.at.difference(since) >= hold) finish(true);
      },
      onError: (Object _) => finish(false),
      onDone: () => finish(false),
      cancelOnError: true,
    );
    return done.future.whenComplete(() {
      timer.cancel();
      unawaited(sub.cancel());
    });
  }
}
