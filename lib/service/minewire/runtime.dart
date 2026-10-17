import 'dart:io';

import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/dns.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
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

  /// In TUN mode an engine's own uplink would be captured by the tunnel that
  /// leads back into it. Engines bind it to the physical interface; when
  /// that fails, or for a ping engine started unbound, these rules send it
  /// straight out through `direct`, which is bound too. Harmless in system
  /// proxy mode.
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
    String? interfaceName,
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
    String? interfaceName,
  }) => AppHostApi().startMinewire(
    serverAddress: serverAddress,
    password: password,
    mode: mode,
    localPort: localPort,
    interfaceName: interfaceName,
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
  static const timeoutCause = 'The minewire server did not answer in time';

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

  /// The interface engines bind their uplinks to. A desktop tunnel captures
  /// the default route, and the engines run in the App, outside the Core
  /// whose own dials are bound to the physical interface; unbound, an
  /// engine's uplink would go through the tunnel and be cut when it starts.
  static String? uplinkInterface({
    required ConnectionPlatform platform,
    required bool tunnel,
    required String interfaceName,
  }) {
    final desktop =
        platform == ConnectionPlatform.windows ||
        platform == ConnectionPlatform.linux;
    final name = interfaceName.trim();
    return tunnel && desktop && name.isNotEmpty ? name : null;
  }

  /// Starts an engine for every minewire server and returns the servers the
  /// compiler should use. On failure every engine started here is stopped.
  ///
  /// [reusePorts] brings engines back on the ports a still-running Core was
  /// compiled with, after the App restarted. [interfaceName] comes from
  /// [uplinkInterface].
  Future<MinewireMaterialized> materialize(
    List<ResolvedServer> servers, {
    Map<int, int> reusePorts = const {},
    String? interfaceName,
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
            interfaceName: interfaceName,
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

  /// Starts a throwaway engine for measuring [link] and returns its port
  /// once the engine holds a session with the server. The engine belongs to
  /// no runtime; the caller stops it with [stopPorts].
  Future<int> startProbe(MinewireLink link, {required Duration timeout}) async {
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
    );
    try {
      // A wrong password or a closed port fails at once instead of
      // holding up the rest of the ping batch until the timeout.
      await _waitConnected(port, timeout: timeout, failFast: true);
    } catch (_) {
      await stopPorts([port]);
      rethrow;
    }
    return port;
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
    Future<ResolvedServer?> Function(int id) load, {
    String? interfaceName,
  }) async {
    for (final entry in ports.entries) {
      if (_active.contains(entry.value)) continue;
      try {
        final server = await load(entry.key);
        if (server == null) {
          ygLogger('minewire server ${entry.key} is gone; cannot resume');
          continue;
        }
        await materialize(
          [server],
          reusePorts: {entry.key: entry.value},
          interfaceName: interfaceName,
        );
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

  /// minewire carries TCP only: the engine refuses SOCKS UDP. Xray's UDP
  /// queries through it never get an answer, so every lookup waits out the
  /// 4 s DNS timeout in proxy mode, and in TUN mode the system resolver gets
  /// nothing at all. DNS that may cross the tunnel switches to TCP; servers
  /// that go direct keep UDP.
  static void applyTcpDns(Map<String, dynamic> config) {
    if (config['dns'] case final Map dns) {
      final servers = dns['servers'];
      if (servers is List) {
        for (var index = 0; index < servers.length; index++) {
          final server = servers[index];
          if (server is String) {
            servers[index] = _tcpDnsAddress(server, null) ?? server;
          } else if (server is Map && server['tag'] != RoutingDns.directTag) {
            final address = _tcpDnsAddress(server['address'], server['port']);
            if (address != null) {
              server
                ..['address'] = address
                ..remove('port');
            }
          }
        }
      }
    }
    // Queries the tunnel's DNS outbound forwards instead of answering go
    // through its dialer, which in all-VPN mode is the node itself.
    for (final outbound in config['outbounds'] as List? ?? const []) {
      if (outbound is! Map || outbound['protocol'] != 'dns') continue;
      final stream = outbound['streamSettings'];
      final sockopt = stream is Map ? stream['sockopt'] : null;
      if (sockopt is Map && sockopt['dialerProxy'] == 'direct') continue;
      final settings = outbound['settings'];
      outbound['settings'] = <String, dynamic>{
        if (settings is Map) ...settings.cast<String, dynamic>(),
        'network': 'tcp',
      };
    }
  }

  /// `tcp://` form of a plain DNS server IP; null for anything else (DoH,
  /// `localhost`, `fakedns`, already TCP).
  static String? _tcpDnsAddress(Object? address, Object? port) {
    if (address is! String) return null;
    final ip = InternetAddress.tryParse(address.trim());
    if (ip == null) return null;
    final host = ip.type == InternetAddressType.IPv6
        ? '[${ip.address}]'
        : ip.address;
    final number = port is int ? port : int.tryParse('${port ?? ''}');
    return number == null || number == 53
        ? 'tcp://$host'
        : 'tcp://$host:$number';
  }

  /// [failFast] gives up on the first failed attempt; otherwise the engine
  /// keeps redialing until the timeout, which rides out a transient error.
  Future<void> _waitConnected(
    int port, {
    Duration? timeout,
    bool failFast = false,
  }) async {
    final waiting = Stopwatch()..start();
    // An engine listens at once but reaches the server in the background;
    // without waiting, Xray's first connections would hit a dead tunnel.
    while (waiting.elapsed < (timeout ?? _connectTimeout)) {
      final engine = (await _host.state())
          .where((state) => state.localPort == port)
          .firstOrNull;
      if (engine?.connected == true) return;
      if (engine == null ||
          engine.running != true ||
          (failFast && (engine.lastError?.isNotEmpty ?? false))) {
        throw ConnectionHostException(
          'minewireUnavailable',
          cause: engine?.lastError,
        );
      }
      // Short: a ping counts this wait as the node's session setup.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw const ConnectionHostException(
      'minewireUnavailable',
      cause: timeoutCause,
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
