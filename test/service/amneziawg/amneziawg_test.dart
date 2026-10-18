import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/amneziawg/conf.dart';
import 'package:onexray/service/amneziawg/link.dart';
import 'package:onexray/service/amneziawg/share.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/shared/share/xray_share_reader.dart';
import 'package:onexray/service/shared/xray/fragment.dart';
import 'package:onexray/service/shared/xray/runtime_outbounds.dart';

String _key(String fill) => base64.encode(utf8.encode(fill * 32));

/// The shape of the AmneziaWG 3.1 config a provider serves, with fake keys.
final _conf =
    '''
[Interface]
Address = 10.8.0.2/32
DNS = 1.1.1.1, 1.0.0.1
PrivateKey = ${_key('a')}
Jc = 6
Jmin = 10
Jmax = 50
S1 = 12
S2 = 12
S3 = 12
S4 = 12
H1 = 1
H2 = 2
H3 = 3
H4 = 4
I1 = <r 2><b 0x8580>
HeaderProtectionKey = ${_key('d')}
RekeyAfterTime = 100-120
RekeyTimeout = 3-7
RejectAfterTime = 150-180
KeepaliveTimeout = 5-15
MaxHandshakeAttempts = 15-20
RandomTrailers = on
DisableCookies = on

[Peer]
PublicKey = ${_key('b')}
PresharedKey = ${_key('c')}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = node.example:51820
PersistentKeepalive = 25-35
''';

Map<String, dynamic> _settings(Map<String, dynamic> outbound) =>
    outbound['settings'] as Map<String, dynamic>;

