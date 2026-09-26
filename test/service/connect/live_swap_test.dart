import 'dart:convert';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/live_control.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';

const _control = LiveControl(port: 43127, password: 'per-session-secret-123');

Map<String, dynamic> _config(
  int node, {
  List<Map<String, dynamic>> inbounds = const [],
}) {
  final config = <String, dynamic>{
    'inbounds': [
      {'tag': 'tunIn', 'protocol': 'socks', 'port': 10820},
      ...inbounds,
    ],
    'outbounds': [
      {
        'tag': 'app-entry-0',
        'protocol': 'vless',
        'settings': {'address': 'node-$node.test'},
      },
      {'tag': 'direct', 'protocol': 'freedom'},
      {'tag': 'block', 'protocol': 'blackhole'},
    ],
    'routing': {
      'domainStrategy': 'IPIfNonMatch',
      'balancers': [
        {
          'tag': 'proxy',
          'selector': ['app-entry-0'],
        },
      ],
      'rules': [
        {'ruleTag': 'app-default', 'balancerTag': 'proxy'},
      ],
    },
  };
  _control.apply(config);
  return config;
}

ConnectionConfiguration _configuration(int node, {PlatformPolicy? policy}) =>
    ConnectionConfiguration(
      connection: ConnectionSettings(selection: ServerSelection.server(node)),
      policy: policy,
    );

