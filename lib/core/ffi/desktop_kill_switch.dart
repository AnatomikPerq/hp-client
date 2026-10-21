import 'dart:convert';
import 'dart:io';

import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/pigeon/model_reader.dart';
import 'package:onexray/core/tools/app_log.dart';
import 'package:onexray/core/tools/atomic_file.dart';
import 'package:path/path.dart' as p;

/// What the App armed the kill switch with for the current connection.
///
/// Written before a Core with the kill switch starts and removed only when
/// the user disconnects, so it outlives a Core that crashes: while it exists,
/// a Core that exits leaves the system proxy at its dead port, and the App
/// treats the TUN filters the Core left as wanted.
class DesktopKillSwitchHold {
  static const _version = 1;

  /// The block outlives the session it was armed in.
  final bool strict;

  /// The session it was armed in. Without [strict], a block found in a later
  /// session (the user logged off, shut down or restarted) is lifted.
  final KillSwitchSession session;

  const DesktopKillSwitchHold({required this.strict, required this.session});

  static File file(String runDirectory) =>
      File(p.join(runDirectory, 'kill-switch.json'));

  static Future<DesktopKillSwitchHold?> read(String runDirectory) async {
    final file = DesktopKillSwitchHold.file(runDirectory);
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic> || json['version'] != _version) {
        throw const FormatException('Unsupported kill switch state');
      }
      return DesktopKillSwitchHold(
        strict: json['strict'] as bool,
        session: KillSwitchSession.fromJson(
          json['session'] as Map<String, dynamic>,
        ),
      );
    } on Object catch (error) {
      // An unreadable hold is still a hold: blocking by mistake is
      // recoverable with one click, leaking is not.
      AppLog.warning('kill switch state unreadable: ${AppLog.reason(error)}');
      return DesktopKillSwitchHold(
        strict: true,
        session: const KillSwitchSession(bootedAt: 0, logon: ''),
      );
    }
  }

  Future<void> write(String runDirectory) async {
    final file = DesktopKillSwitchHold.file(runDirectory);
    await file.parent.create(recursive: true);
    await writeBytesAtomically(
      file,
      utf8.encode(
        jsonEncode({
          'version': _version,
          'strict': strict,
          'session': session.toJson(),
        }),
      ),
    );
  }

  static Future<void> clear(String runDirectory) async {
    final file = DesktopKillSwitchHold.file(runDirectory);
    if (await file.exists()) await file.delete();
  }
}

/// The App's half of the desktop kill switch. The TUN Core installs the
/// filters (they need administrator rights); the App records the hold, reads
/// the filters' state and lifts them through libXray, which needs no UAC
/// prompt for the user who started the Core. The system proxy stays with the
/// platform API, which only asks [hold] whether to hand it back.
class DesktopKillSwitchControl {
  final Future<String> Function() _runDirectory;
  final Future<String> Function(String requestJson) _invoke;

  /// Runs `HyperClientCore unblock` elevated: the fallback when this user may
  /// not lift the filters, because an administrator elevated the Core with
  /// other credentials. Null where there is none.
  final Future<void> Function()? _liftElevated;

  DesktopKillSwitchControl({
    required this._runDirectory,
    required this._invoke,
    this._liftElevated,
  });

  Future<DesktopKillSwitchHold?> hold() async =>
      DesktopKillSwitchHold.read(await _runDirectory());

  /// Records the kill switch of the connection about to start, or removes the
  /// record when it starts without one.
  Future<void> arm(DesktopKillSwitch? killSwitch) async {
    final directory = await _runDirectory();
    if (killSwitch == null) {
      await DesktopKillSwitchHold.clear(directory);
      return;
    }
    KillSwitchSession session;
    try {
      session = (await _state()).session;
    } catch (error) {
      // Not worth failing the connection over: an unknown session only
      // means a lenient block ends at the next App start.
      AppLog.warning('read session failed: ${AppLog.reason(error)}');
      session = const KillSwitchSession(bootedAt: 0, logon: '');
    }
    await DesktopKillSwitchHold(
      strict: killSwitch.strict,
      session: session,
    ).write(directory);
  }

  /// Whether the TUN filters are in place.
  Future<bool> filtersEngaged() async => (await _state()).engaged;

  /// Removes the TUN filters, if any. Never fails the caller: a disconnect
  /// must complete, and the App shows a block that remains.
  Future<void> liftFilters() async {
    try {
      final response = await _call(LibXrayMethod.liftKillSwitch);
      if (response.success) return;
      AppLog.warning('lift kill switch failed: ${response.error}');
      if (_liftElevated == null || !await filtersEngaged()) return;
      await _liftElevated();
      if (await filtersEngaged()) {
        AppLog.warning('kill switch still blocks after the elevated lift');
      }
    } catch (error) {
      AppLog.warning('lift kill switch failed: ${AppLog.reason(error)}');
    }
  }

  /// The user disconnected: lift everything and forget the hold.
  Future<void> disarm() async {
    await liftFilters();
    try {
      await DesktopKillSwitchHold.clear(await _runDirectory());
    } catch (error) {
      AppLog.warning('clear kill switch state failed: ${AppLog.reason(error)}');
    }
  }

  /// At App start, with no Core running: whether a block left before still
  /// holds. A hold from an earlier session is lifted unless it is strict;
  /// filters without a hold (an older App, a lost file) are lifted too.
  ///
  /// Never fails the App's start: when libXray cannot tell, a hold stays.
  Future<bool> settle() async {
    DesktopKillSwitchHold? saved;
    try {
      saved = await hold();
      if (saved == null) {
        if (await filtersEngaged()) {
          AppLog.warning('kill switch filters without a hold; lifting them');
          await liftFilters();
        }
        return false;
      }
      if (saved.strict) return true;
      if (saved.session.sameAs((await _state()).session)) return true;
      AppLog.info('kill switch from an earlier session lifted');
      await disarm();
      return false;
    } catch (error) {
      AppLog.warning('kill switch state unknown: ${AppLog.reason(error)}');
      return saved != null;
    }
  }

  Future<KillSwitchStateResponse> _state() async {
    final response = await _call(LibXrayMethod.killSwitchState);
    if (!response.success || response.data == null) {
      throw LibXrayInvokeException(response.error);
    }
    return KillSwitchStateResponse.fromJson(response.data!);
  }

  Future<LibXrayInvokeResponse> _call(LibXrayMethod method) async =>
      LibXrayInvokeResponseParser.parse(
        await _invoke(
          jsonEncode(LibXrayInvokeRequest(method: method).toJson()),
        ),
      );
}
