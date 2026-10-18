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
