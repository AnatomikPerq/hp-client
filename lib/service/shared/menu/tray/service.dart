import 'dart:ui';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:onexray/gen/assets.gen.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/failure.dart';
import 'package:onexray/service/connect/health.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/provider_mode.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/failure.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/failure.dart' show appFailureMessage;
import 'package:onexray/service/shared/menu/tray/menu.dart';
import 'package:onexray/service/shared/menu/tray/entry.dart';
import 'package:onexray/service/shared/menu/tray/platform.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/launch/app_startup.dart';
import 'package:onexray/service/shared/notification/service.dart';
import 'package:collection/collection.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:window_manager/window_manager.dart';

final class TrayService {
  static final TrayService _singleton = TrayService._internal();

  factory TrayService() => _singleton;

  TrayService._internal()
    : _databaseOverride = null,
      _coordinatorOverride = null,
      _healthOverride = null,
      _platform = NativeTrayPlatform(),
      _connect = (() => ConnectionCoordinator.instance.connect()),
      _notify = ((message) => NotificationService().pushNotification(message)),
      _showMainWindow = (() => AppStartupService().showMainWindow());

  @visibleForTesting
  TrayService.forTesting({
    required this._connect,
    required this._notify,
    required this._showMainWindow,
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
    ValueListenable<ConnectionHealth>? health,
    TrayPlatform? platform,
  }) : _databaseOverride = database,
       _coordinatorOverride = coordinator,
       _healthOverride = health,
       _platform = platform ?? NativeTrayPlatform();

  final AppDatabase? _databaseOverride;
  final ConnectionCoordinator? _coordinatorOverride;
  final ValueListenable<ConnectionHealth>? _healthOverride;
  final TrayPlatform _platform;
  AppDatabase get _db => _databaseOverride ?? AppDatabase();
  ConnectionCoordinator get _coordinator =>
      _coordinatorOverride ?? ConnectionCoordinator.instance;
  ValueListenable<ConnectionHealth> get _health =>
      _healthOverride ?? ConnectionHealthMonitor.instance.state;

  Future<void> Function(
    Map<String, dynamic> values,
    String label,
    Future<void> Function() validate,
  )?
  onConfigurationChange;
  SubscriptionFormatConfirmation? onSubscriptionFormatConfirmation;
  TrayMenuData _data = TrayMenuData();
  final _listeners = <StreamSubscription<dynamic>>[];
  final _pendingUpdates = <String>{};
  bool _changingConfiguration = false;
  bool _refreshRequested = false;
  bool _menuOpen = false;
  Future<void>? _refreshing;

  final Future<void> Function() _connect;
  final Future<void> Function(String) _notify;
  final Future<void> Function() _showMainWindow;

  //==========================
  var _initialized = false;
  ConnectionPhase? _lastPhase;
  bool? _lastCanDisconnect;
  String? _lastToolTip;
  String? _trayIcon;
  String? _toolTip;
  // The menu marks the running provider configuration.
  int? _lastProfileId;

  bool get _canQuitWithoutStoppingVpn =>
      AppPlatform.isMacOS ||
      (AppPlatform.isWindows && windowsBuildMode == WindowsMode.msix);

  void init() {
    if (!AppPlatform.isDesktop || _initialized) {
      return;
    }

    _platform.init(
      // On Windows the left button opens the App and only the right one the
      // menu, as other tray apps do. Elsewhere either opens the menu.
      onClick: () =>
          unawaited(AppPlatform.isWindows ? _showWindow() : _openMenu()),
      onRightClick: () => unawaited(_openMenu()),
      onMenuVisibility: (visible) {
        _menuOpen = visible;
        if (!visible && _refreshRequested) scheduleMicrotask(_requestRefresh);
      },
    );
    _coordinator.state.addListener(_connectionChanged);
    _health.addListener(_connectionChanged);
    _coordinator.killSwitchBlocking.addListener(_connectionChanged);
    _initialized = true;
    _listeners.add(
      TrayMenuData.watch(_db).listen(
        (data) {
          _data = data;
          _requestRefresh();
        },
        onError: (Object error, StackTrace stackTrace) {
          ygLogger('Read tray choices failed: $error\n$stackTrace');
        },
      ),
    );
    _listeners.add(
      AppEventBus.instance.stream
          .map((state) => state.languageCode)
          .distinct()
          .listen((_) => _requestRefresh()),
    );
  }

