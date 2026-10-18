import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/health.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/ping/live_probe.dart';

ConnectionRuntime _runtime(
  int node, {
  Map<int, int> minewirePorts = const {},
  DateTime? startedAt,
}) => ConnectionRuntime.create(
  configuration: ConnectionConfiguration(),
  compiled: CompiledConnection(
    xrayJson: '{}',
    entries: [
      ResolvedServer(id: node, sourceId: 1, outbound: {'tag': 'Node $node'}),
    ],
    finalExit: null,
    nodeTags: {'app-entry-0': node},
  ),
  platform: ConnectionPlatform.windows,
  request: StartVpnRequest(null, '10820', '18003', '{}'),
  minewirePorts: minewirePorts,
  startedAt: startedAt ?? DateTime.fromMillisecondsSinceEpoch(1000),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Localized notices read the language from the event bus.
  AppEventBus();
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late ConnectionHealthMonitor monitor;
  late List<LivePingResult> results;
  late List<String> notices;
  var engines = <MinewireEngineState>[];
  var probes = 0;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(database: db, disposeStatus: () {});
    results = [];
    notices = [];
    engines = [];
    probes = 0;
    monitor = ConnectionHealthMonitor(
      coordinator: coordinator,
      probe: (_) async {
        probes++;
        return results.removeAt(0);
      },
      minewireState: () async => engines,
      notify: (message) async => notices.add(message),
      enabled: true,
      // The test drives every round itself.
      interval: const Duration(hours: 1),
      retry: const Duration(hours: 1),
      firstCheck: const Duration(hours: 1),
    )..start();
  });

  tearDown(() async {
    monitor.dispose();
    coordinator.dispose();
    await db.close();
  });

  void connect(ConnectionRuntime runtime) => coordinator.state.value =
      ConnectionView(phase: ConnectionPhase.connected, runtime: runtime);

  test(
    'three failed probes in a row mark the connection unreachable',
    () async {
      final l = appLocalizationsNoContext();
      final runtime = _runtime(1);
      connect(runtime);
      expect(monitor.state.value.status, ConnectionHealthStatus.checking);
      expect(monitor.state.value.appliesTo(runtime), isTrue);

      results.add(const LivePingResult.success(140));
      await monitor.check();
      expect(monitor.state.value.status, ConnectionHealthStatus.healthy);
      expect(monitor.state.value.milliseconds, 140);

      results.addAll(List.filled(2, const LivePingResult.failure()));
      await monitor.check();
      await monitor.check();
      // One lost probe after a sleep or a network change is not an outage.
      expect(monitor.state.value.status, ConnectionHealthStatus.healthy);
      expect(notices, isEmpty);

      results.addAll(List.filled(2, const LivePingResult.failure()));
      await monitor.check();
      expect(monitor.state.value.unreachable, isTrue);
      await monitor.check();
      expect(notices, [l.connectionHealthLostNotice('Node 1')]);

      results.add(const LivePingResult.success(90));
      await monitor.check();
      expect(monitor.state.value.status, ConnectionHealthStatus.healthy);
      expect(notices.last, l.connectionHealthRestoredNotice);
      expect(probes, 6);
    },
  );

  test('a node switch or a disconnect starts over', () async {
    connect(_runtime(1));
    results.addAll(List.filled(3, const LivePingResult.failure()));
    for (var i = 0; i < 3; i++) {
      await monitor.check();
    }
    expect(monitor.state.value.unreachable, isTrue);

    // A live switch keeps the session (same start time), not the verdict.
    final next = _runtime(2);
    connect(next);
    expect(monitor.state.value.status, ConnectionHealthStatus.checking);
    expect(monitor.state.value.appliesTo(next), isTrue);
    results.add(const LivePingResult.failure());
    await monitor.check();
    expect(monitor.state.value.unreachable, isFalse);

    coordinator.state.value = const ConnectionView();
    expect(monitor.state.value, ConnectionHealth.none);
    await monitor.check();
    expect(probes, 4);
  });

  test('a probe that ends after a switch does not apply', () async {
    final pending = Completer<LivePingResult>();
    monitor.dispose();
    monitor = ConnectionHealthMonitor(
      coordinator: coordinator,
      probe: (_) => pending.future,
      minewireState: () async => engines,
      notify: (message) async => notices.add(message),
      enabled: true,
      interval: const Duration(hours: 1),
      retry: const Duration(hours: 1),
      firstCheck: const Duration(hours: 1),
      failuresBeforeUnreachable: 1,
    )..start();
    connect(_runtime(1));
    final check = monitor.check();
    connect(_runtime(2));
    pending.complete(const LivePingResult.failure());
    await check;
    expect(monitor.state.value.status, ConnectionHealthStatus.checking);
    expect(notices, isEmpty);
  });

  test('a minewire engine without a session is reported', () async {
    connect(_runtime(1, minewirePorts: {1: 41000}));
    engines = [MinewireEngineState(41000, true, false, 'EOF')];
    results.add(const LivePingResult.failure());
    await monitor.check();
    expect(monitor.state.value.minewireDown, isTrue);

    engines = [MinewireEngineState(41000, true, true, null)];
    results.add(const LivePingResult.success(200));
    await monitor.check();
    expect(monitor.state.value.minewireDown, isFalse);

    // An engine that is gone altogether has no session either.
    engines = [];
    results.add(const LivePingResult.success(200));
    await monitor.check();
    expect(monitor.state.value.minewireDown, isTrue);
  });

  test('mobile and disabled monitors never probe', () async {
    monitor.dispose();
    monitor = ConnectionHealthMonitor(
      coordinator: coordinator,
      probe: (_) async {
        probes++;
        return const LivePingResult.failure();
      },
      enabled: false,
    )..start();
    connect(_runtime(1));
    await monitor.check();
    expect((probes, monitor.state.value), (0, ConnectionHealth.none));
  });
}
