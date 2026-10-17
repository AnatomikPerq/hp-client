import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/minewire/link.dart';
import 'package:onexray/service/minewire/runtime.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/shared/ping/batch.dart';

/// Measures a minewire node the way every other node is measured.
///
/// libXray's probe times one cold request through a fresh outbound, so a
/// node's delay includes its own handshake with the server. A minewire node
/// gets the same: a throwaway engine opens its session (TCP and the
/// Minecraft login), then the same probe runs through a socks outbound to
/// that engine, and the two times add up. It also yields the exit's country.
///
/// The bare TCP connect time used before covered only the first hop: it
/// always won the automatic selection and passed even with a wrong password.
class MinewirePingProbe {
  MinewirePingProbe._(this._runtime, this._port, this._connect, this.failure);

  final MinewireRuntime _runtime;
  final int? _port;
  final int _connect;

  /// Why the engine could not open a session; then there is nothing to probe.
  final PingBatchResult? failure;

  static Future<MinewirePingProbe> start(
    MinewireLink link,
    int timeoutSeconds, {
    MinewireRuntime? runtime,
  }) async {
    final owner = runtime ?? MinewireRuntime.instance;
    final timeout = Duration(seconds: timeoutSeconds > 0 ? timeoutSeconds : 5);
    final watch = Stopwatch()..start();
    try {
      final port = await owner.startProbe(link, timeout: timeout);
      return MinewirePingProbe._(owner, port, watch.elapsedMilliseconds, null);
    } on ConnectionHostException catch (error) {
      final timedOut = error.cause == MinewireRuntime.timeoutCause;
      return MinewirePingProbe._(
        owner,
        null,
        0,
        PingBatchResult(
          false,
          timedOut ? PingDelayConstants.timeout : PingDelayConstants.error,
          '${error.cause ?? error.reason}',
        ),
      );
    } catch (error) {
      return MinewirePingProbe._(
        owner,
        null,
        0,
        PingBatchResult.failed('$error'),
      );
    }
  }

  /// The source for libXray's probe; null when the engine failed.
  PingBatchSource? get source {
    final port = _port;
    if (port == null) return null;
    return PingBatchSource(
      encodeSingleOutbound({
        'tag': 'proxy',
        'protocol': 'socks',
        'settings': {'address': '127.0.0.1', 'port': port},
      }),
    );
  }

  /// The probe's result with the session setup added to a success.
  PingBatchResult complete(PingBatchResult probe) {
    if (!probe.success) return probe;
    return PingBatchResult(
      true,
      probe.delay + _connect,
      probe.error,
      countryCode: probe.countryCode,
      locationError: probe.locationError,
    );
  }

  Future<void> stop() async {
    final port = _port;
    if (port != null) await _runtime.stopPorts([port]);
  }
}
