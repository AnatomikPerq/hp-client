import 'dart:convert';
import 'dart:io';

import 'package:onexray/service/amneziawg/conf.dart';
import 'package:onexray/service/shared/share/share_text.dart';
import 'package:onexray/service/shared/share/xray_config_share.dart';

/// Share links of AmneziaWG and WireGuard, which libXray does not know and
/// drops: they are parsed here, before libXray, like minewire links.
///
/// - `awg://<base64 of a .conf>#<name>`, as providers serve AmneziaWG up to 3.1;
/// - `vpn://<base64>`, AmneziaVPN's key: Qt-compressed JSON whose AmneziaWG
///   and WireGuard containers each carry a `.conf` (an Xray container
///   carries an Xray client config, which is taken as well);
/// - `wireguard://` and `wg://`, the URI of v2rayN and NekoBox:
///   `wireguard://<private key>@<host>:<port>?publickey=...&address=...`.
abstract final class AmneziaWGLinks {
  static const _schemes = ['awg', 'vpn', 'wireguard', 'wg'];

  static bool matches(String line) {
    final text = line.trimLeft().toLowerCase();
    return _schemes.any((scheme) => text.startsWith('$scheme://'));
  }

  /// The nodes of one link; empty for anything malformed, since one broken
  /// node must not fail a whole subscription.
  static List<Map<String, dynamic>> parse(String line) {
    final text = line.trim();
    final index = text.indexOf('://');
    if (index < 0) return const [];
    final scheme = text.substring(0, index).toLowerCase();
    final rest = text.substring(index + 3);
    return switch (scheme) {
      'awg' => _awg(rest),
      'vpn' => _amnezia(rest),
      'wireguard' || 'wg' => [?_uri(text)],
      _ => const [],
    };
  }

  static List<Map<String, dynamic>> _awg(String rest) {
    final hash = rest.indexOf('#');
    final body = hash < 0 ? rest : rest.substring(0, hash);
    final name = hash < 0 ? null : _decode(rest.substring(hash + 1));
    final bytes = decodeBase64Loose(_decode(body) ?? body);
    if (bytes != null) {
      try {
        final conf = utf8.decode(bytes);
        if (AmneziaWG.looksLikeConf(conf)) {
          return [?AmneziaWG.fromConf(conf, name: name)];
        }
      } on FormatException {
        // Not UTF-8: maybe the URI form below.
      }
    }
    // Some clients write awg:// in the URI form of wireguard://.
    return [?_uri('awg://$rest')];
  }

  /// AmneziaVPN's `vpn://` key: base64 of Qt's qCompress (a 4-byte length,
  /// then zlib) of the server JSON, or of the JSON itself.
  static List<Map<String, dynamic>> _amnezia(String rest) {
    final bytes = decodeBase64Loose(rest.split('#').first);
    if (bytes == null || bytes.length < 5) return const [];
    Object? root;
    for (final decode in <List<int> Function(List<int>)>[
      (bytes) => ZLibDecoder().convert(bytes.sublist(4)),
      (bytes) => ZLibDecoder().convert(bytes),
      (bytes) => bytes,
    ]) {
      try {
        root = jsonDecode(utf8.decode(decode(bytes)));
        break;
      } on Exception {
        continue; // Not this encoding.
      }
    }
    if (root is! Map) return const [];
    final containers = root['containers'];
    if (containers is! List) return const [];
    final title = [root['description'], root['name'], root['hostName']]
        .whereType<String>()
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final nodes = <Map<String, dynamic>>[];
    for (final container in containers) {
      if (container is! Map) continue;
      for (final (key, label) in const [
        ('awg', AmneziaWG.defaultName),
        ('wireguard', AmneziaWG.wireGuardName),
        ('xray', 'Xray'),
      ]) {
        final protocol = container[key];
        if (protocol is! Map) continue;
        final last = protocol['last_config'];
        if (last is! String) continue;
        final name = title.isEmpty ? label : '$title · $label';
        if (key == 'xray') {
          for (final outbound in xrayConfigOutbounds(last) ?? const []) {
            nodes.add({...outbound, 'tag': name});
          }
          continue;
        }
        Object? config;
        try {
          config = jsonDecode(last);
        } on FormatException {
          continue;
        }
        if (config is! Map || config['config'] is! String) continue;
        final conf = (config['config'] as String)
            .replaceAll(r'$PRIMARY_DNS', '${root['dns1'] ?? ''}')
            .replaceAll(r'$SECONDARY_DNS', '${root['dns2'] ?? ''}');
        if (AmneziaWG.fromConf(conf, name: name) case final node?) {
          nodes.add(node);
        }
      }
    }
    return nodes;
  }

