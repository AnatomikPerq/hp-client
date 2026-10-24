import 'dart:convert';
import 'dart:io';

import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/amneziawg/conf.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/dialing.dart';
import 'package:onexray/service/connect/runtime_network_policy.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/dns.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/connect/routing/profiles/catalog.dart';
import 'package:onexray/service/connect/routing/profiles/profile.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/shared/ping/live_probe.dart';
import 'package:onexray/service/shared/xray/runtime_inbounds.dart';
import 'package:onexray/service/shared/xray/runtime_outbounds.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';
import 'package:onexray/service/shared/xray/fragment.dart';
import 'package:onexray/service/shared/xray/remnawave.dart';
import 'package:onexray/service/shared/xray/vpn_config.dart';
import 'package:onexray/service/shared/xray/server_dialing.dart';

/// A complete provider graph selected as one subscription asset.
class ResolvedProfile {
  final int id;
  final int sourceId;
  final String name;
  final Map<String, dynamic> _config;

  ResolvedProfile({
    required this.id,
    required this.sourceId,
    required this.name,
    required Map<String, dynamic> config,
  }) : _config = JsonTool.copyMap(config) {
    if (id <= 0 || sourceId <= 0 || name.trim().isEmpty) {
      throw const FormatException('Invalid provider profile');
    }
  }

  factory ResolvedProfile.fromRow(CoreConfigData row) {
    if (row.type != CoreConfigType.Remnawave.name || row.data == null) {
      throw const FormatException('Provider configuration is unavailable');
    }
    return ResolvedProfile(
      id: row.id,
      sourceId: row.subId,
      name: row.name,
      config: ConnectionCompiler.parseRawJson(
        utf8.decode(base64Decode(row.data!)),
      ),
    );
  }

  String get type => CoreConfigType.Remnawave.name;
  Map<String, dynamic> get config => JsonTool.copyMap(_config);
}

class ResolvedServer {
  final int id;
  final int sourceId;
  final String name;
  final Map<String, dynamic> _outbound;
  late final String outboundJson = jsonEncode(_outbound);

  ResolvedServer({
    required this.id,
    required this.sourceId,
    required Map<String, dynamic> outbound,
  }) : name = outboundDisplayName(outbound),
       _outbound = JsonTool.copyMap(outbound);

  factory ResolvedServer.fromRow(CoreConfigData row) {
    if (row.type != 'outbound') {
      throw const FormatException('A server must be an outbound');
    }
    return ResolvedServer(
      id: row.id,
      sourceId: row.subId,
      outbound: readOutboundFromDbData(row),
    );
  }

  Map<String, dynamic> get outbound => JsonTool.copyMap(_outbound);
  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'name': name,
    'outbound': outbound,
  };
}

class RuntimeOptions {
  final ConnectionPlatform platform;
  final WindowsMode windowsMode;
  final String sessionDirectory;
  final int metricsPort;
  final int socksPort;
  final bool lanProxyEnabled;
  final int lanProxyPort;
  final String lanProxyUser;
  final String lanProxyPassword;
  final bool ipv6;
  final ServerDialingSettings dialing;
  final String tunDnsIpv4Address;
  final String tunDnsIpv6Address;
  final String interfaceName;
  final bool logEnabled;
  final bool logFilesSupported;
  final String logLevel;
  final bool dnsLog;
  final String maskAddress;

  /// Desktop system proxy mode: `tunIn` is a loopback SOCKS/HTTP inbound on
  /// [socksPort] and outbounds follow normal OS routing.
  final bool systemProxy;

  RuntimeOptions({
    required this.platform,
    WindowsMode? windowsMode,
    required this.sessionDirectory,
    required this.metricsPort,
    required this.socksPort,
    this.lanProxyEnabled = false,
    this.lanProxyPort = defaultLanProxyPort,
    this.lanProxyUser = '',
    this.lanProxyPassword = '',
    this.ipv6 = true,
    this.dialing = const ServerDialingSettings(),
    this.tunDnsIpv4Address = '8.8.8.8',
    this.tunDnsIpv6Address = '2001:4860:4860::8888',
    this.interfaceName = '',
    this.logEnabled = false,
    this.logFilesSupported = true,
    this.logLevel = 'warning',
    this.dnsLog = true,
    this.maskAddress = '',
    this.systemProxy = false,
  }) : windowsMode = windowsMode ?? windowsBuildMode {
    if (metricsPort == socksPort) {
      throw const FormatException('Runtime ports are invalid');
    }
    if (systemProxy && !desktop) {
      throw const FormatException('System proxy mode is desktop-only');
    }
    if (lanProxyEnabled && (lanProxyUser.isEmpty || lanProxyPassword.isEmpty)) {
      throw const FormatException(
        'LAN proxy sharing needs a login and password',
      );
    }
    if (lanProxyEnabled && (lanProxyPort < 1024 || lanProxyPort > 65535)) {
      throw const FormatException('LAN proxy port must be within 1024–65535');
    }
    if (lanProxyEnabled &&
        (lanProxyPort == metricsPort || lanProxyPort == socksPort)) {
      throw const FormatException(
        'LAN proxy port conflicts with a runtime port',
      );
    }
    if (requiresInterface && interfaceName.isEmpty) {
      throw const FormatException('Network interface is required');
    }
  }

