import 'dart:convert';
import 'dart:io';

/// AmneziaWG and WireGuard client configs: the `.conf` files of AmneziaVPN,
/// amneziawg-tools and wg-quick, and the outbound they become.
///
/// The outbound is libXray's `amneziawg` (Xray's WireGuard client on
/// amneziawg-go v3, see `libXray/amneziawg`). A config without AmneziaWG
/// keys becomes the same outbound without them, which speaks plain
/// WireGuard. It is used instead of Xray's `wireguard` because that one
/// resolves its server with Xray's DNS, which in the App goes through the
/// proxy, that is, into the tunnel that is not up yet; `amneziawg` uses the
/// system resolver, like every other outbound.
abstract final class AmneziaWG {
  static const protocol = 'amneziawg';
  static const defaultName = 'AmneziaWG';
  static const wireGuardName = 'WireGuard';

  /// [Interface] keys of AmneziaWG, lower case, with their JSON names and kinds.
  static const _keys = <String, (String, _Kind)>{
    'jc': ('jc', _Kind.number),
    'jmin': ('jmin', _Kind.number),
    'jmax': ('jmax', _Kind.number),
    's1': ('s1', _Kind.number),
    's2': ('s2', _Kind.number),
    's3': ('s3', _Kind.number),
    's4': ('s4', _Kind.number),
    'h1': ('h1', _Kind.range),
    'h2': ('h2', _Kind.range),
    'h3': ('h3', _Kind.range),
    'h4': ('h4', _Kind.range),
    'i1': ('i1', _Kind.text),
    'i2': ('i2', _Kind.text),
    'i3': ('i3', _Kind.text),
    'i4': ('i4', _Kind.text),
    'i5': ('i5', _Kind.text),
    'headerprotectionkey': ('headerProtectionKey', _Kind.text),
    'contentpaddingaddition': ('contentPaddingAddition', _Kind.range),
    'rekeyaftertime': ('rekeyAfterTime', _Kind.range),
    'rekeytimeout': ('rekeyTimeout', _Kind.range),
    'rejectaftertime': ('rejectAfterTime', _Kind.range),
    'keepalivetimeout': ('keepaliveTimeout', _Kind.range),
    'maxhandshakeattempts': ('maxHandshakeAttempts', _Kind.range),
    'randomtrailers': ('randomTrailers', _Kind.flag),
    'disablecookies': ('disableCookies', _Kind.flag),
  };

  /// AmneziaWG 1.5 keys that amneziawg-go v3 dropped; such a config still
  /// connects when its server takes it without them.
  static const _dropped = {'j1', 'j2', 'j3', 'itime'};

  /// The `.conf` spelling of each JSON key, in the order configs write them.
  static final _confNames = {
    for (final entry in _keys.entries) entry.value.$1: _confName(entry.key),
  };

  static String _confName(String key) => switch (key) {
    'jc' => 'Jc',
    'jmin' => 'Jmin',
    'jmax' => 'Jmax',
    'headerprotectionkey' => 'HeaderProtectionKey',
    'contentpaddingaddition' => 'ContentPaddingAddition',
    'rekeyaftertime' => 'RekeyAfterTime',
    'rekeytimeout' => 'RekeyTimeout',
    'rejectaftertime' => 'RejectAfterTime',
    'keepalivetimeout' => 'KeepaliveTimeout',
    'maxhandshakeattempts' => 'MaxHandshakeAttempts',
    'randomtrailers' => 'RandomTrailers',
    'disablecookies' => 'DisableCookies',
    _ => key.toUpperCase(),
  };

  /// Whether [key] is an AmneziaWG key of a `.conf` [Interface].
  static bool isConfKey(String key) => _keys.containsKey(key.toLowerCase());

  static bool isOutbound(Map<String, dynamic> outbound) =>
      outbound['protocol'] == protocol;

  /// Whether the outbound's settings carry any AmneziaWG key, that is,
  /// whether it is more than plain WireGuard on the wire.
  static bool obfuscated(Map<String, dynamic> outbound) {
    final settings = outbound['settings'];
    if (settings is! Map) return false;
    return _confNames.keys.any((key) => settings[key] != null);
  }

