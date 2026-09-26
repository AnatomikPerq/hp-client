import 'dart:convert';
import 'dart:io';

import 'package:onexray/core/system_proxy/model.dart';
import 'package:onexray/core/tools/atomic_file.dart';

enum SystemProxyRestore {
  /// The App had not changed the system proxy.
  nothing,

  /// The settings saved before the App took over were written back.
  restored,

  /// Someone else changed the proxy after the App set it; their settings stay.
  keptForeign,
}

/// Owns the system proxy while the App's proxy mode runs.
///
/// Other software on the same machine (another VPN client, a corporate agent)
/// may also manage the system proxy. The App therefore saves the previous
/// settings to disk before touching anything and writes them back only while
/// the system still points at the App's own endpoint. If the proxy was changed
/// by someone else in the meantime, it is left alone.
///
/// The saved state survives crashes: [restore] after an unexpected Core exit
/// or on the next App start puts the user's settings back.
class SystemProxyManager {
  static const _version = 1;

  final SystemProxyBackend backend;

  /// Where the settings saved before the App took over are kept.
  final File stateFile;
  Future<void> _queue = Future.value();

  SystemProxyManager({required this.backend, required this.stateFile});

  /// Points the system proxy at `host:port`.
  ///
  /// PAC and auto-detection are switched off while the App's proxy is active:
  /// both take precedence over a manual proxy and would bypass it.
  Future<void> apply({required String host, required int port}) =>
      _serial(() async {
        final applied = SystemProxySettings(
          enabled: true,
          server: '$host:$port',
          bypass: systemProxyDefaultBypass.join(';'),
        );
        final current = await backend.read();
        final saved = await _readState();
        // After a crash the current settings are the App's, not the user's:
        // keep the snapshot taken before the App first took over.
        final previous = saved != null && _owns(current, saved)
            ? saved.previous
            : current;
        await _writeState(_State(previous: previous, applied: applied));
        await backend.write(applied);
      });

  /// Writes the saved settings back if the system still uses the App's proxy.
  Future<SystemProxyRestore> restore() => _serial(() async {
    final saved = await _readState();
    if (saved == null) return SystemProxyRestore.nothing;
    final current = await backend.read();
    final owned = _owns(current, saved);
    if (owned) await backend.write(saved.previous);
    await _deleteState();
    return owned ? SystemProxyRestore.restored : SystemProxyRestore.keptForeign;
  });

  /// Whether the App currently holds saved settings to restore.
  Future<bool> get active async => await _readState() != null;

  static bool _owns(SystemProxySettings current, _State saved) =>
      current.enabled &&
      current.server.trim().toLowerCase() ==
          saved.applied.server.trim().toLowerCase();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<_State?> _readState() async {
    // Synchronous on purpose: the common "nothing to restore" answer must not
    // add an IO round trip in front of every Core exit notification.
    if (!stateFile.existsSync()) return null;
    try {
      final json = jsonDecode(await stateFile.readAsString());
      if (json is! Map<String, dynamic> || json['version'] != _version) {
        throw const FormatException('Unsupported system proxy state');
      }
      return _State(
        previous: SystemProxySettings.fromJson(
          json['previous'] as Map<String, dynamic>,
        ),
        applied: SystemProxySettings.fromJson(
          json['applied'] as Map<String, dynamic>,
        ),
      );
    } on TypeError {
      throw const FormatException('Invalid system proxy state');
    }
  }

  Future<void> _writeState(_State state) async {
    await stateFile.parent.create(recursive: true);
    await writeBytesAtomically(
      stateFile,
      utf8.encode(
        jsonEncode({
          'version': _version,
          'previous': state.previous.toJson(),
          'applied': state.applied.toJson(),
        }),
      ),
    );
  }

  Future<void> _deleteState() async {
    if (await stateFile.exists()) await stateFile.delete();
  }
}

class _State {
  final SystemProxySettings previous;
  final SystemProxySettings applied;

  const _State({required this.previous, required this.applied});
}