  void dispose() {
    if (!AppPlatform.isDesktop || !_initialized) {
      return;
    }
    _initialized = false;
    _platform.dispose();
    _coordinator.state.removeListener(_connectionChanged);
    _health.removeListener(_connectionChanged);
    _coordinator.killSwitchBlocking.removeListener(_connectionChanged);
    for (final listener in _listeners) {
      unawaited(listener.cancel());
    }
    _listeners.clear();
    onConfigurationChange = null;
    onSubscriptionFormatConfirmation = null;
    _lastPhase = null;
    _lastCanDisconnect = null;
    _lastToolTip = null;
    _trayIcon = null;
    _toolTip = null;
    _lastProfileId = null;
    _menuOpen = false;
  }

  void _connectionChanged() {
    final view = _coordinator.state.value;
    final toolTip = _toolTipFor(view);
    if (_lastPhase == view.phase &&
        _lastCanDisconnect == view.canDisconnect &&
        _lastToolTip == toolTip &&
        _lastProfileId == view.runtime?.profile?.id) {
      return;
    }
    _lastPhase = view.phase;
    _lastCanDisconnect = view.canDisconnect;
    _lastToolTip = toolTip;
    _lastProfileId = view.runtime?.profile?.id;
    _requestRefresh();
  }

  /// Windows shows at most 127 UTF-16 units in a tray tooltip.
  static const _toolTipLimit = 120;

  /// Hovering the icon tells the state and the node without opening the
  /// window: "HYPER CLIENT · Connected · Main". Traffic is left out on
  /// purpose, so speed samples never touch the tray.
  String _toolTipFor(ConnectionView view) {
    final l = appLocalizationsNoContext();
    final connected = view.phase == ConnectionPhase.connected;
    final phase = view.failed && !connected
        ? ConnectionPhase.failed
        : view.phase;
    final health = _health.value;
    final unreachable =
        connected && health.unreachable && health.appliesTo(view.runtime);
    final blocked =
        _coordinator.killSwitchBlocking.value && !connected && !view.busy;
    final parts = <String>[
      'HYPER CLIENT',
      if (blocked)
        l.killSwitchBlocked
      else if (unreachable)
        l.connectionHealthLost
      else if (phase != ConnectionPhase.disconnected)
        switch (phase) {
          ConnectionPhase.disconnected => l.prototypeDisconnected,
          ConnectionPhase.preparing ||
          ConnectionPhase.connecting => l.prototypeConnecting,
          ConnectionPhase.connected => l.prototypeConnected,
          ConnectionPhase.disconnecting => l.prototypeDisconnecting,
          // The reason, as the failure notification gives it.
          ConnectionPhase.failed => connectionFailureMessage(
            l,
            issue: view.issue,
            error: view.error,
            permission: view.permission,
          ),
        },
      if (connected && view.runtime != null)
        if (_withoutFlags(view.runtime!.nodeName) case final name
            when name.isNotEmpty)
          name,
    ];
    final text = parts.join(' · ');
    if (text.length <= _toolTipLimit) return text;
    // Cut on a code point boundary, never inside a surrogate pair.
    final runes = <int>[];
    var length = 0;
    for (final rune in text.runes) {
      final width = rune > 0xFFFF ? 2 : 1;
      if (length + width > _toolTipLimit - 1) break;
      runes.add(rune);
      length += width;
    }
    return '${String.fromCharCodes(runes)}…';
  }

  /// Windows has no glyphs for regional-indicator flags and prints their
  /// letters ("NL"); the tooltip drops them like the node rows do.
  static String _withoutFlags(String name) => String.fromCharCodes(
    name.runes.where((rune) => rune < 0x1F1E6 || rune > 0x1F1FF),
  ).trim();

  void _requestRefresh() {
    if (!_initialized) return;
    unawaited(
      refreshTrayManager().catchError((Object error, StackTrace stackTrace) {
        ygLogger('Refresh tray failed: $error\n$stackTrace');
      }),
    );
  }

