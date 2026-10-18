import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/shared/xray/runtime_outbounds.dart';

/// Shared by route compilation and its local validation placeholders.
abstract final class XrayFragment {
  static const tag = 'fragment';

  static const _udpOnly = {'wireguard', 'amneziawg'};

  static bool matches(Map<String, dynamic> outbound) =>
      outbound['tag'] == tag && outbound['protocol'] == 'freedom';

  static Map<String, dynamic> defaultOutbound() => XrayOutbound(
    tag: tag,
    protocol: 'freedom',
    settings: {
      'fragment': {
        'packets': 'tlshello',
        'length': '100-200',
        'interval': '10-20',
      },
    },
  ).toJson();

  /// Only the selected entry roles are linked. Exit clones and user helper
  /// chains are not entries, even when they use the same protocol.
  ///
  /// Entries on loopback (minewire engines) stay direct: they have no TLS
  /// hello of their own to split, and the fragment outbound is bound to the
  /// physical interface, through which Windows refuses a loopback dial.
  /// WireGuard and AmneziaWG stay direct too: they speak UDP with no TLS.
  static List<Map<String, dynamic>> connectEntries(
    Iterable<Map<String, dynamic>> entries,
    Iterable<Map<String, dynamic>> helpers,
  ) {
    final enabled = helpers.any(matches);
    return entries.map((source) {
      final outbound = JsonTool.copyMap(source);
      if (enabled &&
          !_udpOnly.contains(outbound['protocol']) &&
          !outboundDialsLoopback(outbound)) {
        setOutboundDialerProxy(outbound, tag);
      }
      return outbound;
    }).toList();
  }
}
