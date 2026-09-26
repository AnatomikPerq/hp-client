import 'dart:io';

import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/minewire/link.dart';

/// A running engine for one server of the current runtime.
class MinewireEndpoint {
  final int nodeId;
  final int localPort;
  final List<String> serverIps;
  final int serverPort;

  const MinewireEndpoint({
    required this.nodeId,
    required this.localPort,
    required this.serverIps,
    required this.serverPort,
  });
}

/// Servers ready for the compiler: minewire ones point at their engines.
class MinewireMaterialized {
  final List<ResolvedServer> servers;
  final List<MinewireEndpoint> endpoints;

  const MinewireMaterialized(this.servers, this.endpoints);

  Map<int, int> get ports => {
    for (final endpoint in endpoints) endpoint.nodeId: endpoint.localPort,
  };

  /// In TUN mode an engine's own uplink is captured by the tunnel that leads
  /// back into it. These rules send it straight out through `direct`, which
  /// is bound to the physical interface. Harmless in system proxy mode.
  List<Map<String, dynamic>> get bypassRules => [
    for (final endpoint in endpoints)
      {
        'ruleTag': '${MinewireRuntime.bypassRulePrefix}${endpoint.nodeId}',
        'ip': [for (final ip in endpoint.serverIps) _cidr(ip)],
        'port': '${endpoint.serverPort}',
        'outboundTag': 'direct',
      },
  ];

  static String _cidr(String ip) => ip.contains(':') ? '$ip/128' : '$ip/32';
}

/// Engine calls, injectable for tests.
abstract interface class MinewireHost {
  Future<int> start({
    required String serverAddress,
    required String password,
    required String mode,
    int? localPort,
  });

  Future<void> stop({int? localPort});

  Future<List<MinewireEngineState>> state();
}

class _LibXrayMinewireHost implements MinewireHost {
  const _LibXrayMinewireHost();

  @override
  Future<int> start({
    required String serverAddress,
    required String password,
    required String mode,
    int? localPort,
  }) => AppHostApi().startMinewire(
    serverAddress: serverAddress,
    password: password,
    mode: mode,
    localPort: localPort,
  );

  @override
  Future<void> stop({int? localPort}) =>
      AppHostApi().stopMinewire(localPort: localPort);

  @override
  Future<List<MinewireEngineState>> state() => AppHostApi().minewireState();
}

/// Engines run inside libXray in the App process, next to the Core, which
/// reaches each one as an ordinary `socks` outbound on loopback.
class MinewireRuntime {
  static final instance = MinewireRuntime();
  static const bypassRulePrefix = 'app-minewire-';

  final MinewireHost _host;
  final Future<List<String>> Function(String host) _resolve;
  final Duration _connectTimeout;

  /// Engines started by this App session. Nothing else starts engines, so a
  /// session that never used minewire makes no libXray calls at all.
  final Set<int> _active = {};

  MinewireRuntime({
    MinewireHost? host,
    Future<List<String>> Function(String host)? resolve,
    this._connectTimeout = const Duration(seconds: 12),
  }) : _host = host ?? const _LibXrayMinewireHost(),
       _resolve = resolve ?? _lookup;

  /// Starts an engine for every minewire server and returns the servers the
  /// compiler should use. On failure every engine started here is stopped.
  ///
  /// [reusePorts] brings engines back on the ports a still-running Core was
  /// compiled with, after the App restarted.
  Future<MinewireMaterialized> materialize(
    List<ResolvedServer> servers, {
    Map<int, int> reusePorts = const {},
  }) async {
    final started = <int>[];
    final endpoints = <int, MinewireEndpoint>{};
    try {
      final result = <ResolvedServer>[];
      for (final server in servers) {
        final outbound = server.outbound;
        if (!MinewireLink.isOutbound(outbound)) {
          result.add(server);
          continue;
        }
        final link = MinewireLink.fromOutbound(outbound);
        if (link == null) {
          throw const ConnectionHostException('minewireInvalid');
        }
        var endpoint = endpoints[server.id];
        if (endpoint == null) {
          // Resolved before the tunnel is up: afterwards DNS may depend on
          // the very tunnel that is not working yet. The bypass rule needs
          // the addresses too.
          final ips = await _resolve(link.host);
          if (ips.isEmpty) {
            throw ConnectionHostException(
              'minewireUnavailable',
              cause: 'Cannot resolve ${link.host}',
            );
          }
          final port = await _host.start(
            serverAddress: _hostPort(ips.first, link.port),
            password: link.password,
            mode: link.mode,
            localPort: reusePorts[server.id],
          );
          started.add(port);
          _active.add(port);
          await _waitConnected(port);
          endpoint = MinewireEndpoint(
            nodeId: server.id,
            localPort: port,
            serverIps: ips,
            serverPort: link.port,
          );
          endpoints[server.id] = endpoint;
        }
        result.add(
          ResolvedServer(
            id: server.id,
            sourceId: server.sourceId,
            outbound: {
              'tag': link.name,
              'protocol': 'socks',
              'settings': {'address': '127.0.0.1', 'port': endpoint.localPort},
            },
          ),
        );
      }
      return MinewireMaterialized(result, endpoints.values.toList());
    } catch (_) {
      await stopPorts(started);
      rethrow;
    }
  }