void main() {
  group('.conf', () {
    test('every AmneziaWG 3.1 key reaches the outbound', () {
      final outbound = AmneziaWG.fromConf(_conf, name: '🧬 Mutant')!;
      expect(outbound['tag'], '🧬 Mutant');
      expect(outbound['protocol'], 'amneziawg');
      expect(_settings(outbound), {
        'secretKey': _key('a'),
        'address': ['10.8.0.2/32'],
        'remoteDNS': ['1.1.1.1', '1.0.0.1'],
        'jc': 6,
        'jmin': 10,
        'jmax': 50,
        's1': 12,
        's2': 12,
        's3': 12,
        's4': 12,
        'h1': 1,
        'h2': 2,
        'h3': 3,
        'h4': 4,
        'i1': '<r 2><b 0x8580>',
        'headerProtectionKey': _key('d'),
        'rekeyAfterTime': '100-120',
        'rekeyTimeout': '3-7',
        'rejectAfterTime': '150-180',
        'keepaliveTimeout': '5-15',
        'maxHandshakeAttempts': '15-20',
        'randomTrailers': true,
        'disableCookies': true,
        'peers': [
          {
            'publicKey': _key('b'),
            'preSharedKey': _key('c'),
            'endpoint': 'node.example:51820',
            'keepAlive': '25-35',
            'allowedIPs': ['0.0.0.0/0', '::/0'],
          },
        ],
      });
      expect(outboundProtocolLabel(outbound), 'AMNEZIAWG');
    });

    test('a config written back reads the same', () {
      final outbound = AmneziaWG.fromConf(_conf, name: 'n')!;
      final again = AmneziaWG.fromConf(AmneziaWG.toConf(outbound)!, name: 'n');
      expect(again, outbound);
    });

    test('hex keys are written in base64', () {
      final outbound = AmneziaWG.fromConf(_conf, name: 'n')!;
      _settings(outbound)['secretKey'] = '61' * 32;
      expect(AmneziaWG.toConf(outbound), contains('PrivateKey = ${_key('a')}'));
    });

    test('plain WireGuard is the same outbound without the keys', () {
      final outbound = AmneziaWG.fromConf('''
# a wg-quick file
[Interface]
PrivateKey = ${_key('a')}
Address = 10.0.0.2/32, fd00::2/128
DNS = 9.9.9.9, home.lan
MTU = 1420
ListenPort = 51820
PostUp = iptables -A FORWARD

[Peer]
PublicKey = ${_key('b')}
Endpoint = [2001:db8::1]:51820 # the server
PersistentKeepalive = 25
''')!;
      expect(outbound['tag'], 'WireGuard');
      expect(AmneziaWG.obfuscated(outbound), isFalse);
      expect(outboundProtocolLabel(outbound), 'WIREGUARD');
      expect(_settings(outbound), {
        'secretKey': _key('a'),
        'address': ['10.0.0.2/32', 'fd00::2/128'],
        'remoteDNS': ['9.9.9.9'],
        'mtu': 1420,
        'peers': [
          {
            'publicKey': _key('b'),
            'endpoint': '[2001:db8::1]:51820',
            'keepAlive': 25,
          },
        ],
      });
    });

    test('AmneziaWG 1.5 keys are dropped and reported', () {
      final legacy = _conf.replaceFirst(
        'Jc = 6',
        'Jc = 6\nJ1 = <b 0x01>\nItime = 60',
      );
      final outbound = AmneziaWG.fromConf(legacy)!;
      expect(_settings(outbound).keys, isNot(contains('j1')));
      expect(AmneziaWG.droppedKeys(legacy), ['J1', 'ITIME']);
    });

    test('incomplete or malformed configs are refused', () {
      for (final broken in [
        _conf.replaceFirst(RegExp(r'PrivateKey = .*'), ''),
        _conf.replaceFirst('Address = 10.8.0.2/32', ''),
        _conf.replaceFirst('Endpoint = node.example:51820', 'Endpoint = x'),
        _conf.replaceFirst('[Peer]', '[Nope]'),
        _conf.replaceFirst('H3 = 3', 'H3 = 9-1'),
        _conf.replaceFirst('RandomTrailers = on', 'RandomTrailers = maybe'),
        _conf.replaceFirst('Jc = 6', 'Jc = many'),
      ]) {
        expect(AmneziaWG.fromConf(broken), isNull);
      }
    });
  });

  group('links', () {
    test('awg:// carries a .conf in base64', () {
      final link =
          'awg://${base64Url.encode(utf8.encode(_conf)).replaceAll('=', '')}'
          '#${Uri.encodeComponent('🧬 Мутант (AWG 2.0)')}';
      final nodes = AmneziaWGLinks.parse(link);
      expect(nodes, [AmneziaWG.fromConf(_conf, name: '🧬 Мутант (AWG 2.0)')]);
    });

    test('a shared AmneziaWG node reads back the same', () {
      final outbound = AmneziaWG.fromConf(_conf, name: 'Mutant')!;
      final link = AmneziaWGLinks.shareLink(outbound)!;
      expect(link, startsWith('awg://'));
      expect(AmneziaWGLinks.parse(link), [outbound]);
    });

    test('vpn:// of AmneziaVPN, Qt-compressed, with its DNS placeholders', () {
      final lastConfig = jsonEncode({
        'config': _conf.replaceFirst(
          'DNS = 1.1.1.1, 1.0.0.1',
          r'DNS = $PRIMARY_DNS, $SECONDARY_DNS',
        ),
      });
      final json = utf8.encode(
        jsonEncode({
          'containers': [
            {
              'container': 'amnezia-awg',
              'awg': {'last_config': lastConfig, 'port': '51820'},
            },
            {'container': 'amnezia-openvpn', 'openvpn': {}},
          ],
          'defaultContainer': 'amnezia-awg',
          'description': 'Home',
          'dns1': '8.8.8.8',
          'dns2': '8.8.4.4',
        }),
      );
      final length = ByteData(4)..setUint32(0, json.length);
      final compressed = [
        ...length.buffer.asUint8List(),
        ...ZLibEncoder().convert(json),
      ];
      final nodes = AmneziaWGLinks.parse(
        'vpn://${base64Url.encode(compressed).replaceAll('=', '')}',
      );
      expect(nodes, hasLength(1));
      expect(nodes.single['tag'], 'Home · AmneziaWG');
      expect(_settings(nodes.single)['remoteDNS'], ['8.8.8.8', '8.8.4.4']);
      expect(_settings(nodes.single)['h1'], 1);
    });

    test('wireguard:// becomes amneziawg, with reserved Xray wireguard', () {
      final plain = AmneziaWGLinks.parse(
        'wireguard://${Uri.encodeComponent(_key('a'))}@1.2.3.4:51820'
        '?publickey=${Uri.encodeComponent(_key('b'))}'
        '&address=10.0.0.2%2F32,fd00::2%2F128&mtu=1280&keepalive=25#WG',
      ).single;
      expect(plain['protocol'], 'amneziawg');
      expect(plain['tag'], 'WG');
      expect(_settings(plain)['mtu'], 1280);
      expect((_settings(plain)['peers'] as List).single, {
        'publicKey': _key('b'),
        'endpoint': '1.2.3.4:51820',
        'keepAlive': 25,
      });
      final again = AmneziaWGLinks.parse(AmneziaWGLinks.shareLink(plain)!);
      expect(again, [plain]);

      final warp = AmneziaWGLinks.parse(
        'wg://${Uri.encodeComponent(_key('a'))}@[2606:4700::1]:2408'
        '?public_key=${Uri.encodeComponent(_key('b'))}'
        '&local_address=172.16.0.2/32&reserved=1,2,3',
      ).single;
      final queryKey = AmneziaWGLinks.parse(
        'wireguard://1.2.3.4:51820?privatekey=${Uri.encodeComponent(_key('a'))}'
        '&publickey=${Uri.encodeComponent(_key('b'))}&address=10.0.0.2',
      ).single;
      expect(_settings(queryKey)['secretKey'], _key('a'));

      expect(warp['protocol'], 'wireguard');
      expect(_settings(warp)['reserved'], [1, 2, 3]);
      expect(
        ((_settings(warp)['peers'] as List).single as Map)['endpoint'],
        '[2606:4700::1]:2408',
      );
    });

    test('malformed links give no node', () {
      for (final link in [
        'awg://not-base64!#x',
        'vpn://AAAA',
        'wireguard://key@1.2.3.4?publickey=x&address=10.0.0.2',
        'wireguard://key@1.2.3.4:51820?address=10.0.0.2',
        'wg://key@1.2.3.4:51820?publickey=x&address=10.0.0.2&reserved=1,2',
      ]) {
        expect(AmneziaWGLinks.parse(link), isEmpty, reason: link);
      }
    });
  });

  group('share text', () {
    test('a base64 subscription loses only its AmneziaWG lines', () {
      final awg = 'awg://${base64Url.encode(utf8.encode(_conf))}#Mutant';
      const vless = 'vless://id@node.example:443?security=tls#V';
      final split = splitAmneziaWGLinks(
        base64.encode(utf8.encode('$vless\n$awg\n')),
      );
      expect(split.nodes.single['tag'], 'Mutant');
      expect(split.rest.trim(), vless);
    });

    test('a pasted .conf next to a link is one node', () {
      const vless = 'vless://id@node.example:443?security=tls#V';
      final split = splitAmneziaWGLinks('$_conf\n$vless');
      expect(split.nodes, [AmneziaWG.fromConf(_conf)]);
      expect(split.rest.trim(), vless);
    });

    test('text without AmneziaWG passes through untouched', () {
      const text = 'dmxlc3M6Ly9pZEBub2RlOjQ0Mw==';
      final split = splitAmneziaWGLinks(text);
      expect(split.nodes, isEmpty);
      expect(split.rest, text);
    });

    test('the reader keeps the nodes the core builds', () async {
      final good = 'awg://${base64Url.encode(utf8.encode(_conf))}#Good';
      final bad =
          'awg://${base64Url.encode(utf8.encode(_conf.replaceFirst('I1 = <r 2>', 'I1 = <nope 2>')))}#Bad';
      final checked = <String>[];
      final rows = await XrayShareReader().parseShareText(
        '$good\n$bad\nvless://id@node.example:443#V',
        convert: (text, _) async => [
          {
            'tag': 'V',
            'protocol': 'vless',
            'settings': {'address': 'node.example', 'port': 443},
          },
        ],
        validate: (json) async {
          checked.add(json);
          return json.contains('<nope') ? 'unknown tag <nope>' : '';
        },
      );
      expect(rows.map((row) => row.name.value), ['V', 'Good']);
      expect(checked, hasLength(2));
    });

    test('AmneziaWG nodes alone survive libXray finding nothing', () async {
      final rows = await XrayShareReader().parseShareText(
        'awg://${base64Url.encode(utf8.encode(_conf))}#Only\nnot a link',
        convert: (_, _) async => throw StateError('no links'),
        validate: (_) async => '',
      );
      expect(rows.map((row) => row.name.value), ['Only']);
    });
  });

  group('runtime', () {
    test('a peer on loopback counts as a local server', () {
      Map<String, dynamic> node(String endpoint) => {
        'protocol': 'amneziawg',
        'settings': {
          'address': ['10.0.0.2/32'],
          'peers': [
            {'endpoint': endpoint},
          ],
        },
      };
      expect(outboundDialsLoopback(node('127.0.0.1:51820')), isTrue);
      expect(outboundDialsLoopback(node('[::1]:51820')), isTrue);
      expect(outboundDialsLoopback(node('1.2.3.4:51820')), isFalse);
      expect(outboundDialsLoopback(node('localhost:1')), isTrue);
    });

    test('Fragment leaves WireGuard and AmneziaWG direct', () {
      final entries = XrayFragment.connectEntries(
        [
          AmneziaWG.fromConf(_conf, name: 'awg')!,
          {
            'tag': 'v',
            'protocol': 'vless',
            'settings': {'address': 'node.example', 'port': 443},
          },
        ],
        [XrayFragment.defaultOutbound()],
      );
      expect(entries.first, isNot(contains('streamSettings')));
      expect(outboundDialerProxy(entries.last), XrayFragment.tag);
    });
  });
}
