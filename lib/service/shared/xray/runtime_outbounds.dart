import 'dart:io';

import 'package:onexray/core/model/xray_json.dart';

XrayOutbound createFreedomOutbound({
  required String tag,
  String? interfaceName,
}) => XrayOutbound(
  tag: tag,
  protocol: 'freedom',
  streamSettings: interfaceName == null
      ? null
      : XrayStreamSettings(sockopt: XraySockopt(interface: interfaceName)),
);

/// The `proxy` balancer falls back to its own first node, never to `direct`.
///
/// The fallback is taken only when no selected outbound exists: during a
/// live node switch, between removing the old node and adding the new one
/// under the same tag. Xray drops a connection routed to a missing tag, so
/// that window fails closed instead of sending DNS, DoT and smart-mode proxy
/// traffic past the tunnel. The fallback also needs the observatory feature.
String? proxyFallbackTag(List<String> selector) =>
    selector.isEmpty ? null : selector.first;

XrayOutbound createBlackholeOutbound({required String tag}) =>
    XrayOutbound(tag: tag, protocol: 'blackhole');

XrayOutbound createDnsOutbound({
  required String tag,
  required String dialerProxy,
}) => XrayOutbound(
  tag: tag,
  protocol: 'dns',
  settings: {
    'rules': const [
      XrayOutboundDnsRule(action: 'hijack', qType: '1,28'),
      XrayOutboundDnsRule(action: 'direct'),
    ].map((rule) => rule.toJson()).toList(),
  },
  streamSettings: XrayStreamSettings(
    sockopt: XraySockopt(dialerProxy: dialerProxy),
  ),
);

/// Every server [outbound] dials is on loopback, in any Xray layout: flat
/// `address`, `servers`/`vnext` lists, or the `peers` endpoints of
/// WireGuard and AmneziaWG (whose `address` is their own side of the
/// tunnel, never a server). minewire engines are such local servers.
bool outboundDialsLoopback(Map<String, dynamic> outbound) {
  final settings = outbound['settings'];
  if (settings is! Map) return false;
  final addresses = switch (outbound['protocol']) {
    'wireguard' || 'amneziawg' => [
      if (settings['peers'] case final List peers)
        for (final peer in peers)
          if (peer is Map) _endpointHost(peer['endpoint']),
    ],
    _ => [
      ?settings['address'],
      for (final key in const ['servers', 'vnext'])
        if (settings[key] case final List servers)
          for (final server in servers)
            if (server is Map) server['address'],
    ],
  };
  return addresses.isNotEmpty &&
      addresses.every((address) {
        if (address is! String) return false;
        final value = address.trim().toLowerCase();
        return value == 'localhost' ||
            (InternetAddress.tryParse(value)?.isLoopback ?? false);
      });
}

/// The host of a `host:port` or `[v6]:port` endpoint.
Object? _endpointHost(Object? endpoint) {
  if (endpoint is! String) return null;
  final index = endpoint.lastIndexOf(':');
  if (index <= 0) return null;
  final host = endpoint.substring(0, index);
  return host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;
}
