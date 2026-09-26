import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/model/tun_json.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/connect/platform_requirements.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/minewire/runtime.dart';
import 'package:path/path.dart' as p;

Future<List<int>> allocateRuntimePorts(
  List<dynamic> rawInbounds, {
  Future<List<int>> Function(int count)? getFreePorts,
  Set<int> reserved = const {},
}) async {
  final allocate = getFreePorts ?? AppHostApi().getFreePorts;
  for (var attempt = 0; attempt < 5; attempt++) {
    final candidates = await allocate(2);
    if (candidates.length == 2 &&
        candidates.toSet().length == 2 &&
        candidates.every((port) => port > 0 && port <= 65535) &&
        !candidates.any(reserved.contains) &&
        !rawInbounds.any(
          (entry) =>
              entry is Map &&
              candidates.any(
                (port) => ConnectionCompiler.portIncludes(entry['port'], port),
              ),
        )) {
      return candidates;
    }
  }
  throw const FormatException('Runtime ports are unavailable');
}

/// The user-facing proxy port is fixed, so a busy one is reported up front
/// instead of as a bind error from inside the Core.
Future<void> ensureSystemProxyPortFree(int port) async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
  } on SocketException catch (error) {
    throw ConnectionHostException('systemProxyPortBusy', cause: error);
  }
}

/// Resolves and compiles without publishing settings or starting a VPN.
class ConnectionPreparation {
  final AppDatabase db;
  final ConnectionResolver resolver;

  ConnectionPreparation({AppDatabase? db, ConnectionResolver? resolver})
    : db = db ?? AppDatabase(),
      resolver =
          resolver ??
          ConnectionResolver(
            rows: () {
              final database = db ?? AppDatabase();
              return (database.select(
                database.coreConfig,
              )..where((row) => row.type.equals('outbound'))).watch();
            },
          );

  Future<ConnectionRuntime> prepare(
    ConnectionConfiguration input, {
    Future<void>? cancelled,
    String? rawDraft,
    RoutingConfiguration? customDraft,
    Map<int, ResolvedServer> serverDrafts = const {},
    void Function(Set<int>)? onResolved,
  }) async {
    var configuration = input;
    var settings = input.connection;
    final policy = input.policy;
    final platform = connectionPlatform;
    final systemProxy = policy.usesSystemProxy(platform);
    // Proxy mode has no tunnel: no adapter settings, no interface binding.
    if (!systemProxy) {
      await ConnectionPlatformRequirements(platform: platform)
          .ensureOutboundInterface(policy.xrayOutboundInterfaceName);
    }
    final tun = systemProxy ? null : policy.toTun(platform);
    String? raw = rawDraft;
    RoutingConfiguration? custom = customDraft;
    if (settings.expert && raw == null) {
      final row = settings.rawId == null
          ? null
          : await db.coreConfigDao.searchRow(settings.rawId!);
      if (row == null || row.type != 'raw') {
        throw const FormatException('Raw configuration is unavailable');
      }
      if (row.data == null) {
        throw const FormatException('Raw configuration is empty');
      }
      raw = utf8.decode(base64Decode(row.data!));
    } else if (!settings.expert &&
        settings.trafficMode == TrafficMode.custom &&
        custom == null) {
      final row = settings.customId == null
          ? null
          : await db.routingProfileDao.searchRow(settings.customId!);
      if (row == null) {
        throw const FormatException('Custom route is unavailable');
      }
      custom = CustomRoutingService.readConfiguration(row);
    }
    String? notice;
    List<ResolvedServer> entries;
    try {
      entries = await resolver.resolve(
        settings,
        custom: custom,
        cancelled: cancelled,
      );
    } on ConnectionResolutionException catch (error) {
      if (settings.selection.kind == SelectionKind.automatic ||
          !{
            ConnectionResolutionFailure.selectionUnavailable,
            ConnectionResolutionFailure.insufficientHealthyServers,
          }.contains(error.reason)) {
        rethrow;
      }
      settings = ConnectionSettings.fromJson({
        ...settings.toJson(),
        'selection': const ServerSelection.automatic().toJson(),
      });
      entries = await resolver.resolve(
        settings,
        custom: custom,
        cancelled: cancelled,
      );
      configuration = ConnectionConfiguration(
        connection: settings,
        policy: policy,
      );
      notice = 'selectionReset';
    }
    entries = [for (final entry in entries) serverDrafts[entry.id] ?? entry];
    onResolved?.call({
      for (final entry in entries) entry.id,
      if (settings.finalExitId != null) settings.finalExitId!,
    });
    ResolvedServer? finalExit;
    if (settings.finalExitId != null) {
      final row = await db.coreConfigDao.searchRow(settings.finalExitId!);
      if (row == null) throw const FormatException('Final exit is unavailable');
      finalExit = serverDrafts[row.id] ?? ResolvedServer.fromRow(row);
    }
    var regions = const RegionCatalog.empty();
    if (!settings.expert &&
        settings.trafficMode == TrafficMode.smart &&
        settings.smart.directRegions.isNotEmpty) {
      Future<Map<String, dynamic>> readIndex(String name) async => jsonDecode(
        await File(p.join(VpnConstants.datDir, '$name.json')).readAsString(),
      ) as Map<String, dynamic>;
      regions = RegionCatalog.fromJson(
        jsonDecode(await rootBundle.loadString(RegionCatalog.assetPath))
            as Map<String, dynamic>,
        geositeCodes: RegionCatalog.codesFromIndex(await readIndex('geosite')),
        geoipCodes: RegionCatalog.codesFromIndex(await readIndex('geoip')),
      );
    }
    final rawConfig = raw == null ? null : ConnectionCompiler.parseRawJson(raw);
    final userInbounds =
        rawConfig?['inbounds'] ?? custom?.toJson()['inbounds'] ?? [];
    if (userInbounds is! List ||
        userInbounds.any((entry) => entry is! Map<String, dynamic>)) {
      throw const FormatException('inbounds must be an object array');
    }
    final proxyPort = systemProxy ? policy.systemProxyPort : null;
    if (proxyPort != null) await ensureSystemProxyPortFree(proxyPort);
    final allocated = await allocateRuntimePorts(
      userInbounds.cast<Map<String, dynamic>>(),
      reserved: {?proxyPort},
    );
    final ports = [proxyPort ?? allocated[0], allocated[1]];
    // minewire engines run in the App and are reached through loopback SOCKS;
    // the servers handed to the compiler point at them.
    final minewire = await MinewireRuntime.instance.materialize([
      ...entries,
      ?finalExit,
    ]);
    try {
      return await _finish(
        configuration: configuration,
        settings: settings,
        platform: platform,
        policy: policy,
        tun: tun,
        ports: ports,
        systemProxy: systemProxy,
        entries: entries,
        finalExit: finalExit,
        minewire: minewire,
        rawConfig: rawConfig,
        custom: custom,
        regions: regions,
        serverDrafts: serverDrafts,
        notice: notice,
      );
    } catch (_) {
      await MinewireRuntime.instance.stopPorts(minewire.ports.values);
      rethrow;
    }
  }

