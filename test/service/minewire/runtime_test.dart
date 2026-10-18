import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/minewire/link.dart';
import 'package:onexray/service/minewire/ping.dart';
import 'package:onexray/service/minewire/runtime.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/shared/ping/batch.dart';

class _Host implements MinewireHost {
  final engines = <int, MinewireEngineState>{};
  final starts = <StartMinewireRequest>[];
  int nextPort = 41000;
  bool connect = true;

  /// The engine keeps running and redialing after this error.
  String? retrying;

  @override
  Future<int> start({
    required String serverAddress,
    required String password,
    required String mode,
    int? localPort,
    String? interfaceName,
    String? logFile,
  }) async {
    starts.add(
      StartMinewireRequest(
        serverAddress,
        password,
        mode: mode,
        localPort: localPort,
        interfaceName: interfaceName,
        logFile: logFile,
      ),
    );
    final port = localPort ?? nextPort++;
    engines[port] = retrying != null
        ? MinewireEngineState(port, true, false, retrying)
        : MinewireEngineState(
            port,
            connect,
            connect,
            connect ? null : 'bad password',
          );
    return port;
  }

  @override
  Future<void> stop({int? localPort}) async {
    if (localPort == null) {
      engines.clear();
    } else {
      engines.remove(localPort);
    }
  }

  @override
  Future<List<MinewireEngineState>> state() async => engines.values.toList();
}

ResolvedServer _minewire(int id, {String host = '203.0.113.7'}) =>
    ResolvedServer(
      id: id,
      sourceId: 1,
      outbound: MinewireLink(
        password: 'secret',
        host: host,
        port: 25565,
        name: 'mw-$id',
      ).toOutbound(),
    );

ResolvedServer _vless(int id) => ResolvedServer(
  id: id,
  sourceId: 1,
  outbound: {
    'tag': 'v-$id',
    'protocol': 'vless',
    'settings': <String, dynamic>{},
  },
);