  Future<void> refreshTrayManager() {
    _refreshRequested = true;
    if (_menuOpen) return Future.value();
    return _refreshing ??= _refreshMenu().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<void> _refreshMenu() async {
    if (!AppPlatform.isDesktop) {
      return;
    }
    do {
      _refreshRequested = false;
      await _publishMenu();
    } while (_refreshRequested && _initialized && !_menuOpen);
  }

  Future<void> _publishMenu() async {
    if (!_initialized) return;
    final view = _coordinator.state.value;
    final running = view.canDisconnect || view.busy;
    await _setTrayIcon(running, _toolTipFor(view));
    if (!_initialized) return;

    final items = <TrayMenuEntry>[];
    if (running) {
      items.add(
        TrayMenuEntry(
          key: _TrayMenuKey.stopVpn.name,
          label: appLocalizationsNoContext().menuBarStopVpn,
        ),
      );
    } else {
      items.add(
        TrayMenuEntry(
          key: _TrayMenuKey.startVpn.name,
          label: appLocalizationsNoContext().menuBarStartVpn,
          disabled: view.busy,
        ),
      );
    }
    items.add(
      TrayMenuEntry(
        key: _TrayMenuKey.reconnect.name,
        label: appLocalizationsNoContext().menuBarReconnect,
        disabled: view.phase != ConnectionPhase.connected || view.busy,
      ),
    );
    items.add(TrayMenuEntry.separator());
    items.addAll(
      _data.selectionItems(
        appLocalizationsNoContext(),
        busy: view.busy || _changingConfiguration,
        runningProfile: view.runtime?.profile,
      ),
    );
    items.add(TrayMenuEntry.separator());
    items.addAll(
      _data.updateItems(appLocalizationsNoContext(), _pendingUpdates),
    );
    items.add(TrayMenuEntry.separator());
    items.add(
      TrayMenuEntry(
        key: _TrayMenuKey.showApp.name,
        label: appLocalizationsNoContext().menuBarShowApp,
      ),
    );
    items.add(
      TrayMenuEntry(
        key: _TrayMenuKey.quitApp.name,
        label: appLocalizationsNoContext().menuBarQuitApp,
      ),
    );
    if (_canQuitWithoutStoppingVpn) {
      items.add(
        TrayMenuEntry(
          key: _TrayMenuKey.quitAndStopVpn.name,
          label: appLocalizationsNoContext().menuBarQuitAndStopVpn,
        ),
      );
    }

    _platform.setMenu(items, (entry) => unawaited(onMenuAction(entry)));
  }

  Future<void> _setTrayIcon(bool running, String toolTip) async {
    var icon = "";
    if (AppPlatform.isWindows) {
      if (running) {
        icon = Assets.icon.trayRunningIco;
      } else {
        icon = Assets.icon.trayNotRunningIco;
      }
    } else {
      if (running) {
        icon = Assets.icon.trayRunningPng.path;
      } else {
        icon = Assets.icon.trayNotRunningPng.path;
      }
    }
    // Every catalog change republishes the menu; reloading the same icon
    // file each time is wasted work.
    if (_trayIcon != icon) {
      await _platform.setIcon(icon);
      _trayIcon = icon;
    }
    if (_toolTip != toolTip) {
      await _platform.setToolTip(toolTip);
      _toolTip = toolTip;
    }
  }

  Future<void> _showWindow() async {
    try {
      await _showMainWindow();
    } catch (error, stackTrace) {
      ygLogger('Show window from tray failed: $error\n$stackTrace');
    }
  }

  /// A menu that pops up seconds after the click, under wherever the cursor
  /// is by then, is worse than none.
  static const _staleMenuRequest = Duration(seconds: 2);

  Future<void> _openMenu() async {
    if (!_initialized || _menuOpen) return;
    _menuOpen = true;
    final requested = Stopwatch()..start();
    try {
      // Keep the active native menu and its callbacks alive until it closes.
      await _refreshing;
      if (!_initialized || requested.elapsed > _staleMenuRequest) return;
      await _platform.openMenu();
    } catch (error, stackTrace) {
      ygLogger('Open tray menu failed: $error\n$stackTrace');
    } finally {
      if (_menuOpen) {
        _menuOpen = false;
        if (_refreshRequested) _requestRefresh();
      }
    }
  }

  Future<void> onMenuAction(TrayMenuEntry menuItem) async {
    if (menuItem.key == null || menuItem.disabled) {
      return;
    }
    final key = _TrayMenuKey.fromString(menuItem.key!);
    try {
      if (menuItem.key!.startsWith('update')) {
        await _update(menuItem.key!);
        return;
      }
      if (key == null) {
        await _select(menuItem.key!);
        return;
      }
      switch (key) {
        case _TrayMenuKey.startVpn:
          await _connect();
          break;
        case _TrayMenuKey.reconnect:
          await _coordinator.apply(
            await _coordinator.configuration,
            connect: true,
          );
          break;
        case _TrayMenuKey.stopVpn:
          await _coordinator.disconnect();
          break;
        case _TrayMenuKey.showApp:
          await windowManager.show();
          await windowManager.focus();
          break;
        case _TrayMenuKey.quitApp:
          if (!_canQuitWithoutStoppingVpn) {
            await _coordinator.disconnect();
          }
          await ServicesBinding.instance.exitApplication(
            AppExitType.cancelable,
          );
          break;
        case _TrayMenuKey.quitAndStopVpn:
          await _coordinator.disconnect();
          await ServicesBinding.instance.exitApplication(
            AppExitType.cancelable,
          );
          break;
      }
    } catch (error) {
      if (failureCancelled(error) ||
          connectionFailureReason(error) == 'cancelled') {
        return;
      }
      if (key == _TrayMenuKey.startVpn || key == _TrayMenuKey.reconnect) {
        try {
          await _notify(
            connectionFailureMessage(appLocalizationsNoContext(), error: error),
          );
        } catch (notificationError) {
          ygLogger('Tray connection notification failed: $notificationError');
        }
        if (!connectionFailureNeedsWindow(error)) return;
      } else if (key == null) {
        await _notice(
          menuItem.key!.startsWith('update')
              ? appFailureMessage(appLocalizationsNoContext(), error)
              : connectionFailureMessage(
                  appLocalizationsNoContext(),
                  error: error,
                ),
        );
        return;
      }
      // Keep the coordinator's failure/permission state for the normal UI retry.
      await _showMainWindow();
    }
  }

  Future<void> _select(String key) async {
    final handler = onConfigurationChange;
    if (handler == null || _changingConfiguration) return;
    final l = appLocalizationsNoContext();
    final separator = key.indexOf(':');
    final kind = separator < 0 ? key : key.substring(0, separator);
    final value = separator < 0 ? '' : key.substring(separator + 1);
    final id = int.tryParse(value);
    Future<bool> trafficAvailable() async {
      final current = ConnectionConfiguration.fromJson(
        jsonDecode((await _db.connectionConfigDao.read()).configurationJson)
            as Map<String, dynamic>,
      ).connection;
      return !current.expert &&
          !await usesProviderConfiguration(
            _db,
            current,
            runtime: _coordinator.state.value.runtime,
          );
    }

    if ((kind == 'traffic' || kind == 'custom') && !await trafficAvailable()) {
      return;
    }
    Future<bool> serverAvailable(int id) async {
      final row = await _db.coreConfigDao.searchActiveServerRow(id);
      if (row == null) return false;
      final source = row.subId > 0
          ? await _db.subscriptionDao.searchRow(row.subId)
          : null;
      return ServerCatalog(servers: [row], sources: [?source]).selectable(row);
    }

    Map<String, dynamic> values;
    String label;
    Future<void> validate() async {
      final exists = switch (kind) {
        'server' => await serverAvailable(id!),
        'raw' =>
          (await _db.coreConfigDao.searchRow(id!))?.type ==
              CoreConfigType.raw.name,
        'source' =>
          id == 0
              ? (await _db.coreConfigDao.allOutboundRowsWithDataBySubId(0))
                    .isNotEmpty
              : (await _db.subscriptionDao.searchRow(id!))?.mode ==
                    SubscriptionMode.appManaged.name,
        'custom' =>
          await trafficAvailable() &&
              await _db.routingProfileDao.searchRow(id!) != null,
        'traffic' => await trafficAvailable(),
        _ => true,
      };
      if (!exists) throw const AppFailure(FailureCategory.conflict, 'notFound');
    }

    switch (kind) {
      case 'automatic':
        values = {
          'expert': false,
          'selection': const ServerSelection.automatic().toJson(),
        };
        label = l.prototypeAutomaticSelection;
      case 'server':
      case 'source':
        if (id == null) return;
        await validate();
        values = {
          'expert': false,
          'selection':
              (kind == 'server'
                      ? ServerSelection.server(id)
                      : ServerSelection.source(id))
                  .toJson(),
        };
        label = kind == 'server'
            ? (await _db.coreConfigDao.searchRow(id))!.name
            : id == 0
            ? l.prototypeManualAdditions
            : (await _db.subscriptionDao.searchRow(id))!.name;
      case 'region':
        values = {
          'expert': false,
          'selection': ServerSelection.region(value).toJson(),
        };
        label = value.isEmpty ? '—' : l.countryRegionName(value);
      case 'raw':
        if (id == null) return;
        await validate();
        values = {'expert': true, 'rawId': id};
        label = (await _db.coreConfigDao.searchRow(id))!.name;
      case 'custom':
        if (id == null) return;
        await validate();
        values = {
          'expert': false,
          'trafficMode': TrafficMode.custom.name,
          'customId': id,
        };
        label = (await _db.routingProfileDao.searchRow(id))!.name;
      case 'traffic':
        if (value != TrafficMode.smart.name &&
            value != TrafficMode.selective.name &&
            value != TrafficMode.allVpn.name) {
          return;
        }
        values = {'expert': false, 'trafficMode': value};
        label = value == TrafficMode.smart.name
            ? l.prototypeSmartRoutingRecommended
            : value == TrafficMode.selective.name
            ? l.trafficSelective
            : l.prototypeAllViaVpn;
      default:
        return;
    }
    _changingConfiguration = true;
    _requestRefresh();
    try {
      await handler(values, label, validate);
    } finally {
      _changingConfiguration = false;
      _requestRefresh();
    }
  }

  Future<void> _update(String key) async {
    if (!_pendingUpdates.add(key)) return;
    _requestRefresh();
    final l = appLocalizationsNoContext();
    try {
      if (key == 'updateSubscriptions') {
        await _notice(
          subscriptionRefreshMessage(
            l,
            await SubscriptionService().refreshAll(
              confirmOrdinary: onSubscriptionFormatConfirmation,
            ),
          ),
        );
      } else if (key.startsWith('updateSubscription:')) {
        final id = int.tryParse(key.substring('updateSubscription:'.length));
        final source = id == null
            ? null
            : await _db.subscriptionDao.searchRow(id);
        if (source == null) {
          throw const AppFailure(FailureCategory.conflict, 'notFound');
        }
        await _notice(
          subscriptionRefreshMessage(l, {
            source: await SubscriptionService().refreshSubscriptionResult(
              source,
              confirmOrdinary: onSubscriptionFormatConfirmation,
            ),
          }),
        );
      } else if (key == 'updateGeodata') {
        final errors = await GeoDataService().updateAll();
        await _notice(
          errors.isEmpty
              ? l.prototypeAllGeodataUpdated
              : [
                  for (final entry in errors.entries)
                    '${entry.key == -1 ? l.prototypeDefaultRoutingData : _data.geodata.where((row) => row.id == entry.key).firstOrNull?.name ?? entry.key}: ${appFailureMessage(l, entry.value)}',
                ].join('\n'),
        );
      } else if (key == 'updateDefaultGeodata') {
        await GeoDataService().updateDefaults();
        await _notice(l.prototypeGeodataUpdated);
      } else if (key.startsWith('updateGeodata:')) {
        final id = int.tryParse(key.substring('updateGeodata:'.length));
        final file = id == null ? null : await _db.geoDataDao.searchRow(id);
        if (file == null || file.id <= 0) {
          throw const AppFailure(FailureCategory.conflict, 'notFound');
        }
        await GeoDataService().updateCustom(file);
        await _notice('${file.name}.dat · ${l.prototypeGeodataUpdated}');
      }
    } finally {
      _pendingUpdates.remove(key);
      _requestRefresh();
    }
  }

  Future<void> _notice(String message) async {
    if (message.isEmpty) return;
    try {
      await _notify(message);
    } catch (error, stackTrace) {
      ygLogger('Tray notification failed: $error\n$stackTrace');
    }
  }
}

enum _TrayMenuKey {
  reconnect("reconnect"),
  startVpn("startVpn"),
  stopVpn("stopVpn"),
  showApp("showApp"),
  quitApp("quitApp"),
  quitAndStopVpn("quitAndStopVpn");

  const _TrayMenuKey(this.name);

  final String name;

  static _TrayMenuKey? fromString(String name) =>
      _TrayMenuKey.values.firstWhereOrNull((value) => value.name == name);
}