  Future<ConnectionRuntime> _finish({
    required ConnectionConfiguration configuration,
    required ConnectionSettings settings,
    required ConnectionPlatform platform,
    required PlatformPolicy policy,
    required TunJson? tun,
    required List<int> ports,
    required bool systemProxy,
    required List<ResolvedServer> entries,
    required ResolvedServer? finalExit,
    required MinewireMaterialized minewire,
    required Map<String, dynamic>? rawConfig,
    required RoutingConfiguration? custom,
    required RegionCatalog regions,
    required Map<int, ResolvedServer> serverDrafts,
    required String? notice,
  }) async {
    final runtimeServers = minewire.servers;
    var compiled = ConnectionCompiler.compile(
      settings: settings,
      entries: runtimeServers.take(entries.length).toList(),
      finalExit: finalExit == null ? null : runtimeServers.last,
      raw: rawConfig,
      custom: custom,
      regions: regions,
      options: RuntimeOptions(
        platform: platform,
        sessionDirectory: VpnConstants.runDir,
        socksPort: ports[0],
        metricsPort: ports[1],
        ipv6: policy.ipv6Enabled,
        tunDnsIpv4Address: policy.dnsIpv4Address,
        tunDnsIpv6Address: policy.dnsIpv6Address,
        interfaceName: policy.xrayOutboundInterfaceName,
        systemProxy: systemProxy,
        logEnabled: policy.logEnabled,
        logLevel: policy.logLevel,
        dnsLog: policy.recordDns,
        maskAddress: policy.maskAddress,
      ),
    );
    if (minewire.endpoints.isNotEmpty) {
      final config = compiled.config;
      MinewireRuntime.applyBypass(config, minewire.bypassRules);
      compiled = CompiledConnection(
        xrayJson: jsonEncode(config),
        entries: compiled.entries,
        finalExit: compiled.finalExit,
        nodeTags: compiled.nodeTags,
      );
    }
    await GeoDataService().requireDependencies(
      geoDataReferences(jsonDecode(compiled.xrayJson) as Map<String, dynamic>),
    );
    for (final server in [...entries, ?finalExit]) {
      final row = await db.coreConfigDao.searchRow(server.id);
      if (row == null ||
          row.type != 'outbound' ||
          (!serverDrafts.containsKey(row.id) &&
              ResolvedServer.fromRow(row).outboundJson !=
                  server.outboundJson)) {
        throw const FormatException(
          'A selected server changed during preparation',
        );
      }
    }
    // Without TUN settings a desktop request means system proxy mode, and the
    // SOCKS port is the user-facing inbound the system proxy points at.
    final request = StartVpnRequest(
      tun,
      systemProxy ||
              platform == ConnectionPlatform.windows ||
              platform == ConnectionPlatform.ios
          ? '${ports[0]}'
          : null,
      '${ports[1]}',
      jsonEncode(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest(compiled.xrayJson).toJson(),
        ).toJson(),
      ),
    );
    return ConnectionRuntime.create(
      configuration: configuration,
      compiled: compiled,
      platform: platform,
      request: request,
      notice: notice,
      minewirePorts: minewire.ports,
    );
  }
}