  /// Stops the given engines; failures are logged, not thrown.
  Future<void> stopPorts(Iterable<int> ports) async {
    for (final port in ports.toList()) {
      _active.remove(port);
      try {
        await _host.stop(localPort: port);
      } catch (error) {
        ygLogger('stop minewire engine $port failed: $error');
      }
    }
  }

  /// Stops every engine except [keep], after a node switch or a disconnect.
  Future<void> keepOnly(Set<int> keep) =>
      stopPorts(_active.where((port) => !keep.contains(port)));

  Future<void> stopAll() => keepOnly(const {});

  /// After an App restart the Core may still run, compiled against engines
  /// that died with the previous App process. Brings them back on the same
  /// ports; a server deleted in the meantime cannot be resumed.
  Future<void> resume(
    Map<int, int> ports,
    Future<ResolvedServer?> Function(int id) load,
  ) async {
    for (final entry in ports.entries) {
      if (_active.contains(entry.value)) continue;
      try {
        final server = await load(entry.key);
        if (server == null) {
          ygLogger('minewire server ${entry.key} is gone; cannot resume');
          continue;
        }
        await materialize([server], reusePorts: {entry.key: entry.value});
      } catch (error) {
        ygLogger('resume minewire engine ${entry.value} failed: $error');
      }
    }
  }

  /// Puts minewire into [config]'s routing, ahead of every other rule: any
  /// rule above could send the engines' uplinks back into the tunnel.
  static void applyBypass(
    Map<String, dynamic> config,
    List<Map<String, dynamic>> rules,
  ) {
    if (rules.isEmpty) return;
    final current = config['routing'];
    final routing = <String, dynamic>{
      if (current is Map) ...current.cast<String, dynamic>(),
    };
    final existing = [
      if (routing['rules'] case final List list)
        for (final rule in list)
          if (!(rule is Map &&
              '${rule['ruleTag']}'.startsWith(bypassRulePrefix)))
            rule,
    ];
    routing['rules'] = <dynamic>[...rules, ...existing];
    config['routing'] = routing;
  }

  Future<void> _waitConnected(int port) async {
    final waiting = Stopwatch()..start();
    // An engine listens at once but reaches the server in the background;
    // without waiting, Xray's first connections would hit a dead tunnel.
    while (waiting.elapsed < _connectTimeout) {
      final engine = (await _host.state())
          .where((state) => state.localPort == port)
          .firstOrNull;
      if (engine?.connected == true) return;
      if (engine == null || engine.running != true) {
        throw ConnectionHostException(
          'minewireUnavailable',
          cause: engine?.lastError,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw const ConnectionHostException(
      'minewireUnavailable',
      cause: 'The minewire server did not answer in time',
    );
  }

  static String _hostPort(String ip, int port) =>
      ip.contains(':') ? '[$ip]:$port' : '$ip:$port';

  static Future<List<String>> _lookup(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return [literal.address];
    try {
      final records = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 6));
      // IPv4 first: the bypass rule and the engine then agree on one address
      // family most networks can route.
      final addresses = records.toList()
        ..sort(
          (a, b) => a.type == b.type
              ? 0
              : a.type == InternetAddressType.IPv4
              ? -1
              : 1,
        );
      return addresses.map((record) => record.address).toSet().toList();
    } catch (error) {
      ygLogger('resolve minewire host failed: $error');
      return const [];
    }
  }
}