  bool get desktop =>
      platform == ConnectionPlatform.windows ||
      platform == ConnectionPlatform.linux;

  /// A desktop TUN binds every outbound to the physical interface so the
  /// Core's own traffic cannot loop back into the tunnel. Without a tunnel
  /// there is nothing to escape, and the OS routing (including another VPN
  /// the user runs) stays in charge.
  bool get requiresInterface => desktop && !systemProxy;

  bool get usesWindowsSystemVpn =>
      platform == ConnectionPlatform.windows && windowsMode == WindowsMode.msix;

  /// `tunIn` is a private or user-facing SOCKS inbound instead of a TUN.
  bool get usesLoopbackInbound => usesWindowsSystemVpn || systemProxy;
}

class CompiledConnection {
  final String xrayJson;
  final List<ResolvedServer> entries;
  final ResolvedServer? finalExit;
  final Map<String, int> nodeTags;
  final ResolvedProfile? profile;

  CompiledConnection({
    required this.xrayJson,
    required Iterable<ResolvedServer> entries,
    required this.finalExit,
    required Map<String, int> nodeTags,
    this.profile,
  }) : entries = List.unmodifiable(entries),
       nodeTags = Map.unmodifiable(nodeTags);

  Map<String, dynamic> get config =>
      jsonDecode(xrayJson) as Map<String, dynamic>;
}

