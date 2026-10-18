import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/menu/tray/service.dart';

ConnectionRuntime _runtime(String node) => ConnectionRuntime.create(
  configuration: ConnectionConfiguration(),
  compiled: CompiledConnection(
    xrayJson: '{}',
    entries: [
      ResolvedServer(id: 1, sourceId: 1, outbound: {'tag': node}),
    ],
    finalExit: null,
    nodeTags: const {'app-entry-0': 1},
  ),
  platform: ConnectionPlatform.windows,
  request: StartVpnRequest(null, '10820', '18003', '{}'),
);

Iterable<Map<dynamic, dynamic>> _items(Map<dynamic, dynamic> menu) sync* {
  for (final item in menu['items'] as List) {
    yield item as Map<dynamic, dynamic>;
    final submenu = item['submenu'];
    if (submenu != null) yield* _items(submenu as Map<dynamic, dynamic>);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tray_manager');
  late AppDatabase db;
  late TrayService tray;
  late ConnectionCoordinator coordinator;
  late Completer<void> popupClosed;
  Completer<void>? iconReady;
  final menus = <Map<dynamic, dynamic>>[];
  final calls = <MethodCall>[];
  final choices = <Map<String, dynamic>>[];
  var popups = 0;
  var connections = 0;

  Future<void> click(int id) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onTrayMenuItemClick', {'id': id}),
      ),
      (_) {},
    );
    await pumpEventQueue();
  }

  setUp(() async {
    menus.clear();
    calls.clear();
    choices.clear();
    popups = 0;
    connections = 0;
    iconReady = null;
    popupClosed = Completer<void>();
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    coordinator = ConnectionCoordinator(database: db, disposeStatus: () {});
    addTearDown(coordinator.dispose);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'setIcon':
          await iconReady?.future;
        case 'setContextMenu':
          menus.add(call.arguments['menu'] as Map<dynamic, dynamic>);
        case 'popUpContextMenu':
          popups++;
          // AppKit/Win32's menu tracking call returns when the popup closes.
          await popupClosed.future;
      }
      return null;
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    tray =
        TrayService.forTesting(
            database: db,
            coordinator: coordinator,
            connect: () async => connections++,
            notify: (_) async => fail('No notification is expected'),
            showMainWindow: () async => fail('No window is needed'),
          )
          ..onConfigurationChange = (values, _, validate) async {
            await validate();
            choices.add(values);
          };
    addTearDown(() async {
      tray.dispose();
      if (iconReady != null && !iconReady!.isCompleted) iconReady!.complete();
      if (!popupClosed.isCompleted) popupClosed.complete();
      await pumpEventQueue();
    });
    tray.init();
    await pumpEventQueue();
    await tray.refreshTrayManager();
  });

  test('tray stays icon-only and ignores traffic-only updates', () async {
    expect(calls.where((call) => call.method == 'setIcon'), hasLength(1));
    int visualCalls() => calls
        .where(
          (call) =>
              call.method == 'setIcon' ||
              call.method == 'setTitle' ||
              call.method == 'setToolTip',
        )
        .length;
    final initialVisualCalls = visualCalls();
    await tray.refreshTrayManager();
    expect(visualCalls(), initialVisualCalls);

    coordinator.state.value = const ConnectionView(
      phase: ConnectionPhase.connected,
      metricsAvailable: true,
      downloadSpeed: 1024,
      uploadSpeed: 2048,
    );
    await pumpEventQueue();
    final titles = calls.where((call) => call.method == 'setTitle');
    expect(titles, AppPlatform.isMacOS ? hasLength(1) : isEmpty);
    expect(titles.map((call) => call.arguments['title']), everyElement(''));
    expect(
      calls
          .where((call) => call.method == 'setToolTip')
          .map((call) => call.arguments['toolTip']),
      everyElement(startsWith('HYPER CLIENT')),
    );
    expect(_items(menus.last).any((item) => item['key'] == 'stopVpn'), isTrue);
    expect(calls.where((call) => call.method == 'setIcon'), hasLength(2));

    final published = calls.length;
    coordinator.state.value = const ConnectionView(
      phase: ConnectionPhase.connected,
      metricsAvailable: true,
      downloadSpeed: 987654,
      uploadSpeed: 123456,
    );
    await pumpEventQueue();
    expect(calls, hasLength(published));
  });

  test('tooltip names the state and the node without flags', () async {
    List<String> toolTips() => [
      for (final call in calls.where((call) => call.method == 'setToolTip'))
        call.arguments['toolTip'] as String,
    ];
    final l = appLocalizationsNoContext();
    final supported = AppPlatform.isWindows || AppPlatform.isMacOS;
    // Set right after the first icon: tray_manager 0.5.3 otherwise shows
    // uninitialized memory as the Windows tooltip.
    expect(toolTips(), supported ? ['HYPER CLIENT'] : isEmpty);

    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: _runtime('\u{1F1F3}\u{1F1F1} Main'),
    );
    await pumpEventQueue();
    expect(
      toolTips(),
      supported
          ? ['HYPER CLIENT', 'HYPER CLIENT · ${l.prototypeConnected} · Main']
          : isEmpty,
    );

    final published = calls.length;
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: _runtime('\u{1F1F3}\u{1F1F1} Main'),
      downloadSpeed: 4096,
    );
    await pumpEventQueue();
    expect(calls, hasLength(published));

    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: _runtime('Reserve \u{1F600}${'x' * 200}'),
    );
    await pumpEventQueue();
    if (supported) {
      expect(toolTips().last, startsWith('HYPER CLIENT · '));
      expect(toolTips().last.length, lessThanOrEqualTo(120));
      expect(toolTips().last, endsWith('…'));
    }
  });

  for (final rightClick in [false, true]) {
    test(
      'open menu survives background refresh (right click: $rightClick)',
      () async {
        final sourceId = await db.subscriptionDao.insertRow(
          SubscriptionCompanion.insert(
            name: 'Provider',
            url: 'https://example.com/sub',
            timestamp: DateTime(2026),
          ),
        );
        await pumpEventQueue();
        final oldMenu = menus.last;
        final published = menus.length;
        final start = _items(oldMenu)
            .singleWhere((item) => item['key'] == 'startVpn');
        final automatic = _items(oldMenu)
            .singleWhere((item) => item['key'] == 'automatic');
        if (rightClick) {
          tray.onTrayIconRightMouseDown();
        } else {
          tray.onTrayIconMouseDown();
        }
        await pumpEventQueue();
        expect(popups, 1);

        final source = (await db.subscriptionDao.searchRow(sourceId))!;
        await db.subscriptionDao.updateRow(
          source.copyWith(name: 'Renamed provider'),
        );
        await pumpEventQueue();
        await tray.refreshTrayManager();
        await tray.refreshTrayManager();
        expect(menus.length, published);
        await click(start['id'] as int);
        await click(automatic['id'] as int);
        expect(connections, 1);
        expect(choices, hasLength(1));
        expect(menus.length, published);

        popupClosed.complete();
        await pumpEventQueue();
        expect(menus.length, published + 1);
        expect(
          _items(
            menus.last,
          ).singleWhere((item) => item['key'] == 'source:$sourceId')['label'],
          'Renamed provider',
        );
        final newStart = _items(menus.last)
            .singleWhere((item) => item['key'] == 'startVpn');
        await click(newStart['id'] as int);
        expect(connections, 2);
      },
    );
  }

  test('data prefix refresh waits for an open menu to close', () async {
    final ids = <int>[];
    for (var i = 0; i < 12; i++) {
      ids.add(
        await db.subscriptionDao.insertRow(
          SubscriptionCompanion.insert(
            name: 'Provider ${12 - i}',
            url: 'https://example.com/$i',
            timestamp: DateTime(2026),
          ),
        ),
      );
    }
    await pumpEventQueue();
    Iterable<Object?> sourceKeys(Map<dynamic, dynamic> menu, String prefix) =>
        _items(menu)
            .map((item) => item['key'])
            .where((key) => key is String && key.startsWith(prefix));
    final oldMenu = menus.last;
    final published = menus.length;
    for (final prefix in ['source:', 'updateSubscription:']) {
      expect(sourceKeys(oldMenu, prefix), [
        for (final id in ids.sublist(0, 10)) '$prefix$id',
      ]);
    }
    expect(await db.subscriptionDao.allRows, hasLength(12));
    final choice = _items(oldMenu)
        .singleWhere((item) => item['key'] == 'source:${ids[9]}');
    tray.onTrayIconMouseDown();
    await pumpEventQueue();
    expect(popups, 1);

    await db.subscriptionDao.deleteRow(ids.first);
    await pumpEventQueue();
    await tray.refreshTrayManager();
    expect(menus, hasLength(published));
    await click(choice['id'] as int);
    expect(choices.single, {
      'expert': false,
      'selection': {'kind': 'source', 'id': ids[9]},
    });
    expect(menus, hasLength(published));

    popupClosed.complete();
    await pumpEventQueue();
    expect(menus, hasLength(published + 1));
    for (final prefix in ['source:', 'updateSubscription:']) {
      expect(sourceKeys(menus.last, prefix), [
        for (final id in ids.sublist(1, 11)) '$prefix$id',
      ]);
    }
    expect(await db.subscriptionDao.allRows, hasLength(11));
  });

  test(
    'opening waits for an in-flight publish and queues later refreshes',
    () async {
      iconReady = Completer<void>();
      // A new state, so the publish really sets a new icon.
      coordinator.state.value = const ConnectionView(
        phase: ConnectionPhase.connected,
      );
      final refresh = tray.refreshTrayManager();
      tray.onTrayIconMouseDown();
      await pumpEventQueue();
      expect(popups, 0);
      await tray.refreshTrayManager();
      iconReady!.complete();
      await refresh;
      await pumpEventQueue();
      expect(popups, 1);
      final published = menus.length;
      await tray.refreshTrayManager();
      expect(menus.length, published);
      popupClosed.complete();
      await pumpEventQueue();
      expect(menus.length, published + 1);
    },
  );

  test('popup failure releases queued refreshes', () async {
    tray.onTrayIconMouseDown();
    await pumpEventQueue();
    final published = menus.length;
    await tray.refreshTrayManager();
    popupClosed.completeError(PlatformException(code: 'popup-failed'));
    await pumpEventQueue();
    expect(menus.length, published + 1);
    await tray.refreshTrayManager();
    expect(menus.length, published + 2);
  });
}
