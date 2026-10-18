import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/menu/tray/service.dart';
import 'package:onexray/service/shared/menu/tray/entry.dart';
import 'package:onexray/service/shared/menu/tray/platform.dart';

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

Iterable<TrayMenuEntry> _items(List<TrayMenuEntry> entries) sync* {
  for (final entry in entries) {
    yield entry;
    if (entry.children case final children?) yield* _items(children);
  }
}

final class _FakeTrayPlatform implements TrayPlatform {
  _FakeTrayPlatform({
    required this.calls,
    required this.menus,
    required this.beforeIcon,
    required this.popup,
  });

  final List<MethodCall> calls;
  final List<List<TrayMenuEntry>> menus;
  final Future<void> Function() beforeIcon;
  final Future<void> Function() popup;
  late void Function() _onClick;
  late void Function() _onRightClick;
  late void Function(bool) _onMenuVisibility;
  late void Function(TrayMenuEntry) _onSelect;

  @override
  void init({
    required void Function() onClick,
    required void Function() onRightClick,
    required void Function(bool) onMenuVisibility,
  }) {
    _onClick = onClick;
    _onRightClick = onRightClick;
    _onMenuVisibility = onMenuVisibility;
    calls.add(const MethodCall('setToolTip', {'toolTip': 'HYPER CLIENT'}));
    if (AppPlatform.isMacOS) {
      calls.add(const MethodCall('setTitle', {'title': ''}));
    }
  }

  void click() => _onClick();
  void rightClick() => _onRightClick();
  void select(TrayMenuEntry entry) => _onSelect(entry);

  @override
  Future<void> setIcon(String path) async {
    calls.add(MethodCall('setIcon', {'path': path}));
    await beforeIcon();
  }

  @override
  Future<void> setToolTip(String text) async {
    calls.add(MethodCall('setToolTip', {'toolTip': text}));
  }

  @override
  void setMenu(
    List<TrayMenuEntry> entries,
    void Function(TrayMenuEntry) onSelect,
  ) {
    calls.add(const MethodCall('setContextMenu'));
    menus.add(List.unmodifiable(entries));
    _onSelect = onSelect;
  }

