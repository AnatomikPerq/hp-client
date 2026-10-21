import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/provider_mode.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/connect/routing/profiles/catalog.dart';
import 'package:onexray/service/connect/routing/profiles/profile.dart';
import 'package:onexray/service/connect/routing/profiles/ru_blocked.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/xray/runtime_inbounds.dart';
import 'package:onexray/service/shared/xray/runtime_outbounds.dart';
import 'package:onexray/service/shared/xray/validation.dart';
import 'package:path/path.dart' as p;

/// Where the enabled profiles act for the stored connection.
enum TrafficProfilesScope { applied, raw, advanced, provider }

class TrafficProfilesDraft {
  final ConnectionConfiguration configuration;
  final RuBlockedStatus? ruBlocked;
  final TrafficProfilesScope scope;

  const TrafficProfilesDraft({
    required this.configuration,
    required this.ruBlocked,
    required this.scope,
  });
}

/// Fork: saves the profiles chosen on top of the routing mode. One save is
/// one reconnect, however many profiles changed.
class TrafficProfilesEditorService {
  final AppDatabase db;
  final ConnectionCoordinator coordinator;
  final RuBlockedList ruBlocked;
  final Future<String> Function(String)? testXray;

  TrafficProfilesEditorService({
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
    RuBlockedList? ruBlocked,
    this.testXray,
  }) : db = database ?? AppDatabase(),
       coordinator = coordinator ?? ConnectionCoordinator.instance,
       ruBlocked = ruBlocked ?? RuBlockedList.instance;

  Future<TrafficProfilesDraft> load() async {
    await coordinator.initialize();
    final configuration = await coordinator.configuration;
    RuBlockedStatus? status;
    try {
      status = await ruBlocked.status();
    } catch (_) {
      // The page still works without the list details.
    }
    return TrafficProfilesDraft(
      configuration: configuration,
      ruBlocked: status,
      scope: await _scope(configuration.connection),
    );
  }

  Future<TrafficProfilesScope> _scope(ConnectionSettings connection) async {
    if (connection.expert) return TrafficProfilesScope.raw;
    if (await usesProviderConfiguration(
      db,
      connection,
      runtime: coordinator.state.value.runtime,
    )) {
      return TrafficProfilesScope.provider;
    }
    if (connection.trafficMode == TrafficMode.custom &&
        connection.customId != null &&
        (await db.routingProfileDao.searchRow(connection.customId!))
                ?.advanced ==
            true) {
      return TrafficProfilesScope.advanced;
    }
    return TrafficProfilesScope.applied;
  }

  Future<RuBlockedStatus?> status() => ruBlocked.status();

  Future<RuBlockedUpdate> updateRuBlocked() => ruBlocked.update();

  /// Returns null when the user declined the reconnect, otherwise whether a
  /// newly enabled ru-blocked list could not be refreshed (the bundled or
  /// earlier copy is used then).
  Future<bool?> save({
    required ConnectionConfiguration original,
    required TrafficProfileSettings profiles,
    required Future<bool> Function() confirmReconnect,
  }) async {
    profiles.validate();
    await coordinator.initialize();
    await coordinator.refresh();
    if ((await coordinator.configuration).encode() != original.encode()) {
      throw const ConnectionHostException('configurationChanged');
    }
    final connection = original.connection;
    final affectsRuntime =
        await _scope(connection) == TrafficProfilesScope.applied &&
        !sameRuntime(connection, profiles);
    var allowReconnect = false;
    if (affectsRuntime &&
        coordinator.state.value.phase == ConnectionPhase.connected) {
      allowReconnect = await confirmReconnect();
      if (!allowReconnect) return null;
    }
    var updateFailed = false;
    final enablesRuBlocked =
        TrafficProfiles.usesRuBlocked(profiles) &&
        !TrafficProfiles.usesRuBlocked(connection.profiles);
    if (enablesRuBlocked) {
      // Turning the profile on refreshes the list; a failed request keeps
      // the copy that is there.
      try {
        await ruBlocked.update();
      } catch (_) {
        updateFailed = true;
      }
      await ruBlocked.ensureInstalled();
    }
    final customChanged = !const DeepCollectionEquality().equals(
      [for (final profile in profiles.custom) profile.toJson()],
      [for (final profile in connection.profiles.custom) profile.toJson()],
    );
    await coordinator.apply(
      ConnectionConfiguration(
        connection: ConnectionSettings.fromJson({
          ...connection.toJson(),
          'profiles': profiles.toJson(),
        }),
        policy: original.policy,
      ),
      affectsRuntime: affectsRuntime,
      allowReconnect: allowReconnect,
      expectedConfiguration: original.encode(),
      validateAssets: customChanged ? () => _validateCustom(profiles) : null,
    );
    return updateFailed;
  }

  /// Whether [next] compiles to the rules [original] already runs with.
  static bool sameRuntime(
    ConnectionSettings original,
    TrafficProfileSettings next,
  ) {
    final allVpn = original.trafficMode == TrafficMode.allVpn;
    final selective = original.trafficMode == TrafficMode.selective;
    List<Map<String, dynamic>> rules(TrafficProfileSettings value) => [
      for (final rule in TrafficProfiles.rules(
        value,
        context: const TrafficProfileContext(ruBlocked: true, processes: true),
        actions: {
          if (!allVpn) TrafficProfileAction.proxy,
          if (!selective) TrafficProfileAction.direct,
        },
        lanGuard: !selective,
      ))
        rule.toJson(),
    ];
    return const DeepCollectionEquality().equals(
      rules(original.profiles),
      rules(next),
    );
  }

  /// Xray decides whether each custom value (a category, a CIDR, a path)
  /// is valid; every custom profile is checked as if it were enabled.
  Future<void> _validateCustom(TrafficProfileSettings profiles) async {
    if (profiles.custom.isEmpty) return;
    final all = TrafficProfileSettings(
      enabled: [for (final profile in profiles.custom) profile.id],
      custom: profiles.custom,
    );
    final selection = const RoutingSelectionSettings().compile(
      selector: ['app-entry-0'],
    );
    final error = await (testXray ?? AppHostApi().testXray)(
      XrayValidation.normal(
        XrayJson(
          inbounds: [createSocksInbound('1080')],
          routing: XrayRouting(
            domainStrategy: 'IPIfNonMatch',
            balancers: [selection.balancer],
            rules: TrafficProfiles.rules(
              all,
              context: TrafficProfileContext(
                ruBlocked: await ruBlocked.installed(),
                processes: true,
              ),
              lanGuard: false,
            ),
          ),
          observatory: selection.observatory,
          outbounds: [
            createFreedomOutbound(tag: 'app-entry-0').toJson(),
            createFreedomOutbound(tag: 'direct').toJson(),
          ],
        ),
      ),
    );
    if (error.isNotEmpty) {
      throw AppFailure(
        FailureCategory.configuration,
        'xrayValidation',
        cause: error,
      );
    }
  }

  /// A program's file name, which survives the versioned folders most
  /// installers use. Linux binaries have no extension to filter by.
  static Future<String?> pickProgram() async {
    final file = await FilePicker.pickFile(
      type: Platform.isWindows ? FileType.custom : FileType.any,
      allowedExtensions: Platform.isWindows ? const ['exe'] : null,
    );
    final path = file?.path;
    return path == null ? null : p.basename(path);
  }
}
