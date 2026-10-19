import 'dart:async';
import 'dart:io';

import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:path/path.dart' as p;

/// Diagnostics a release build keeps: connection failures and health
/// changes, appended to `<run>/app.log` and rotated to `app.log.1` at 1 MiB.
///
/// [ygLogger] writes nothing in release, so a connection that silently
/// stopped working left no trace. Only short, explicit messages belong here:
/// never configs, links, keys or stack traces, which may carry secrets.
/// Errors go through [reason], which keeps the diagnostic and cuts those out.
abstract final class AppLog {
  static const fileName = 'app.log';

  /// A variable only for tests.
  static int maxBytes = 1 << 20;

  static Future<void> _tail = Future.value();

  /// The directory the file lives in; null skips the file (tests, and
  /// before native storage is ready).
  static String? Function() directory = _runDirectory;

  static String? _runDirectory() {
    final root = AppHostApi().tunFilesDir;
    return root.isEmpty ? null : p.join(root, 'run');
  }

  static void info(String message) => _write('INFO', message);

  /// [error] for the log: its type and a short diagnostic. A bare type
  /// ("LibXrayInvokeException") said nothing about why a live switch failed;
  /// causes may quote configs, so links, JSON, UUIDs and long tokens are cut.
  static String reason(Object error) {
    // An AppFailure's details drop its code, which is the useful part here.
    var text = error is AppFailure ? '$error' : failureDetails(error);
    for (var previous = ''; previous != text;) {
      previous = text;
      text = text.replaceAll(RegExp(r'\{[^{}]*\}'), '{…}');
    }
    text = text
        .replaceAll(
          RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false),
          '<link>',
        )
        .replaceAll(
          RegExp(
            r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
            caseSensitive: false,
          ),
          '<uuid>',
        )
        .replaceAll(RegExp(r'[A-Za-z0-9+/_=-]{32,}'), '<secret>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.length > _maxReason) text = '${text.substring(0, _maxReason)}…';
    final type = '${error.runtimeType}';
    return text.isEmpty || text == type ? type : '$type: $text';
  }

  static const _maxReason = 300;

  static void warning(String message) => _write('WARN', message);

  static void _write(String level, String message) {
    ygLogger('[$level] $message');
    final dir = directory();
    if (dir == null) return;
    final line =
        '${_timestamp(DateTime.now())} [$level] '
        '${message.replaceAll(RegExp(r'[\r\n]+'), ' ')}\n';
    _tail = _tail
        .then((_) => _append(dir, line))
        .catchError((Object error) => ygLogger('app log failed: $error'));
  }

  /// Completes once every line written so far is on disk.
  static Future<void> flush() => _tail;

  static Future<void> _append(String dir, String line) async {
    await Directory(dir).create(recursive: true);
    final file = File(p.join(dir, fileName));
    if (await file.exists() && await file.length() + line.length > maxBytes) {
      final previous = File('${file.path}.1');
      if (await previous.exists()) await previous.delete();
      await file.rename(previous.path);
    }
    await file.writeAsString(line, mode: FileMode.append, flush: true);
  }

  static String _timestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
