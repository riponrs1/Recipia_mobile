import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Timing log for slow work, e.g. "PERF migrate 812ms". Silent in release builds.
Future<T> perfAsync<T>(String label, Future<T> Function() f) async {
  final sw = Stopwatch()..start();
  try {
    return await f();
  } finally {
    if (!kReleaseMode) print('PERF $label ${sw.elapsedMilliseconds}ms');
  }
}

T perfSync<T>(String label, T Function() f) {
  final sw = Stopwatch()..start();
  try {
    return f();
  } finally {
    if (!kReleaseMode && sw.elapsedMilliseconds > 0) print('PERF $label ${sw.elapsedMilliseconds}ms');
  }
}

/// Logs every frame slower than 100 ms ("PERF slow frame 340ms"), so
/// freezes show up in the log. Profile and debug builds only.
void watchSlowFrames() {
  if (kReleaseMode) return;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      final ms = t.totalSpan.inMilliseconds;
      if (ms > 100) {
        print('PERF slow frame ${ms}ms build=${t.buildDuration.inMilliseconds} draw=${t.rasterDuration.inMilliseconds}');
      }
    }
  });
}
