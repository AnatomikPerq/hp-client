import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/minewire/link.dart';
import 'package:onexray/service/minewire/ping.dart';
import 'package:onexray/service/minewire/runtime.dart';
import 'package:onexray/service/servers/subscription/service.dart';

class _Host implements MinewireHost {
  final engines = <int, MinewireEngineState>{};
  final starts = <StartMinewireRequest>[];
  int nextPort = 41000;
  bool connect = true;

  @override
  Future<int> start({
    required String serverAddress,
    required String password,
    required String mode,
    int? localPort,
  }) async {
    starts.add(
      StartMinewireRequest(
        serverAddress,
        password,
        mode: mode,
        localPort: localPort,
      ),
    );
    final port = localPort ?? nextPort++;
    engines[port] = MinewireEngineState(
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

  group('TCP ping', () {
    test('measures connect time to the server', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((socket) => socket.destroy());
      final result = await minewireTcpPing(
        MinewireLink(
          password: 'x',
          host: '127.0.0.1',
          port: server.port,
          name: 'n',
        ),
        3,
      );
      expect(result.success, isTrue);
      expect(result.delay, greaterThan(0));
    });

    test('an unreachable server is a failure', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      final result = await minewireTcpPing(
        MinewireLink(password: 'x', host: '127.0.0.1', port: port, name: 'n'),
        3,
      );
      expect(result.success, isFalse);
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