  @override
  Future<void> openMenu() async {
    _onMenuVisibility(true);
    try {
      await popup();
    } finally {
      _onMenuVisibility(false);
    }
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeTrayPlatform platform;
  late AppDatabase db;
  late TrayService tray;
  late ConnectionCoordinator coordinator;
  late Completer<void> popupClosed;
  Completer<void>? iconReady;
  final menus = <List<TrayMenuEntry>>[];
  final calls = <MethodCall>[];
  final choices = <Map<String, dynamic>>[];
  var popups = 0;
  var connections = 0;
  var windows = 0;

  Future<void> click(TrayMenuEntry entry) async {
    platform.select(entry);
    await pumpEventQueue();
  }

  setUp(() async {
    menus.clear();
    calls.clear();
    choices.clear();
    popups = 0;
    connections = 0;
    windows = 0;
    iconReady = null;
    popupClosed = Completer<void>();
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    coordinator = ConnectionCoordinator(database: db, disposeStatus: () {});
    addTearDown(coordinator.dispose);
    platform = _FakeTrayPlatform(
      calls: calls,
      menus: menus,
      beforeIcon: () async => await iconReady?.future,
      popup: () async {
        popups++;
        await popupClosed.future;
      },
    );
    tray =
        TrayService.forTesting(
            database: db,
            coordinator: coordinator,
            platform: platform,
            connect: () async => connections++,
            notify: (_) async => fail('No notification is expected'),
            showMainWindow: () async => windows++,
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
    final keys = _items(menus.last).map((item) => item.key).toSet();
    expect(keys, contains('quitApp'));
    expect(
      keys.contains('quitAndStopVpn'),
      AppPlatform.isMacOS ||
          (AppPlatform.isWindows && windowsBuildMode == WindowsMode.msix),
    );
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
    expect(titles, AppPlatform.isMacOS ? isNotEmpty : isEmpty);
    expect(titles.map((call) => call.arguments['title']), everyElement(''));
    expect(
      calls
          .where((call) => call.method == 'setToolTip')
          .map((call) => call.arguments['toolTip']),
      everyElement(startsWith('HYPER CLIENT')),
    );
    expect(_items(menus.last).any((item) => item.key == 'stopVpn'), isTrue);
    expect(calls.where((call) => call.method == 'setIcon'), hasLength(2));
    expect(titles, AppPlatform.isMacOS ? hasLength(1) : isEmpty);

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

  test(
    'the left button opens the App on Windows, the right one the menu',
    () async {
      platform.click();
      await pumpEventQueue();
      // Elsewhere either button opens the menu, as upstream.
      expect((windows, popups), AppPlatform.isWindows ? (1, 0) : (0, 1));
      if (!AppPlatform.isWindows) {
        popupClosed.complete();
        await pumpEventQueue();
        popupClosed = Completer<void>();
      }

      platform.rightClick();
      await pumpEventQueue();
      expect(popups, AppPlatform.isWindows ? 1 : 2);
      expect(windows, AppPlatform.isWindows ? 1 : 0);
    },
  );

  test('tooltip names the state and the node without flags', () async {
    List<String> toolTips() => [
      for (final call in calls.where((call) => call.method == 'setToolTip'))
        call.arguments['toolTip'] as String,
    ];
    final l = appLocalizationsNoContext();
    expect(toolTips().last, 'HYPER CLIENT');

    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: _runtime('\u{1F1F3}\u{1F1F1} Main'),
    );
    await pumpEventQueue();
    expect(toolTips().last, 'HYPER CLIENT · ${l.prototypeConnected} · Main');

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
    // Windows shows at most 127 UTF-16 units.
    expect(toolTips().last, startsWith('HYPER CLIENT · '));
    expect(toolTips().last.length, lessThanOrEqualTo(120));
    expect(toolTips().last, endsWith('…'));
  });

  test(
    'open menu keeps its actions while background updates queue a new menu',
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
          .singleWhere((item) => item.key == 'startVpn');
      final automatic = _items(oldMenu)
          .singleWhere((item) => item.key == 'automatic');
      platform.rightClick();
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
      await click(start);
      await click(automatic);
      expect(connections, 1);
      expect(choices, hasLength(1));
      expect(menus.length, published);

      popupClosed.complete();
      await pumpEventQueue();
      expect(menus.length, published + 1);
      expect(
        _items(menus.last)
            .singleWhere((item) => item.key == 'source:$sourceId')
            .label,
        'Renamed provider',
      );
      final newStart = _items(menus.last)
          .singleWhere((item) => item.key == 'startVpn');
      await click(newStart);
      expect(connections, 2);
    },
  );
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
    Iterable<String?> sourceKeys(List<TrayMenuEntry> menu, String prefix) =>
        _items(menu)
            .map((item) => item.key)
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
        .singleWhere((item) => item.key == 'source:${ids[9]}');
    platform.rightClick();
    await pumpEventQueue();
    expect(popups, 1);

    await db.subscriptionDao.deleteRow(ids.first);
    await pumpEventQueue();
    await tray.refreshTrayManager();
    expect(menus, hasLength(published));
    await click(choice);
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
      coordinator.state.value = const ConnectionView(
        phase: ConnectionPhase.connected,
      );
      final refresh = tray.refreshTrayManager();
      platform.rightClick();
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
    platform.rightClick();
    await pumpEventQueue();
    final published = menus.length;
    await tray.refreshTrayManager();
    popupClosed.completeError(PlatformException(code: 'popup-failed'));
    await pumpEventQueue();
    expect(menus.length, published + 1);
    await tray.refreshTrayManager();
    expect(menus.length, published + 2);
  });

  test('disposing the tray cancels an in-flight menu publication', () async {
    iconReady = Completer<void>();
    coordinator.state.value = const ConnectionView(
      phase: ConnectionPhase.connected,
    );
    final refreshing = tray.refreshTrayManager();
    final published = menus.length;
    tray.dispose();
    iconReady!.complete();

    await refreshing;

    expect(menus, hasLength(published));
  });
}