/// Pure value compilation. Never opens a database, edits an asset, allocates a
/// port or starts Xray. Runtime files and commits belong to the coordinator.
class ConnectionCompiler {
  static Map<String, dynamic> parseRawJson(String text) {
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Raw configuration must be an object');
    }
    return value;
  }

  /// Compare editor drafts through the same overrides as a real Raw runtime.
  /// The caller supplies identical options for both drafts; no files are written.
  static Map<String, dynamic> rawSemanticJson(
    Map<String, dynamic> source,
    RuntimeOptions options,
  ) {
    final value = JsonTool.copyMap(source)..remove('name');
    return _fullRuntimeMap(VpnConfigAdapter.adapt(value), options);
  }

  static const dnsProxy = RoutingDns.proxyTag;
  static const dnsDirect = RoutingDns.directTag;
  static const dnsOutbound = 'dnsOut';

  /// The rule that sends [LivePingProbe]'s hosts through the VPN.
  static const liveProbeRuleTag = 'app-live-probe';

  /// Checks only collisions with the enabled App-managed LAN listener.
  static void validateLanProxyInbounds(List<dynamic> inbounds, int port) {
    for (final inbound in inbounds.whereType<Map>()) {
      final tag = inbound['tag'];
      if (tag == lanProxyInboundTag) {
        throw const FormatException('The LAN proxy inbound tag is App-managed');
      }
      if (tag != 'tunIn' && portIncludes(inbound['port'], port)) {
        throw const FormatException(
          'LAN proxy port conflicts with a configuration inbound',
        );
      }
    }
  }

  /// The editor and runtime share these exact built-in rules and their order.
  static List<XrayRoutingRule> smartRules(
    SmartRoutingSettings smart,
    RegionCatalog regions,
  ) {
    final domains = <String>{
      if (smart.directPrivate) 'geosite:PRIVATE',
      if (smart.directApple) 'geosite:APPLE',
      if (smart.directWindows) ...['geosite:MICROSOFT', 'geosite:BING'],
      ...regions.domainRules(smart.directRegions),
    }.toList();
    final ips = <String>{
      if (smart.directPrivate) 'geoip:PRIVATE',
      ...regions.ipRules(smart.directRegions),
    }.toList();
    return [
      if (smart.blockAds)
        XrayRoutingRule(
          ruleTag: 'app-smart-ads',
          domain: ['geosite:CATEGORY-ADS-ALL'],
          outboundTag: 'block',
        ),
      if (smart.directWindows)
        XrayRoutingRule(
          ruleTag: 'app-smart-github',
          domain: ['geosite:GITHUB'],
          balancerTag: 'proxy',
        ),
      if (domains.isNotEmpty)
        XrayRoutingRule(
          ruleTag: 'app-smart-direct-domain',
          domain: domains,
          outboundTag: 'direct',
        ),
      if (ips.isNotEmpty)
        XrayRoutingRule(
          ruleTag: 'app-smart-direct-ip',
          ip: ips,
          outboundTag: 'direct',
        ),
    ];
  }

  static CompiledConnection compile({
    required ConnectionSettings settings,
    required List<ResolvedServer> entries,
    ResolvedServer? finalExit,
    Map<String, dynamic>? raw,
    ResolvedProfile? profile,
    RoutingConfiguration? custom,
    required RegionCatalog regions,
    required RuntimeOptions options,
    TrafficProfileContext profileContext = const TrafficProfileContext(),
  }) {
    final nodeTags = <String, int>{};
    late final Map<String, dynamic> config;
    if (profile != null) {
      if (settings.expert ||
          settings.selection.kind != SelectionKind.server ||
          settings.selection.id != profile.id ||
          entries.isNotEmpty ||
          finalExit != null ||
          raw != null ||
          custom != null) {
        throw const FormatException(
          'Provider configuration requires one fixed profile',
        );
      }
      final adapted = RemnawaveAdapter.adapt(profile.config);
      config = _fullRuntimeMap(adapted, options);
    } else if (settings.expert) {
      if (raw == null || entries.isNotEmpty || finalExit != null) {
        throw const FormatException(
          'Raw configuration is required without normal nodes',
        );
      }
      config = _fullRuntimeMap(VpnConfigAdapter.adapt(raw), options);
    } else {
      final required = settings.requiredEntries(
        customEntryCount: custom?.entryCount,
      );
      if (entries.length != required ||
          entries.map((entry) => entry.id).toSet().length != required) {
        throw const FormatException('Not enough distinct entry nodes');
      }
      if (settings.finalExitId != finalExit?.id ||
          entries.any((entry) => entry.id == finalExit?.id)) {
        throw const FormatException('Invalid final exit selection');
      }
      if (settings.selection.kind == SelectionKind.server &&
          entries.single.id != settings.selection.id) {
        throw const FormatException('Fixed server does not match');
      }
      if (settings.trafficMode == TrafficMode.custom && custom == null) {
        throw const FormatException('Custom route is required');
      }
      if (settings.trafficMode == TrafficMode.custom &&
          custom is AdvancedRoutingProfile) {
        final outbounds = <Map<String, dynamic>>[];
        for (final (index, entry) in entries.indexed) {
          final tag = 'app-entry-$index';
          outbounds.add(_node(entry, tag));
          nodeTags[tag] = entry.id;
        }
        _applyOutboundPolicy(outbounds, options, raw: false);
        final template = custom.fillSlots(
          outbounds,
          includeLanProxy: options.lanProxyEnabled,
        );
        final inbounds = _objects(template, 'inbounds');
        for (var index = 0; index < inbounds.length; index++) {
          if (inbounds[index]['tag'] == 'tunIn') {
            inbounds[index] = {
              ..._runtimeInbound(
                options,
                fakeDns: FakeDns.usedByRaw(template),
              ).toJson(),
              ...inbounds[index],
            };
          }
        }
        template['inbounds'] = inbounds;
        return CompiledConnection(
          xrayJson: jsonEncode(
            _rawRuntimeMap(
              template,
              options,
              includeLanProxy: options.lanProxyEnabled,
            ),
          ),
          entries: entries,
          finalExit: null,
          nodeTags: nodeTags,
        );
      }
      final ordinary = custom is RoutingProfileState ? custom : null;
      final allVpn = settings.trafficMode == TrafficMode.allVpn;
      final selective = settings.trafficMode == TrafficMode.selective;
      // Fork: enabled profiles go above the mode's own rules. Everything
      // already reaches the VPN in All VPN and leaves direct in Selective,
      // so those modes only take the other direction.
      final profileRules = TrafficProfiles.rules(
        settings.profiles,
        context: profileContext.withProcesses(options.desktop),
        actions: {
          if (!allVpn) TrafficProfileAction.proxy,
          if (!selective) TrafficProfileAction.direct,
        },
        lanGuard: !selective,
      );
      final rules = <XrayRoutingRule>[];
      switch (settings.trafficMode) {
        case TrafficMode.smart:
          final smart = smartRules(settings.smart, regions);
          bool blocks(XrayRoutingRule rule) => rule.outboundTag == 'block';
          rules
            ..addAll(smart.where(blocks))
            ..addAll(profileRules)
            ..addAll(smart.where((rule) => !blocks(rule)));
        case TrafficMode.selective:
          rules
            ..addAll([
              if (settings.smart.blockAds)
                XrayRoutingRule(
                  ruleTag: 'app-smart-ads',
                  domain: ['geosite:CATEGORY-ADS-ALL'],
                  outboundTag: 'block',
                ),
            ])
            ..addAll(
              TrafficProfiles.privateDirect(
                'app-selective-private',
                profileContext,
              ),
            )
            ..addAll(profileRules);
        case TrafficMode.custom:
          rules.addAll(profileRules);
          for (final (index, rule) in ordinary!.rules.indexed) {
            rules.add(rule.xrayJson..ruleTag = 'app-custom-$index');
          }
        case TrafficMode.allVpn:
          rules.addAll(profileRules);
      }
      // All VPN resolves through the proxy alone until a profile sends
      // something direct.
      final directDns = switch (settings.trafficMode) {
        TrafficMode.smart || TrafficMode.selective => settings.smart.directDns,
        TrafficMode.custom => true,
        TrafficMode.allVpn => profileRules.isNotEmpty,
      };
      final entriesOutbounds = <Map<String, dynamic>>[];
      final exits = <Map<String, dynamic>>[];
      final selector = <String>[];
      for (final (index, entry) in entries.indexed) {
        final entryTag = 'app-entry-$index';
        final outbound = _node(entry, entryTag);
        nodeTags[entryTag] = entry.id;
        entriesOutbounds.add(outbound);
        if (finalExit == null) {
          selector.add(entryTag);
        } else {
          final exitTag = 'app-exit-$index';
          final exit = _node(finalExit, exitTag);
          setOutboundDialerProxy(exit, entryTag);
          nodeTags[exitTag] = finalExit.id;
          exits.add(exit);
          selector.add(exitTag);
        }
      }
      final fragment = switch (settings.trafficMode) {
        TrafficMode.smart || TrafficMode.selective =>
          settings.smart.fragment ? XrayFragment.defaultOutbound() : null,
        TrafficMode.custom => ordinary!.fragmentOutbound,
        TrafficMode.allVpn => null,
      };
      final helpers = <Map<String, dynamic>>[?fragment];
      final connectedEntries = XrayFragment.connectEntries(
        entriesOutbounds,
        helpers,
      );
      final outbounds = <Map<String, dynamic>>[
        if (finalExit == null) ...connectedEntries else ...exits,
        if (finalExit != null) ...connectedEntries,
        ...helpers,
      ];
      _applyOutboundPolicy(outbounds, options, raw: false);
      final bootstrapDomains = ManagedServerDialing.apply(
        outbounds: outbounds,
        settings: options.dialing.effective(ipv6: options.ipv6),
        // Only where _applyOutboundPolicy binds too: system proxy mode has
        // no tunnel to keep the dial out of.
        interfaceName: options.requiresInterface ? options.interfaceName : null,
      );
      outbounds.addAll([
        createFreedomOutbound(
          tag: 'direct',
          interfaceName: options.requiresInterface
              ? options.interfaceName
              : null,
        ).toJson(),
        createBlackholeOutbound(tag: 'block').toJson(),
        createDnsOutbound(
          tag: dnsOutbound,
          dialerProxy: allVpn ? selector.single : 'direct',
        ).toJson(),
      ]);
      final dnsSettings = _withNodeDns(
        switch (settings.trafficMode) {
          TrafficMode.smart || TrafficMode.selective => settings.smart.dns,
          TrafficMode.custom => ordinary!.dns,
          TrafficMode.allVpn => const RoutingDnsSettings(),
        },
        entries: entries,
        finalExit: finalExit,
        ipv6: options.ipv6,
      );
      final sniffing = switch (settings.trafficMode) {
        TrafficMode.smart || TrafficMode.selective => settings.smart.sniffing,
        TrafficMode.custom => ordinary!.sniffing,
        TrafficMode.allVpn => const RoutingSniffingSettings(),
      };
      final selectionSettings = switch (settings.trafficMode) {
        TrafficMode.smart || TrafficMode.selective => settings.smart.selection,
        TrafficMode.custom => ordinary!.selection,
        TrafficMode.allVpn => const RoutingSelectionSettings(),
      };
      final selection = selectionSettings.compile(selector: selector);
      final fakeDns = !allVpn && (ordinary?.fakeDns ?? settings.smart.fakeDns);
      dnsSettings.validate(directEnabled: directDns);
      selectionSettings.validate();
      sniffing.validate(fakeDns: fakeDns);
      final dns = RoutingDns.compile(
        settings: dnsSettings,
        rules: rules,
        directEnabled: directDns,
        fakeDns: fakeDns,
        ipv6: options.ipv6,
        defaultDirect: selective,
      );
      dns.servers = [
        ...ManagedServerDialing.bootstrapServers(
          domains: bootstrapDomains,
          ipv4Address: options.tunDnsIpv4Address,
          ipv6Address: options.tunDnsIpv6Address,
          ipv6: options.ipv6,
        ),
        ...?dns.servers,
      ];
      final normal = XrayJson(
        env: XrayEnv(
          assetLocation: VpnConstants.datDir,
          certLocation: VpnConstants.datDir,
        ),
        inbounds: [
          _runtimeInbound(
            options,
            fakeDns: FakeDns.usesServer(dns),
            sniffing: sniffing,
          ),
          if (options.lanProxyEnabled)
            createLanProxyInbound(
              options.lanProxyPort,
              user: options.lanProxyUser,
              password: options.lanProxyPassword,
              fakeDns: FakeDns.usesServer(dns),
              sniffing: sniffing,
            ),
        ],
        log: _runtimeLog(options),
        stats: XrayStats(),
        metrics: XrayMetrics(listen: '127.0.0.1:${options.metricsPort}'),
        policy: XrayPolicy(system: _runtimeStatsPolicy()),
        outbounds: outbounds,
        observatory: selection.observatory,
        dns: dns,
        fakedns: FakeDns.poolsFor(dns),
        routing: XrayRouting(
          // Address rules of a profile need the name resolved in All VPN too.
          domainStrategy: allVpn && !rules.any((rule) => rule.ip != null)
              ? 'AsIs'
              : 'IPIfNonMatch',
          balancers: [selection.balancer],
          rules: [
            if (bootstrapDomains.isNotEmpty)
              XrayRoutingRule(
                ruleTag: ManagedServerDialing.dnsTag,
                inboundTag: [ManagedServerDialing.dnsTag],
                outboundTag: 'direct',
              ),
            XrayRoutingRule(
              ruleTag: 'app-default',
              inboundTag: [dnsProxy],
              balancerTag: 'proxy',
            ),
            if (!allVpn || directDns)
              XrayRoutingRule(
                ruleTag: 'app-direct-dns',
                inboundTag: [dnsDirect],
                outboundTag: 'direct',
              ),
            XrayRoutingRule(
              ruleTag: 'app-tunnel-dns',
              inboundTag: ['tunIn'],
              port: '53',
              outboundTag: dnsOutbound,
            ),
            XrayRoutingRule(
              ruleTag: 'app-tunnel-dot',
              inboundTag: ['tunIn'],
              port: '853',
              balancerTag: 'proxy',
            ),
            // Fork: "Check connection" and the health monitor measure the VPN
            // in every mode. Selective, a direct profile or a custom rule
            // sent their hosts direct, and the check timed the direct path.
            XrayRoutingRule(
              ruleTag: liveProbeRuleTag,
              inboundTag: ['tunIn'],
              domain: [for (final host in LivePingProbe.hosts) 'full:$host'],
              balancerTag: 'proxy',
            ),
            ...rules,
            if (selective)
              XrayRoutingRule(
                ruleTag: TrafficProfiles.selectiveDirectTag,
                inboundTag: [
                  'tunIn',
                  if (options.lanProxyEnabled) lanProxyInboundTag,
                ],
                outboundTag: 'direct',
              )
            else if (selection.automatic)
              XrayRoutingRule(
                ruleTag: 'app-proxy-catchall',
                inboundTag: [
                  'tunIn',
                  if (options.lanProxyEnabled) lanProxyInboundTag,
                ],
                balancerTag: 'proxy',
              ),
          ],
        ),
      );
      config = normal.toJson();
    }
    return CompiledConnection(
      xrayJson: jsonEncode(config),
      entries: entries,
      finalExit: finalExit,
      nodeTags: nodeTags,
      profile: profile,
    );
  }

  /// Fork: one AmneziaWG node resolves through the DNS of its own config
  /// (`DNS =`, such as the server's AmneziaDNS) instead of 8.8.8.8. The
  /// outbound's netstack already resolves domain targets with `remoteDNS`;
  /// this covers Xray's own DNS too (TUN system queries, address rules).
  /// Only for a single node without a final exit, where the `proxy` balancer
  /// holds that node alone (the address often answers only inside its
  /// tunnel), and only while the user kept the default VPN resolver.
  /// Switching to a node with other DNS restarts the Core: `dns` is not
  /// part of a live swap.
  static RoutingDnsSettings _withNodeDns(
    RoutingDnsSettings settings, {
    required List<ResolvedServer> entries,
    required ResolvedServer? finalExit,
    required bool ipv6,
  }) {
    if (finalExit != null ||
        entries.length != 1 ||
        !settings.defaultProxyResolvers) {
      return settings;
    }
    final servers = [
      for (final server in AmneziaWG.remoteDns(entries.single.outbound))
        if (ipv6 ||
            InternetAddress.tryParse(server)?.type == InternetAddressType.IPv4)
          RoutingDnsResolver(address: server),
    ];
    return servers.isEmpty
        ? settings
        : settings.copyWith(proxyResolvers: servers);
  }

  static Map<String, dynamic> _node(ResolvedServer node, String tag) {
    final outbound = node.outbound;
    if (outboundDialerProxy(outbound)?.isNotEmpty == true ||
        outboundProxyTag(outbound)?.isNotEmpty == true) {
      throw const FormatException(
        'Normal nodes cannot reference other outbounds; use Raw for a complete configuration',
      );
    }
    return outbound
      ..remove('name')
      ..['tag'] = tag;
  }

  static Map<String, dynamic> _object(Map<String, dynamic> parent, String key) {
    final value = parent[key];
    if (value == null) return parent[key] = <String, dynamic>{};
    if (value is! Map<String, dynamic>) {
      throw FormatException('$key must be an object');
    }
    return parent[key] = Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _objects(
    Map<String, dynamic> parent,
    String key,
  ) {
    final value = parent[key] ?? <dynamic>[];
    if (value is! List || value.any((item) => item is! Map<String, dynamic>)) {
      throw FormatException('$key must be an object array');
    }
    return value.cast<Map<String, dynamic>>().toList();
  }

  static XrayInbound _runtimeInbound(
    RuntimeOptions options, {
    bool fakeDns = false,
    RoutingSniffingSettings sniffing = const RoutingSniffingSettings(),
  }) {
    if (options.usesLoopbackInbound) {
      return createSocksInbound(
        '${options.socksPort}',
        fakeDns: fakeDns,
        sniffing: sniffing,
      );
    }
    final nativeTun =
        options.platform == ConnectionPlatform.linux ||
        options.platform == ConnectionPlatform.windows;
    return createTunInbound(
      fakeDns: fakeDns,
      sniffing: sniffing,
      gateway: nativeTun
          ? ['198.18.0.1/15', if (options.ipv6) 'fc00::1/64']
          : null,
      dns: nativeTun
          ? [
              options.tunDnsIpv4Address,
              if (options.ipv6) options.tunDnsIpv6Address,
            ]
          : null,
      autoSystemRoutingTable: nativeTun
          ? ['0.0.0.0/0', if (options.ipv6) '::/0']
          : null,
      // Off on Windows, and explicitly: a missing key means "auto" next to
      // autoSystemRoutingTable. Xray's own binding (proxy/tun setinterface)
      // sets the IPv6 options on every dual-stack UDP socket and fails when
      // the interface has no IPv6, so no UDP left the Core at all (direct
      // DNS, LAN discovery, Hysteria2, AmneziaWG). Every outbound is bound
      // by sockopt.interface instead (_applyOutboundPolicy), which picks the
      // options by the destination's family.
      autoOutboundsInterface: switch (options.platform) {
        ConnectionPlatform.linux => options.interfaceName,
        ConnectionPlatform.windows => '',
        _ => null,
      },
      autoSystemWfpBlockLeak: options.platform == ConnectionPlatform.windows
          ? ['dns']
          : null,
    );
  }

  static XrayLog _runtimeLog(RuntimeOptions options) {
    final enabled = options.logEnabled && options.logFilesSupported;
    return XrayLog(
      access: enabled ? '${options.sessionDirectory}/access.log' : 'none',
      error: enabled ? '${options.sessionDirectory}/error.log' : 'none',
      logLevel: enabled ? options.logLevel : 'none',
      dnsLog: enabled && options.dnsLog,
      maskAddress: options.maskAddress,
    );
  }

  static XrayPolicySystem _runtimeStatsPolicy() => XrayPolicySystem(
    statsInboundUplink: true,
    statsInboundDownlink: true,
    statsOutboundUplink: false,
    statsOutboundDownlink: false,
  );

  static Map<String, dynamic> _fullRuntimeMap(
    Map<String, dynamic> source,
    RuntimeOptions options,
  ) => _rawRuntimeMap(
    VpnConfigAdapter.withDefaultDns(
      source,
      ipv4Address: options.tunDnsIpv4Address,
      ipv6Address: options.ipv6 ? options.tunDnsIpv6Address : null,
    ),
    options,
  );

  static Map<String, dynamic> _rawRuntimeMap(
    Map<String, dynamic> source,
    RuntimeOptions options, {
    bool includeLanProxy = false,
  }) {
    final config = JsonTool.copyMap(source);
    validateLocalDnsNetworkPolicy(
      config,
      requiresInterface: options.requiresInterface,
    );
    final outbounds = _objects(config, 'outbounds');
    final inbounds = _objects(config, 'inbounds');
    if (includeLanProxy) {
      validateLanProxyInbounds(inbounds, options.lanProxyPort);
    }
    for (final inbound in inbounds) {
      final tag = inbound['tag'];
      if (tag == 'tunIn') continue;
      if (inbound['protocol'] == 'tun') {
        throw const FormatException('Use the App-managed tunIn tunnel');
      }
      if (portIncludes(inbound['port'], options.metricsPort) ||
          (options.usesLoopbackInbound &&
              portIncludes(inbound['port'], options.socksPort))) {
        throw const FormatException(
          'Raw inbound conflicts with an App-managed port',
        );
      }
      _guardListen(inbound);
    }
    if (options.desktop) _dropUserApi(config, inbounds);
    final managed = inbounds.where((value) => value['tag'] == 'tunIn').toList();
    if (managed.length > 1) {
      throw const FormatException('Only one App-managed tunIn is allowed');
    }
    final generated = _runtimeInbound(
      options,
      fakeDns: FakeDns.usedByRaw(config),
    ).toJson();
    if (managed.isEmpty) {
      inbounds.insert(0, generated);
    } else {
      final inbound = managed.single;
      if (options.usesLoopbackInbound) {
        final settings = inbound['protocol'] == 'socks'
            ? _object(inbound, 'settings')
            : <String, dynamic>{};
        settings.addAll(generated['settings'] as Map<String, dynamic>);
        for (final key in ['protocol', 'listen', 'port']) {
          inbound[key] = generated[key];
        }
        inbound['settings'] = settings;
      } else {
        if (inbound['protocol'] != 'tun') {
          throw const FormatException('tunIn must use the tun protocol');
        }
        final settings = _object(inbound, 'settings');
        final platform = generated['settings'] as Map<String, dynamic>;
        for (final key in const [
          'name',
          'mtu',
          'gateway',
          'dns',
          'autoSystemRoutingTable',
          'autoOutboundsInterface',
        ]) {
          if (platform.containsKey(key)) {
            settings[key] = platform[key];
          } else {
            settings.remove(key);
          }
        }
        // Raw may explicitly opt out or select additional core-side filters.
        if (platform.containsKey('autoSystemWfpBlockLeak')) {
          settings.putIfAbsent(
            'autoSystemWfpBlockLeak',
            () => platform['autoSystemWfpBlockLeak'],
          );
        }
      }
    }
    if (includeLanProxy) {
      inbounds.add(
        createLanProxyInbound(
          options.lanProxyPort,
          user: options.lanProxyUser,
          password: options.lanProxyPassword,
          fakeDns: FakeDns.usedByRaw(config),
        ).toJson(),
      );
    }
    config['inbounds'] = inbounds;
    final env = _object(config, 'env')
      // `env` becomes process environment of the Core, which may run as
      // admin. Only Xray's own options; nothing like GODEBUG or HTTP_PROXY.
      // File descriptors belong to this native session, never an imported
      // graph. Windows compares environment names without case.
      ..removeWhere((key, _) {
        final name = key.toLowerCase();
        return !name.startsWith('xray.') || name == 'xray.tun.fd';
      });
    env['xray.location.asset'] = VpnConstants.datDir;
    env['xray.location.cert'] = VpnConstants.datDir;
    config.remove(
      'geodata',
    ); // App controls installed files, never core-side remote downloads.
    config['log'] = _runtimeLog(options).toJson();
    config['stats'] = <String, dynamic>{};
    config['metrics'] = {'listen': '127.0.0.1:${options.metricsPort}'};
    final policy = _object(config, 'policy');
    final system = _object(policy, 'system');
    system.addAll(_runtimeStatsPolicy().toJson());
    final levels = policy['levels'];
    if (levels is Map<String, dynamic>) {
      for (final level in levels.values) {
        if (level is Map<String, dynamic>) {
          level['statsUserUplink'] = false;
          level['statsUserDownlink'] = false;
        }
      }
    }
    final dns = _object(config, 'dns');
    final queryStrategy = options.ipv6 ? 'UseIP' : 'UseIPv4';
    dns['queryStrategy'] = queryStrategy;
    for (final server in (dns['servers'] as List? ?? [])) {
      if (server is Map<String, dynamic>) {
        server['queryStrategy'] = queryStrategy;
      }
    }
    _applyOutboundPolicy(outbounds, options, raw: true);
    config['outbounds'] = outbounds;
    return config;
  }

  // Proxy payloads remain maps in both modes; only their App-owned network
  // fields are changed here, without decoding the full config into a model.
  static void _applyOutboundPolicy(
    List<Map<String, dynamic>> outbounds,
    RuntimeOptions options, {
    required bool raw,
  }) {
    for (final outbound in outbounds) {
      if (['blackhole', 'loopback', 'dns'].contains(outbound['protocol'])) {
        continue;
      }
      final stream = _object(outbound, 'streamSettings');
      final sockopt = _object(stream, 'sockopt');
      if (outboundDialsLoopback(outbound)) {
        // A local server, such as a minewire engine, is not behind the
        // physical interface: Windows refuses the bound dial ("not valid in
        // its context") and loopback traffic never enters the tunnel anyway.
        sockopt.remove('interface');
      } else {
        _applyInterfacePolicy(sockopt, options);
      }
      if (!raw) {
        sockopt.remove('domainStrategy');
        final settings = outbound['settings'];
        if (settings is Map<String, dynamic>) {
          settings.remove('domainStrategy');
        }
      }
      if (sockopt.isEmpty) stream.remove('sockopt');
      if (stream.isEmpty) outbound.remove('streamSettings');
    }
  }

  static void _applyInterfacePolicy(
    Map<String, dynamic> sockopt,
    RuntimeOptions options,
  ) {
    if (options.requiresInterface) {
      sockopt['interface'] = options.interfaceName;
    } else {
      sockopt.remove('interface');
    }
  }

  /// A shared Raw config or template must not quietly turn this computer
  /// into an open proxy for the local network. Xray listens on every
  /// interface when `listen` is missing, so a missing value means loopback
  /// here; an explicit outside address stays, but only with authentication.
  static void _guardListen(Map<String, dynamic> inbound) {
    final listen = inbound['listen'];
    if (listen == null) {
      inbound['listen'] = '127.0.0.1';
      return;
    }
    if (listen is! String || _loopbackListen(listen)) return;
    final settings = inbound['settings'];
    final authenticated = switch (inbound['protocol']) {
      'socks' || 'mixed' =>
        settings is Map &&
            settings['auth'] == 'password' &&
            settings['accounts'] is List &&
            (settings['accounts'] as List).isNotEmpty,
      'http' =>
        settings is Map &&
            settings['accounts'] is List &&
            (settings['accounts'] as List).isNotEmpty,
      // Port forwards and server protocols carry their own access control.
      _ => true,
    };
    if (!authenticated) {
      throw FormatException(
        'Inbound ${inbound['tag'] ?? inbound['protocol']} listens on $listen '
        'without authentication; add accounts or listen on 127.0.0.1',
      );
    }
  }

  static bool _loopbackListen(String listen) {
    final value = listen.trim().toLowerCase();
    if (value == 'localhost' ||
        value.startsWith('/') ||
        value.startsWith('@')) {
      return true; // Unix sockets are local by definition.
    }
    final address = InternetAddress.tryParse(value);
    return address != null && address.isLoopback;
  }

  /// A desktop Core is a separate, possibly elevated process. A Raw `api`
  /// section would expose its gRPC API, which has no authentication, to any
  /// local process; the App's own authenticated control replaces it where
  /// needed. The API rules and the inbounds only they use go with it.
  static void _dropUserApi(
    Map<String, dynamic> config,
    List<Map<String, dynamic>> inbounds,
  ) {
    final api = config.remove('api');
    final apiTag = api is Map ? api['tag'] : null;
    if (apiTag is! String || apiTag.isEmpty) return;
    final routing = config['routing'];
    if (routing is! Map<String, dynamic>) return;
    final rules = [
      for (final rule in routing['rules'] as List? ?? const [])
        if (rule is Map<String, dynamic>) rule,
    ];
    final apiInbounds = <String>{};
    final kept = <Map<String, dynamic>>[];
    for (final rule in rules) {
      if (rule['outboundTag'] == apiTag) {
        final tags = rule['inboundTag'];
        if (tags is List) apiInbounds.addAll(tags.whereType<String>());
      } else {
        kept.add(rule);
      }
    }
    routing['rules'] = kept;
    final stillRouted = <String>{
      for (final rule in kept)
        if (rule['inboundTag'] is List)
          ...(rule['inboundTag'] as List).whereType<String>(),
    };
    inbounds.removeWhere(
      (inbound) =>
          apiInbounds.contains(inbound['tag']) &&
          !stillRouted.contains(inbound['tag']),
    );
  }

  static bool portIncludes(Object? value, int port) {
    if (value == null) return false;
    for (final part in '$value'.split(',')) {
      final ends = part.trim().split('-');
      final first = int.tryParse(ends.first);
      final last = int.tryParse(ends.last);
      if (first != null && last != null && first <= port && port <= last) {
        return true;
      }
    }
    return false;
  }
}
