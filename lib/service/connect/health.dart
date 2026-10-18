import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/app_log.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:onexray/service/shared/notification/service.dart';
import 'package:onexray/service/shared/ping/live_probe.dart';

enum ConnectionHealthStatus { checking, healthy, unreachable }

/// What the background check last saw for one running connection.
@immutable
class ConnectionHealth {
  /// The runtime and nodes this applies to; null when nothing runs.
  final String? key;
  final ConnectionHealthStatus status;

  /// The last successful probe through the tunnel.
  final int? milliseconds;

  /// A minewire engine of this connection holds no session with its server.
  final bool minewireDown;

  const ConnectionHealth({
    this.key,
    this.status = ConnectionHealthStatus.checking,
    this.milliseconds,
    this.minewireDown = false,
  });

  static const none = ConnectionHealth();

  /// Health is per session and per node: a switch starts over.
  static String keyOf(ConnectionRuntime runtime) =>
      '${runtime.identity}|${(runtime.nodeIds.toList()..sort()).join(',')}';

  bool appliesTo(ConnectionRuntime? runtime) =>
      runtime != null && key == keyOf(runtime);

  bool get unreachable => status == ConnectionHealthStatus.unreachable;

  @override
  bool operator ==(Object other) =>
      other is ConnectionHealth &&
      other.key == key &&
      other.status == status &&
      other.milliseconds == milliseconds &&
      other.minewireDown == minewireDown;

  @override
  int get hashCode => Object.hash(key, status, milliseconds, minewireDown);
}

/// Watches a desktop connection after it came up.
///
/// The coordinator reports a connection as connected while the Core runs,
/// even when nothing gets through: on 17.10 a minewire engine lost its
/// session, Home and the tray kept saying "connected", and nothing in the
/// UI or any log showed why. The monitor probes the same path system
/// traffic takes and reads the minewire engines' state; a few failures in a
/// row mark the connection unreachable on Home and in the tray and post one
/// notification, the first success clears it.
final class ConnectionHealthMonitor {
  static final instance = ConnectionHealthMonitor();

  ConnectionHealthMonitor({
    ConnectionCoordinator? coordinator,
    Future<LivePingResult> Function(ConnectionRuntime runtime)? probe,
    Future<List<MinewireEngineState>> Function()? minewireState,
    Future<void> Function(String message)? notify,
    bool? enabled,
    this.interval = const Duration(seconds: 30),
    this.retry = const Duration(seconds: 10),
    this.firstCheck = const Duration(seconds: 5),
    this.failuresBeforeUnreachable = 3,
  }) : _coordinatorOverride = coordinator,
       _probe = probe ?? _probeTunnel,
       _minewireState = minewireState ?? (() => AppHostApi().minewireState()),
       _notify =
           notify ??
           ((message) => NotificationService().pushNotification(message)),
       _enabled = enabled ?? AppPlatform.isDesktop;

  final ConnectionCoordinator? _coordinatorOverride;
  ConnectionCoordinator get _coordinator =>
      _coordinatorOverride ?? ConnectionCoordinator.instance;
  final Future<LivePingResult> Function(ConnectionRuntime runtime) _probe;
  final Future<List<MinewireEngineState>> Function() _minewireState;
  final Future<void> Function(String message) _notify;
  final bool _enabled;

  final Duration interval;
  final Duration retry;
  final Duration firstCheck;
  final int failuresBeforeUnreachable;

  final state = ValueNotifier(ConnectionHealth.none);

  Timer? _timer;
  String? _key;
  int _failures = 0;
  int _generation = 0;
  bool _started = false;

  void start() {
    if (!_enabled || _started) return;
    _started = true;
    _coordinator.state.addListener(_connectionChanged);
    _connectionChanged();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _coordinator.state.removeListener(_connectionChanged);
    _timer?.cancel();
    _timer = null;
    _key = null;
    _generation++;
    state.value = ConnectionHealth.none;
  }

  void _connectionChanged() {
    final view = _coordinator.state.value;
    final runtime = view.phase == ConnectionPhase.connected
        ? view.runtime
        : null;
    final key = runtime == null ? null : ConnectionHealth.keyOf(runtime);
    if (key == _key) return;
    _key = key;
    _generation++;
    _failures = 0;
    _timer?.cancel();
    _timer = null;
    if (key == null) {
      state.value = ConnectionHealth.none;
      return;
    }
    state.value = ConnectionHealth(key: key);
    _schedule(firstCheck);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(check()));
  }

  /// One round; the timers call it, tests call it directly.
  @visibleForTesting
  Future<void> check() async {
    final view = _coordinator.state.value;
    final runtime = view.runtime;
    final key = _key;
    final generation = _generation;
    if (key == null ||
        runtime == null ||
        view.phase != ConnectionPhase.connected ||
        ConnectionHealth.keyOf(runtime) != key) {
      return;
    }
    final minewireDown = await _minewireLost(runtime);
    LivePingResult result;
    try {
      result = await _probe(runtime);
    } catch (_) {
      result = const LivePingResult.failure();
    }
    _finish(generation, key, runtime, result, minewireDown);
  }

  void _finish(
    int generation,
    String key,
    ConnectionRuntime runtime,
    LivePingResult result,
    bool minewireDown,
  ) {
    if (generation != _generation || !_started) return;
    final previous = state.value;
    final node = runtime.entries.isEmpty ? '' : runtime.entries.first.name;
    if (result.reachable) {
      _failures = 0;
      state.value = ConnectionHealth(
        key: key,
        status: ConnectionHealthStatus.healthy,
        milliseconds: result.milliseconds,
        minewireDown: minewireDown,
      );
      if (previous.unreachable) {
        AppLog.info('connection through "$node" is back');
        unawaited(
          _post(appLocalizationsNoContext().connectionHealthRestoredNotice),
        );
      }
      _schedule(interval);
      return;
    }
    _failures++;
    final unreachable = _failures >= failuresBeforeUnreachable;
    state.value = ConnectionHealth(
      key: key,
      // Until the threshold the last verdict stands: one lost probe after
      // a sleep or a network change is not an outage.
      status: unreachable
          ? ConnectionHealthStatus.unreachable
          : previous.status,
      milliseconds: previous.milliseconds,
      minewireDown: minewireDown,
    );
    if (unreachable && !previous.unreachable) {
      AppLog.warning(
        'no connection through "$node" after $_failures probes'
        '${minewireDown ? '; a minewire engine has no session' : ''}',
      );
      unawaited(
        _post(appLocalizationsNoContext().connectionHealthLostNotice(node)),
      );
    }
    _schedule(retry);
  }

  Future<bool> _minewireLost(ConnectionRuntime runtime) async {
    final ports = runtime.minewirePorts.values.toSet();
    if (ports.isEmpty) return false;
    try {
      final engines = {
        for (final engine in await _minewireState())
          if (engine.localPort case final port? when ports.contains(port))
            port: engine,
      };
      return ports.any((port) => engines[port]?.connected != true);
    } catch (_) {
      return false;
    }
  }

  Future<void> _post(String message) async {
    try {
      await _notify(message);
    } catch (error) {
      AppLog.warning('health notification failed: ${error.runtimeType}');
    }
  }

  static Future<LivePingResult> _probeTunnel(ConnectionRuntime runtime) {
    final policy = runtime.configuration.policy;
    return LivePingProbe(
      proxyPort: policy.usesSystemProxy(runtime.platform)
          ? policy.systemProxyPort
          : null,
    ).measure();
  }
}