  /// The URI form: a private key as the user, the endpoint as the host, the
  /// rest in the query under the names of v2rayN or NekoBox. With
  /// `reserved` (Cloudflare WARP) the node is Xray's own `wireguard`, the
  /// only one that writes it; without, it is `amneziawg`, with any
  /// AmneziaWG keys of the query.
  static Map<String, dynamic>? _uri(String text) {
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return null;
    }
    final query = {
      for (final MapEntry(:key, :value) in uri.queryParameters.entries)
        key.toLowerCase(): value.trim(),
    };
    String? pick(List<String> names) => names
        .map((name) => query[name])
        .firstWhere(
          (value) => value != null && value.isNotEmpty,
          orElse: () => null,
        );
    final secretKey =
        (uri.userInfo.isEmpty ? null : _decode(uri.userInfo)) ??
        pick(['privatekey', 'secretkey']);
    final publicKey = pick([
      'publickey',
      'public_key',
      'peer_public_key',
      'pbk',
    ]);
    final address = (pick(['address', 'local_address', 'ip']) ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (secretKey == null ||
        secretKey.isEmpty ||
        publicKey == null ||
        address.isEmpty ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port <= 0 ||
        uri.port > 65535) {
      return null;
    }
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final reserved = pick(['reserved']);
    final name = _decode(uri.fragment)?.trim() ?? '';
    final mtu = int.tryParse(pick(['mtu']) ?? '');
    final keepAlive = pick([
      'keepalive',
      'persistentkeepalive',
      'persistent_keepalive',
    ]);
    final allowed = (pick(['allowedips', 'allowed_ips']) ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final dns = (pick(['dns']) ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => InternetAddress.tryParse(value) != null)
        .toList();
    final psk = pick(['presharedkey', 'pre_shared_key', 'psk']);
    if (reserved != null) {
      final bytes = reserved
          .split(',')
          .map((value) => int.tryParse(value.trim()))
          .toList();
      if (bytes.length != 3 ||
          bytes.any((b) => b == null || b < 0 || b > 255)) {
        return null;
      }
      return {
        'tag': name.isEmpty ? AmneziaWG.wireGuardName : name,
        'protocol': 'wireguard',
        'settings': {
          'secretKey': secretKey,
          'address': address,
          'peers': [
            {
              'publicKey': publicKey,
              'preSharedKey': ?psk,
              'endpoint': '$host:${uri.port}',
              if (int.tryParse(keepAlive ?? '') case final value?
                  when value > 0)
                'keepAlive': value,
              if (allowed.isNotEmpty) 'allowedIPs': allowed,
            },
          ],
          'mtu': ?mtu,
          'reserved': bytes,
        },
      };
    }
    // The same lines a .conf file would have, read by the same code.
    final conf = StringBuffer()
      ..writeln('[Interface]')
      ..writeln('PrivateKey = $secretKey')
      ..writeln('Address = ${address.join(', ')}');
    if (dns.isNotEmpty) conf.writeln('DNS = ${dns.join(', ')}');
    if (mtu != null) conf.writeln('MTU = $mtu');
    for (final MapEntry(:key, :value) in query.entries) {
      if (AmneziaWG.isConfKey(key)) conf.writeln('$key = $value');
    }
    conf
      ..writeln('[Peer]')
      ..writeln('PublicKey = $publicKey')
      ..writeln('Endpoint = $host:${uri.port}');
    if (psk != null) conf.writeln('PresharedKey = $psk');
    if (allowed.isNotEmpty) conf.writeln('AllowedIPs = ${allowed.join(', ')}');
    if (keepAlive != null) conf.writeln('PersistentKeepalive = $keepAlive');
    return AmneziaWG.fromConf(conf.toString(), name: name);
  }

  /// An `awg://` link of a `.conf` file as it is, named [name].
  static String confLink(String conf, String name) =>
      'awg://${base64Url.encode(utf8.encode(conf))}'
      '${name.isEmpty ? '' : '#${Uri.encodeComponent(name)}'}';

  /// The link to share a node by: `awg://` with its `.conf` for AmneziaWG,
  /// `wireguard://` for plain WireGuard (more clients read that one), null
  /// for anything else.
  static String? shareLink(Map<String, dynamic> outbound) {
    final tag = outbound['tag'];
    final name = tag is String ? tag : '';
    if (AmneziaWG.isOutbound(outbound) && AmneziaWG.obfuscated(outbound)) {
      final conf = AmneziaWG.toConf(outbound);
      return conf == null ? null : confLink(conf, name);
    }
    if (!AmneziaWG.isOutbound(outbound) &&
        outbound['protocol'] != 'wireguard') {
      return null;
    }
    final settings = outbound['settings'];
    if (settings is! Map) return null;
    final peers = settings['peers'];
    if (peers is! List || peers.isEmpty || peers.first is! Map) return null;
    final peer = peers.first as Map;
    final endpoint = peer['endpoint'];
    final secretKey = AmneziaWG.base64Key(settings['secretKey']);
    final publicKey = AmneziaWG.base64Key(peer['publicKey']);
    if (endpoint is! String || secretKey == null || publicKey == null) {
      return null;
    }
    final Uri target;
    try {
      target = Uri.parse('wireguard://$endpoint');
    } on FormatException {
      return null;
    }
    if (target.host.isEmpty || !target.hasPort) return null;
    final address = settings['address'];
    final allowed = peer['allowedIPs'];
    final reserved = settings['reserved'];
    final psk = AmneziaWG.base64Key(peer['preSharedKey']);
    final query = {
      'publickey': publicKey,
      'presharedkey': ?psk,
      if (address is List) 'address': address.join(','),
      if (settings['mtu'] case final int mtu) 'mtu': '$mtu',
      if (peer['keepAlive'] case final Object keepAlive)
        'keepalive': '$keepAlive',
      if (allowed is List && allowed.isNotEmpty)
        'allowedips': allowed.join(','),
      if (reserved is List && reserved.length == 3)
        'reserved': reserved.join(','),
    };
    return Uri(
      scheme: 'wireguard',
      userInfo: Uri.encodeComponent(secretKey),
      host: target.host,
      port: target.port,
      queryParameters: query,
      fragment: name.isEmpty ? null : name,
    ).toString();
  }

  static String? _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}