  /// The servers of the config's `DNS =` line, kept at import as
  /// `remoteDNS`. They often answer only inside this node's tunnel (the
  /// AmneziaDNS container of a self-hosted server is a private address).
  static List<String> remoteDns(Map<String, dynamic> outbound) {
    if (!isOutbound(outbound)) return const [];
    final settings = outbound['settings'];
    if (settings is! Map) return const [];
    return [
      for (final server in _strings(settings['remoteDNS']))
        if (InternetAddress.tryParse(server) != null) server,
    ];
  }

  /// Whether [text] looks like a `.conf` file: an [Interface] section line.
  static bool looksLikeConf(String text) => RegExp(
    r'^\s*\[interface\]\s*$',
    caseSensitive: false,
    multiLine: true,
  ).hasMatch(text);

  /// The outbound of a `.conf` file named [name], or null when it is not a
  /// complete client config (a key, an address, a peer with a key and an
  /// endpoint). Unknown keys (PostUp, Table, ListenPort and the like) are
  /// ignored; a malformed AmneziaWG value rejects the config, since the
  /// server would never answer the handshake.
  static Map<String, dynamic>? fromConf(String text, {String? name}) {
    String? section;
    final interface = <String, String>{};
    final peers = <Map<String, String>>[];
    for (var line in const LineSplitter().convert(text)) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).trim().toLowerCase();
        if (section == 'peer') peers.add({});
        continue;
      }
      final index = line.indexOf('=');
      if (index <= 0) continue;
      final key = line.substring(0, index).trim().toLowerCase();
      var value = line.substring(index + 1).trim();
      // wg-quick allows a comment after a value; I1-I5 tags have no '#'.
      final comment = value.indexOf(' #');
      if (comment >= 0) value = value.substring(0, comment).trim();
      if (section == 'interface') {
        interface[key] = value;
      } else if (section == 'peer') {
        peers.last[key] = value;
      }
    }

    final secretKey = interface['privatekey'];
    final address = _list(interface['address']);
    if (secretKey == null || secretKey.isEmpty || address.isEmpty) {
      return null;
    }
    final settings = <String, dynamic>{
      'secretKey': secretKey,
      'address': address,
    };
    final dns = [
      for (final server in _list(interface['dns']))
        if (InternetAddress.tryParse(server) != null) server,
    ];
    if (dns.isNotEmpty) settings['remoteDNS'] = dns;
    if (interface['mtu'] case final mtu?) {
      final value = int.tryParse(mtu);
      if (value == null || value < 576 || value > 65535) return null;
      settings['mtu'] = value;
    }
    for (final MapEntry(:key, :value) in interface.entries) {
      final known = _keys[key];
      if (known == null || value.isEmpty) continue;
      final (json, kind) = known;
      final parsed = kind.parse(value);
      if (parsed == null) return null;
      settings[json] = parsed;
    }

    final peerSettings = <Map<String, dynamic>>[];
    for (final peer in peers) {
      final publicKey = peer['publickey'];
      final endpoint = peer['endpoint'];
      if (publicKey == null ||
          publicKey.isEmpty ||
          endpoint == null ||
          !_validEndpoint(endpoint)) {
        return null;
      }
      Object? keepAlive;
      if (peer['persistentkeepalive'] case final value?
          when value.toLowerCase() != 'off') {
        keepAlive = _Kind.range.parse(value);
        if (keepAlive == null) return null;
      }
      final allowed = _list(peer['allowedips']);
      peerSettings.add({
        'publicKey': publicKey,
        if (peer['presharedkey'] case final psk? when psk.isNotEmpty)
          'preSharedKey': psk,
        'endpoint': endpoint,
        if (keepAlive != null && keepAlive != 0) 'keepAlive': keepAlive,
        if (allowed.isNotEmpty) 'allowedIPs': allowed,
      });
    }
    if (peerSettings.isEmpty) return null;
    settings['peers'] = peerSettings;

    final draft = <String, dynamic>{'protocol': protocol, 'settings': settings};
    final title = name?.trim() ?? '';
    return {
      'tag': title.isNotEmpty
          ? title
          : obfuscated(draft)
          ? defaultName
          : wireGuardName,
      ...draft,
    };
  }

  /// Keys of AmneziaWG 1.5 a `.conf` file carries that the engine no longer
  /// takes; the import drops them.
  static List<String> droppedKeys(String text) => [
    for (final line in const LineSplitter().convert(text))
      if (line.split('=').first.trim().toLowerCase() case final key
          when _dropped.contains(key))
        key.toUpperCase(),
  ];

  /// The `.conf` file of an `amneziawg` outbound, or null when it is not a
  /// complete one. Keys stored in hex are written in base64, as `.conf`
  /// files have them.
  static String? toConf(Map<String, dynamic> outbound) {
    if (!isOutbound(outbound)) return null;
    final settings = outbound['settings'];
    if (settings is! Map) return null;
    final secretKey = base64Key(settings['secretKey']);
    final address = _strings(settings['address']);
    final peers = settings['peers'];
    if (secretKey == null || address.isEmpty || peers is! List) return null;
    final lines = <String>[
      '[Interface]',
      'PrivateKey = $secretKey',
      'Address = ${address.join(', ')}',
      if (_strings(settings['remoteDNS']) case final dns when dns.isNotEmpty)
        'DNS = ${dns.join(', ')}',
      if (settings['mtu'] case final int mtu) 'MTU = $mtu',
    ];
    for (final MapEntry(key: json, value: conf) in _confNames.entries) {
      final value = settings[json];
      if (value == null) continue;
      if (json == 'headerProtectionKey') {
        final key = base64Key(value);
        if (key == null) return null;
        lines.add('$conf = $key');
      } else if (value is bool) {
        lines.add('$conf = ${value ? 'on' : 'off'}');
      } else {
        lines.add('$conf = $value');
      }
    }
    var complete = false;
    for (final peer in peers) {
      if (peer is! Map) return null;
      final publicKey = base64Key(peer['publicKey']);
      final endpoint = peer['endpoint'];
      if (publicKey == null || endpoint is! String) return null;
      final allowed = _strings(peer['allowedIPs']);
      lines
        ..add('')
        ..add('[Peer]')
        ..add('PublicKey = $publicKey');
      if (peer['preSharedKey'] != null) {
        final psk = base64Key(peer['preSharedKey']);
        if (psk == null) return null;
        lines.add('PresharedKey = $psk');
      }
      lines
        ..add(
          'AllowedIPs = ${allowed.isEmpty ? '0.0.0.0/0, ::/0' : allowed.join(', ')}',
        )
        ..add('Endpoint = $endpoint');
      if (peer['keepAlive'] case final Object keepAlive) {
        lines.add('PersistentKeepalive = $keepAlive');
      }
      complete = true;
    }
    if (!complete) return null;
    return '${lines.join('\n')}\n';
  }

  static List<String> _list(String? value) => value == null
      ? const []
      : [
          for (final item in value.split(','))
            if (item.trim().isNotEmpty) item.trim(),
        ];

  static List<String> _strings(Object? value) => value is List
      ? [
          for (final item in value)
            if (item is String) item,
        ]
      : const [];

  static bool _validEndpoint(String endpoint) {
    final index = endpoint.lastIndexOf(':');
    if (index <= 0) return false;
    final port = int.tryParse(endpoint.substring(index + 1));
    return port != null && port > 0 && port <= 65535;
  }

  /// A key in base64, whether stored so or in hex (Xray takes both).
  static String? base64Key(Object? value) {
    if (value is! String || value.isEmpty) return null;
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      return base64.encode([
        for (var i = 0; i < 64; i += 2)
          int.parse(value.substring(i, i + 2), radix: 16),
      ]);
    }
    return value;
  }
}

enum _Kind {
  number,
  range,
  text,
  flag;

  /// The JSON value of a `.conf` value, or null when it is malformed.
  Object? parse(String value) => switch (this) {
    _Kind.number => int.tryParse(value),
    _Kind.range => _range(value),
    _Kind.text => value,
    _Kind.flag => switch (value.toLowerCase()) {
      'on' || 'true' || 'yes' || '1' => true,
      'off' || 'false' || 'no' || '0' => false,
      _ => null,
    },
  };

  /// A number stays a number; a range "lo-hi" stays a string.
  static Object? _range(String value) {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$').firstMatch(value);
    if (match == null) return null;
    final low = int.parse(match.group(1)!);
    final high = match.group(2) == null ? low : int.parse(match.group(2)!);
    if (high < low || high > 0xffffffff) return null;
    return low == high ? low : '$low-$high';
  }
}
