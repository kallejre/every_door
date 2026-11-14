import 'package:every_door/constants.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

/// Logger for performance tracing. Enabled with [kPerfLogging], independent
/// of the root log level (so it works in release builds too). Output goes to
/// the console and to the in-app log (Settings → Log).
final perfLogger = Logger('Perf');

/// Operations faster than this are not reported by [PerfTimer.slow].
const kPerfSlowMs = 20;

void setupPerfLogging() {
  if (!kPerfLogging) return;
  hierarchicalLoggingEnabled = true;
  perfLogger.level = Level.ALL;
}

/// A stopwatch that logs laps: `label › step: +12ms (total 340ms)`.
class PerfTimer {
  final String label;
  final Stopwatch _sw = Stopwatch()..start();
  int _lastLap = 0;

  PerfTimer(this.label, [String? startMessage]) {
    if (kPerfLogging && startMessage != null) {
      perfLogger.info('$label › $startMessage');
    }
  }

  int get elapsedMs => _sw.elapsedMilliseconds;

  /// Logs the time since the previous lap and since the start.
  void lap(String step) {
    if (!kPerfLogging) return;
    final now = _sw.elapsedMilliseconds;
    perfLogger.info('$label › $step: +${now - _lastLap}ms (total ${now}ms)');
    _lastLap = now;
  }

  /// Logs a lap only when it took at least [kPerfSlowMs].
  void slow(String step) {
    if (!kPerfLogging) return;
    final now = _sw.elapsedMilliseconds;
    if (now - _lastLap >= kPerfSlowMs) {
      perfLogger.info('$label › SLOW $step: +${now - _lastLap}ms');
    }
    _lastLap = now;
  }

  /// Logs a lap when the next frame has been rendered. Use after setState
  /// to see how long building the widget tree took.
  void lapOnNextFrame(String step) {
    if (!kPerfLogging) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => lap(step));
  }
}

/// Runs [fn] and logs how long it took, if it took at least [minMs].
Future<T> perfTime<T>(String label, Future<T> Function() fn,
    {int minMs = 0}) async {
  if (!kPerfLogging) return await fn();
  final sw = Stopwatch()..start();
  final result = await fn();
  final ms = sw.elapsedMilliseconds;
  if (ms >= minMs) perfLogger.info('$label: ${ms}ms');
  return result;
}