ConnectionRuntime _runtime(
  int node, {
  Map<String, dynamic>? config,
  PlatformPolicy? policy,
  DateTime? startedAt,
}) {
  final xrayJson = jsonEncode(config ?? _config(node));
  final server = ResolvedServer(
    id: node,
    sourceId: 1,
    outbound: {'tag': 'node-$node', 'protocol': 'vless'},
  );
  return ConnectionRuntime.create(
    configuration: _configuration(node, policy: policy),
    compiled: CompiledConnection(
      xrayJson: xrayJson,
      entries: [server],
      finalExit: null,
      nodeTags: const {'app-entry-0': 1},
    ),
    platform: ConnectionPlatform.windows,
    request: StartVpnRequest(
      null,
      '10820',
      '18003',
      jsonEncode(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest(xrayJson).toJson(),
        ).toJson(),
      ),
    ),
    control: _control,
    startedAt: startedAt ?? DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  group('LiveControl', () {
    test('the control rule is first and the API has no raw listener', () {
      final config = _config(1);
      expect(config['api'], {
        'tag': 'api',
        'services': ['HandlerService', 'RoutingService'],
      });
      expect((config['api'] as Map).containsKey('listen'), isFalse);
      final inbound = (config['inbounds'] as List).last as Map;
      expect(inbound['listen'], '127.0.0.1');
      expect(inbound['settings']['auth'], 'password');
      expect((config['routing']['rules'] as List).first, {
        'ruleTag': 'app-control',
        'inboundTag': ['app-control'],
        'outboundTag': 'api',
      });
    });

    test('each session gets its own strong password', () {
      final a = LiveControl.create(1);
      final b = LiveControl.create(1);
      expect(a.password, isNot(b.password));
      expect(a.password.length, greaterThanOrEqualTo(32));
      expect(
        LiveControl.create(1, random: Random(1)).password,
        LiveControl.create(1, random: Random(1)).password,
      );
    });

    test('only outbound and routing changes can be applied live', () {
      expect(LiveControl.swappable(_config(1), _config(2)), isTrue);
      expect(
        LiveControl.swappable(
          _config(1),
          _config(
            2,
            inbounds: [
              {'tag': 'extra', 'protocol': 'http', 'port': 8080},
            ],
          ),
        ),
        isFalse,
      );
      final dns = _config(2)
        ..['dns'] = {
          'servers': ['1.1.1.1'],
        };
      expect(LiveControl.swappable(_config(1), dns), isFalse);
    });

    test('operations replace the default and keep untouched outbounds', () {
      final operations = LiveControl.operations(_config(1), _config(2));
      expect(
        operations.map(
          (op) => '${op.op}:${op.tag ?? op.outbound?['tag'] ?? ''}',
        ),
        ['removeOutbound:app-entry-0', 'addOutbound:app-entry-0', 'addRules:'],
      );
      final rules = operations.last.routing!;
      expect((rules['rules'] as List).first['ruleTag'], 'app-control');
      expect(rules['balancers'], isNotEmpty);
    });

    test('an unchanged first outbound is still replaced', () {
      final next = _config(1);
      (next['outbounds'] as List)[2] = {
        'tag': 'block',
        'protocol': 'blackhole',
        'settings': {
          'response': {'type': 'http'},
        },
      };
      final operations = LiveControl.operations(_config(1), next);
      expect(
        operations.where((op) => op.op == 'removeOutbound').map((op) => op.tag),
        ['app-entry-0', 'block'],
      );
      expect(
        operations
            .where((op) => op.op == 'addOutbound')
            .map((op) => op.outbound!['tag']),
        ['app-entry-0', 'block'],
      );
    });
  });

  group('coordinator', () {
    late AppDatabase db;
    late ConnectionRuntime running;
    late List<String> calls;
    late List<List<ControlXrayOperation>> swaps;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      running = _runtime(1);
      calls = [];
      swaps = [];
      await db.connectionConfigDao.commit(
        configurationJson: running.configuration.encode(),
      );
    });

    ConnectionCoordinator create({
      Map<String, dynamic>? next,
      bool swapFails = false,
    }) {
      ConnectionRuntime? current = running;
      final coordinator = ConnectionCoordinator(
        database: db,
        readRuntime: () async => current,
        inspect: (_) async => HostConnection(
          current == null ? VpnStatus.disconnected : VpnStatus.connected,
          runtime: current,
        ),
        stop: () async {
          calls.add('stop');
          current = null;
          return const HostConnection(VpnStatus.disconnected);
        },
        start: (runtime) async {
          calls.add('start');
          current = runtime;
          return HostConnection(VpnStatus.connected, runtime: runtime);
        },
        prepare: (configuration, _) async {
          calls.add('prepare');
          return _runtime(2);
        },
        prepareSwap: (configuration, _, reuse) async {
          calls.add('prepareSwap');
          expect(reuse, same(running));
          return _runtime(2, config: next, startedAt: reuse.startedAt);
        },
        swap: (from, to, operations) async {
          calls.add('swap');
          swaps.add(operations);
          if (swapFails) throw StateError('api unreachable');
          current = to;
          return HostConnection(VpnStatus.connected, runtime: to);
        },
        resumeRuntime: (_) async {},
      );
      addTearDown(coordinator.dispose);
      return coordinator;
    }

    Future<void> select(ConnectionCoordinator coordinator, int node) async {
      await coordinator.initialize(observe: false, registerReferences: false);
      await coordinator.apply(_configuration(node), allowReconnect: true);
    }

    test('a node switch reaches the live Core without a restart', () async {
      final coordinator = create();
      await select(coordinator, 2);
      expect(calls, ['prepareSwap', 'swap']);
      expect(swaps.single.first.op, 'removeOutbound');
      expect(coordinator.state.value.phase, ConnectionPhase.connected);
      final stored = await coordinator.configuration;
      expect(stored.connection.selection.id, 2);
      // Same session: traffic counters and uptime continue.
      expect(coordinator.state.value.runtime!.identity, running.identity);
    });

    test('a failed live switch restarts the Core instead', () async {
      final coordinator = create(swapFails: true);
      await select(coordinator, 2);
      expect(calls, ['prepareSwap', 'swap', 'stop', 'prepare', 'start']);
      expect(coordinator.state.value.phase, ConnectionPhase.connected);
    });

    test('a change the API cannot apply restarts the Core', () async {
      final coordinator = create(
        next: _config(
          2,
          inbounds: [
            {'tag': 'extra', 'protocol': 'http', 'port': 8080},
          ],
        ),
      );
      await select(coordinator, 2);
      expect(calls, ['prepareSwap', 'stop', 'prepare', 'start']);
    });

    test('a policy change never tries the live path', () async {
      final coordinator = create();
      await coordinator.initialize(observe: false, registerReferences: false);
      await coordinator.apply(
        ConnectionConfiguration(
          connection: running.configuration.connection,
          policy: PlatformPolicy.defaults().withDesktopRunMode(
            DesktopRunMode.systemProxy,
          ),
        ),
        allowReconnect: true,
      );
      expect(calls, ['stop', 'prepare', 'start']);
    });
  });
}
