import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/system_proxy/manager.dart';
import 'package:onexray/core/system_proxy/platform.dart';
import 'package:onexray/core/tools/app_log.dart';
import 'package:onexray/core/tools/logger.dart';
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

  /// In proxy mode: where the system proxy sends traffic now that it no
  /// longer points at the App; apps then bypass the connection entirely.
  final String? proxyTakenOver;

  const ConnectionHealth({
    this.key,
    this.status = ConnectionHealthStatus.checking,
    this.milliseconds,
    this.minewireDown = false,
    this.proxyTakenOver,
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
      other.minewireDown == minewireDown &&
      other.proxyTakenOver == proxyTakenOver;

  @override
  int get hashCode =>
      Object.hash(key, status, milliseconds, minewireDown, proxyTakenOver);
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
///
/// In proxy mode the probe goes straight to the App's port, so it keeps
/// passing when the system proxy no longer points there and every app goes
/// around the connection. Each round therefore also checks the system proxy;
/// a takeover marks the connection unreachable at once.
final class ConnectionHealthMonitor {
  static final instance = ConnectionHealthMonitor();

  ConnectionHealthMonitor({
    ConnectionCoordinator? coordinator,
    Future<LivePingResult> Function(ConnectionRuntime runtime)? probe,
    Future<List<MinewireEngineState>> Function()? minewireState,
    Future<void> Function(String message)? notify,
    Future<String?> Function(ConnectionRuntime runtime)? proxyTakenOver,
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
       _proxyTakenOver = proxyTakenOver ?? _systemProxyTakenOver,
       _enabled = enabled ?? AppPlatform.isDesktop;

  final ConnectionCoordinator? _coordinatorOverride;
  ConnectionCoordinator get _coordinator =>
      _coordinatorOverride ?? ConnectionCoordinator.instance;
  final Future<LivePingResult> Function(ConnectionRuntime runtime) _probe;
  final Future<List<MinewireEngineState>> Function() _minewireState;
  final Future<void> Function(String message) _notify;
  final Future<String?> Function(ConnectionRuntime runtime) _proxyTakenOver;
  final bool _enabled;

  final Duration interval;
  final Duration retry;
  final Duration firstCheck;
  final int failuresBeforeUnreachable;

  final state = ValueNotifier(ConnectionHealth.none);

  Timer? _timer;
  String? _key;
  bool _blocking = false;
  int _failures = 0;
  int _generation = 0;
  bool _started = false;

  void start() {
    if (!_enabled || _started) return;
    _started = true;
    _coordinator.state.addListener(_connectionChanged);
    _coordinator.killSwitchBlocking.addListener(_blockingChanged);
    _connectionChanged();
    _blockingChanged();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _coordinator.state.removeListener(_connectionChanged);
    _coordinator.killSwitchBlocking.removeListener(_blockingChanged);
    _blocking = false;
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

  /// The kill switch took over: the Core is gone and apps are offline.
  /// Without a word they would look like a dead network.
  void _blockingChanged() {
    final blocking = _coordinator.killSwitchBlocking.value;
    if (blocking == _blocking) return;
    _blocking = blocking;
    if (!blocking) return;
    AppLog.warning(
      'the kill switch keeps apps offline until a reconnect or a disconnect',
    );
    unawaited(_post(appLocalizationsNoContext().killSwitchBlockedNotice));
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
    String? proxyTakenOver;
    try {
      proxyTakenOver = await _proxyTakenOver(runtime);
    } catch (error) {
      // An unreadable proxy setting is no evidence of a takeover.
      ygLogger('read system proxy failed: $error');
    }
    LivePingResult result;
    try {
      result = await _probe(runtime);
    } catch (_) {
      result = const LivePingResult.failure();
    }
    _finish(generation, key, runtime, result, minewireDown, proxyTakenOver);
  }

  void _finish(
    int generation,
    String key,
    ConnectionRuntime runtime,
    LivePingResult result,
    bool minewireDown,
    String? proxyTakenOver,
  ) {
    if (generation != _generation || !_started) return;
    final previous = state.value;
    final node = runtime.nodeName;
    if (result.reachable && proxyTakenOver == null) {
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
    if (!result.reachable) _failures++;
    // A takeover is read, not guessed from lost probes: no threshold.
    final unreachable =
        proxyTakenOver != null || _failures >= failuresBeforeUnreachable;
    state.value = ConnectionHealth(
      key: key,
      // Until the threshold the last verdict stands: one lost probe after
      // a sleep or a network change is not an outage.
      status: unreachable
          ? ConnectionHealthStatus.unreachable
          : previous.status,
      milliseconds: previous.milliseconds,
      minewireDown: minewireDown,
      proxyTakenOver: proxyTakenOver,
    );
    if (proxyTakenOver != null && proxyTakenOver != previous.proxyTakenOver) {
      AppLog.warning(
        'the system proxy no longer points at the App '
        '($proxyTakenOver); apps bypass "$node"',
      );
      unawaited(
        _post(appLocalizationsNoContext().connectionHealthProxyTakenNotice),
      );
    } else if (unreachable && !previous.unreachable) {
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

  static Future<String?> _systemProxyTakenOver(
    ConnectionRuntime runtime,
  ) async {
    if (!runtime.configuration.policy.usesSystemProxy(runtime.platform)) {
      return null;
    }
    final manager = await createSystemProxyManager(VpnConstants.runDir);
    final current = await manager?.takenOver();
    return current == null ? null : describeSystemProxy(current);
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