void main() {
  late _Host host;
  late MinewireRuntime runtime;

  setUp(() {
    host = _Host();
    runtime = MinewireRuntime(
      host: host,
      resolve: (name) async => name == 'mw.test' ? ['198.51.100.1'] : [name],
      connectTimeout: const Duration(seconds: 1),
      logFile: () => '/run/minewire.log',
    );
  });

  test('minewire servers point at their engines, others stay', () async {
    final result = await runtime.materialize([_vless(1), _minewire(2)]);
    expect(result.servers[0].outbound['protocol'], 'vless');
    final socks = result.servers[1].outbound;
    expect(socks['protocol'], 'socks');
    expect(socks['tag'], 'mw-2');
    expect(socks['settings'], {'address': '127.0.0.1', 'port': 41000});
    expect(result.ports, {2: 41000});
    // The engine gets the already resolved address.
    expect(host.starts.single.serverAddress, '203.0.113.7:25565');
    // A running connection's engine keeps a log; see the ping test below.
    expect(host.starts.single.logFile, '/run/minewire.log');
    expect(runtime.activePorts, {41000});
  });

  test('bypass rules go first and replace stale ones', () async {
    final result = await runtime.materialize([_minewire(2)]);
    final config = <String, dynamic>{
      'routing': {
        'rules': [
          {
            'ruleTag': 'app-minewire-9',
            'ip': ['1.1.1.1/32'],
          },
          {'ruleTag': 'app-default', 'outboundTag': 'proxy'},
        ],
      },
    };
    MinewireRuntime.applyBypass(config, result.bypassRules);
    final rules = config['routing']['rules'] as List;
    expect(rules.map((rule) => rule['ruleTag']), [
      'app-minewire-2',
      'app-default',
    ]);
    expect(rules.first, {
      'ruleTag': 'app-minewire-2',
      'ip': ['203.0.113.7/32'],
      'port': '25565',
      'outboundTag': 'direct',
    });
  });

  test('a server used twice runs one engine', () async {
    final server = _minewire(2);
    final result = await runtime.materialize([server, server]);
    expect(host.starts, hasLength(1));
    expect(result.endpoints, hasLength(1));
  });

  test('an engine that cannot connect stops everything started', () async {
    await runtime.materialize([_minewire(1)]);
    host.connect = false;
    await expectLater(
      runtime.materialize([_minewire(2, host: 'mw.test'), _minewire(3)]),
      throwsA(
        isA<ConnectionHostException>().having(
          (error) => error.reason,
          'reason',
          'minewireUnavailable',
        ),
      ),
    );
    // Only the engine of the earlier runtime is left.
    expect(host.engines.keys, [41000]);
  });

  test('switching keeps the new engines and stops the old ones', () async {
    final old = await runtime.materialize([_minewire(1)]);
    final next = await runtime.materialize([_minewire(2)]);
    await runtime.keepOnly(next.ports.values.toSet());
    expect(host.engines.keys, next.ports.values);
    expect(host.engines.containsKey(old.ports[1]), isFalse);
    await runtime.stopAll();
    expect(host.engines, isEmpty);
  });

  test('a restarted App resumes engines on the Core\'s ports', () async {
    await runtime.resume({2: 45555}, (id) async => _minewire(id));
    expect(host.starts.single.localPort, 45555);
    expect(host.engines.keys, [45555]);
    // A deleted server is skipped, not fatal.
    await runtime.resume({3: 45556}, (_) async => null);
    expect(host.engines.keys, [45555]);
  });

  test('an invalid stored node fails clearly', () async {
    final broken = ResolvedServer(
      id: 5,
      sourceId: 1,
      outbound: {
        'tag': 'x',
        'protocol': 'minewire',
        'settings': <String, dynamic>{},
      },
    );
    await expectLater(
      runtime.materialize([broken]),
      throwsA(
        isA<ConnectionHostException>().having(
          (error) => error.reason,
          'reason',
          'minewireInvalid',
        ),
      ),
    );
  });

  test('engines bind their uplinks only under a desktop tunnel', () async {
    String? bound({
      ConnectionPlatform platform = ConnectionPlatform.windows,
      bool tunnel = true,
      String name = ' Ethernet ',
    }) => MinewireRuntime.uplinkInterface(
      platform: platform,
      tunnel: tunnel,
      interfaceName: name,
    );
    expect(bound(), 'Ethernet');
    expect(bound(platform: ConnectionPlatform.linux, name: 'eth0'), 'eth0');
    expect(bound(tunnel: false), isNull);
    expect(bound(platform: ConnectionPlatform.android), isNull);
    expect(bound(name: ''), isNull);

    await runtime.materialize([_minewire(2)], interfaceName: 'Ethernet');
    await runtime.resume(
      {3: 45557},
      (id) async => _minewire(id),
      interfaceName: 'Ethernet',
    );
    expect(host.starts.map((start) => start.interfaceName), [
      'Ethernet',
      'Ethernet',
    ]);
    await runtime.materialize([_minewire(4)]);
    expect(host.starts.last.toJson().containsKey('interface'), isFalse);
  });

  test('DNS that may cross the tunnel goes over TCP', () {
    final config = <String, dynamic>{
      'dns': {
        'servers': [
          {'address': 'fakedns', 'tag': 'app-dns-fake'},
          {'address': '8.8.8.8', 'tag': 'app-dns-proxy'},
          {'address': '2001:4860:4860::8888', 'port': 5353},
          {'address': '77.88.8.8', 'tag': 'app-dns-direct'},
          'https://dns.google/dns-query',
          '1.1.1.1',
          'localhost',
        ],
      },
      'outbounds': [
        {'tag': 'app-entry-0', 'protocol': 'socks'},
        {
          'tag': 'dnsOut',
          'protocol': 'dns',
          'settings': {
            'rules': [
              {'action': 'hijack', 'qType': '1,28'},
            ],
          },
          'streamSettings': {
            'sockopt': {'dialerProxy': 'app-entry-0'},
          },
        },
        {
          'tag': 'dnsDirect',
          'protocol': 'dns',
          'streamSettings': {
            'sockopt': {'dialerProxy': 'direct'},
          },
        },
      ],
    };
    MinewireRuntime.applyTcpDns(config);
    expect(config['dns']['servers'], [
      {'address': 'fakedns', 'tag': 'app-dns-fake'},
      {'address': 'tcp://8.8.8.8', 'tag': 'app-dns-proxy'},
      {'address': 'tcp://[2001:4860:4860::8888]:5353'},
      {'address': '77.88.8.8', 'tag': 'app-dns-direct'},
      'https://dns.google/dns-query',
      'tcp://1.1.1.1',
      'localhost',
    ]);
    final outbounds = config['outbounds'] as List;
    expect(outbounds[0].containsKey('settings'), isFalse);
    expect(outbounds[1]['settings'], {
      'rules': [
        {'action': 'hijack', 'qType': '1,28'},
      ],
      'network': 'tcp',
    });
    expect(outbounds[2].containsKey('settings'), isFalse);
  });

  group('ping', () {
    final link = MinewireLink(
      password: 'secret',
      host: '203.0.113.7',
      port: 25565,
      name: 'n',
    );

    test('runs the usual probe through a throwaway engine', () async {
      final probe = await MinewirePingProbe.start(link, 3, runtime: runtime);
      expect(probe.failure, isNull);
      // Throwaway engines would flood the log with logins and stops.
      expect(host.starts.single.logFile, isNull);
      // Not part of any runtime: a disconnect or switch leaves it alone.
      await runtime.stopAll();
      expect(host.engines.keys, [41000]);

      final source = jsonDecode(probe.source!.xrayJson);
      expect(source['outbounds'].single, {
        'tag': 'proxy',
        'protocol': 'socks',
        'settings': {'address': '127.0.0.1', 'port': 41000},
      });
      // The session setup counts, like another node's handshake does.
      final measured = probe.complete(
        const PingBatchResult(true, 150, '', countryCode: 'NL'),
      );
      expect(measured.success, isTrue);
      expect(measured.delay, greaterThanOrEqualTo(150));
      expect(measured.countryCode, 'NL');
      final failed = PingBatchResult.failed('timeout');
      expect(probe.complete(failed), same(failed));

      await probe.stop();
      expect(host.engines, isEmpty);
    });

    test('an engine that cannot log in is an error at once', () async {
      host.retrying = 'EOF';
      final watch = Stopwatch()..start();
      final probe = await MinewirePingProbe.start(link, 3, runtime: runtime);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(probe.source, isNull);
      expect(probe.failure!.success, isFalse);
      expect(probe.failure!.delay, PingDelayConstants.error);
      expect(probe.failure!.error, 'EOF');
      expect(host.engines, isEmpty);
    });

    test('an engine that never connects is a timeout', () async {
      host.retrying = '';
      final probe = await MinewirePingProbe.start(link, 1, runtime: runtime);
      expect(probe.failure!.delay, PingDelayConstants.timeout);
      expect(host.engines, isEmpty);
    });
  });

  test('Profile-Title names a subscription, plain or base64', () {
    expect(SubscriptionLoadResult.parseTitle('My VPN'), 'My VPN');
    expect(
      SubscriptionLoadResult.parseTitle('base64:0JzQvtC5IFZQTg=='),
      'Мой VPN',
    );
    expect(SubscriptionLoadResult.parseTitle('base64:%%%'), isNull);
    expect(SubscriptionLoadResult.parseTitle('  '), isNull);
    expect(SubscriptionLoadResult.parseTitle(null), isNull);
    expect(SubscriptionLoadResult.parseTitle('x' * 100)!.length, 64);
  });
}
