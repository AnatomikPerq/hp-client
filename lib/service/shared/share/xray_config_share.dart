import 'dart:convert';

/// Outbounds that only route locally and are never a server to connect to.
const _localProtocols = {'freedom', 'blackhole', 'dns', 'loopback'};

/// Subscriptions that serve full Xray client configs instead of share links:
/// a JSON array of them (v2rayN, Happ, Remnawave's JSON format) or one.
///
/// Each config's proxy outbound becomes an ordinary node named after the
/// config's `remarks`, so what links cannot carry, mux above all, survives
/// the import. The rest of a config (inbounds, DNS, routing, balancers) is
/// the provider's idea of a client and is dropped: the App compiles its own
/// around the node. An outbound that needs another one of its config
/// (`dialerProxy`, `proxySettings`) is skipped; alone it would not work.
///
/// Returns null when [text] is not such JSON. A bare `{"outbounds": [...]}`
/// is not a client config either: libXray imports that one as it is.
List<Map<String, dynamic>>? xrayConfigOutbounds(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('[') && !trimmed.startsWith('{')) return null;
  final Object? root;
  try {
    root = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  final configs = switch (root) {
    List() => [
      for (final config in root)
        if (config is Map<String, dynamic> && config['outbounds'] is List)
          config,
    ],
    Map<String, dynamic>()
        when root['outbounds'] is List &&
            (root.containsKey('remarks') ||
                root.containsKey('inbounds') ||
                root.containsKey('routing')) =>
      [root],
    _ => const <Map<String, dynamic>>[],
  };
  if (configs.isEmpty) return null;
  final result = <Map<String, dynamic>>[];
  for (final config in configs) {
    final proxies = [
      for (final outbound in config['outbounds'] as List)
        if (outbound is Map<String, dynamic> &&
            outbound['protocol'] is String &&
            !_localProtocols.contains(outbound['protocol']) &&
            !_needsAnotherOutbound(outbound))
          outbound,
    ];
    final remarks = config['remarks'];
    final title = remarks is String ? remarks.trim() : '';
    for (final outbound in proxies) {
      final copy = jsonDecode(jsonEncode(outbound)) as Map<String, dynamic>;
      final tag = copy['tag'] is String ? (copy['tag'] as String).trim() : '';
      final name = title.isEmpty
          ? tag
          : proxies.length == 1 || tag.isEmpty
          ? title
          : '$title · $tag';
      if (name.isEmpty) {
        copy.remove('tag');
      } else {
        copy['tag'] = name;
      }
      result.add(copy);
    }
  }
  return result;
}

bool _needsAnotherOutbound(Map<String, dynamic> outbound) {
  if (outbound['proxySettings'] is Map) return true;
  final stream = outbound['streamSettings'];
  final sockopt = stream is Map ? stream['sockopt'] : null;
  final dialer = sockopt is Map ? sockopt['dialerProxy'] : null;
  return dialer is String && dialer.isNotEmpty;
}
