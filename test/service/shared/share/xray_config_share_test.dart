import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/share/xray_config_share.dart';
import 'package:onexray/service/shared/share/xray_share_reader.dart';

import '../../connect/compiler_test.dart' show catalog, options;

Map<String, dynamic> _vless(String tag, {Map<String, dynamic>? mux}) => {
  'tag': tag,
  'protocol': 'vless',
  'settings': {
    'vnext': [
      {
        'address': 'node.example',
        'port': 443,
        'users': [
          {'id': '00000000-0000-4000-8000-000000000000', 'encryption': 'none'},
        ],
      },
    ],
  },
  'streamSettings': {'network': 'ws', 'security': 'tls'},
  'mux': ?mux,
};

Map<String, dynamic> _config(String remarks, List<Map<String, dynamic>> out) =>
    {
      'remarks': remarks,
      'inbounds': [
        {'tag': 'socks', 'port': 10808, 'protocol': 'socks'},
      ],
      'outbounds': [
        ...out,
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
      ],
      'routing': {
        'rules': [
          {
            'outboundTag': 'direct',
            'domain': ['geosite:private'],
          },
        ],
      },
    };

void main() {
  const mux = {
    'enabled': true,
    'concurrency': 8,
    'xudpConcurrency': 16,
    'xudpProxyUDP443': 'reject',
  };

  test('an array of client configs becomes nodes named by remarks', () {
    final outbounds = xrayConfigOutbounds(
      jsonEncode([
        _config('🏳️ Home · WebSocket + Mux', [_vless('proxy', mux: mux)]),
        _config('Home · port 2053', [_vless('proxy')]),
      ]),
    )!;
    expect(outbounds.map((outbound) => outbound['tag']), [
      '🏳️ Home · WebSocket + Mux',
      'Home · port 2053',
    ]);
    // What links cannot carry survives.
    expect(outbounds.first['mux'], mux);
    expect(outbounds.last.containsKey('mux'), isFalse);
    expect(outbounds.first['streamSettings'], {
      'network': 'ws',
      'security': 'tls',
    });
  });

  test('several proxies of one config keep their own tags', () {
    final outbounds = xrayConfigOutbounds(
      jsonEncode([
        _config('Auto', [_vless('nl'), _vless('de')]),
        _config('', [_vless('fi')]),
      ]),
    )!;
    expect(outbounds.map((outbound) => outbound['tag']), [
      'Auto · nl',
      'Auto · de',
      'fi',
    ]);
  });

  test('an outbound that needs another one of its config is skipped', () {
    final chained = _vless('exit')
      ..['streamSettings'] = {
        'network': 'tcp',
        'sockopt': {'dialerProxy': 'entry'},
      };
    final outbounds = xrayConfigOutbounds(
      jsonEncode([
        _config('Chain', [_vless('entry'), chained]),
      ]),
    )!;
    expect(outbounds.map((outbound) => outbound['tag']), ['Chain']);
  });

  test('one client config is read; bare outbounds and links are not', () {
    expect(
      xrayConfigOutbounds(jsonEncode(_config('Single', [_vless('proxy')])))!
          .single['tag'],
      'Single',
    );
    expect(
      xrayConfigOutbounds(
        jsonEncode({
          'outbounds': [_vless('proxy')],
        }),
      ),
      isNull,
    );
    expect(xrayConfigOutbounds('vless://id@node.example:443#Node'), isNull);
    expect(xrayConfigOutbounds('[not json'), isNull);
    expect(xrayConfigOutbounds('[1, "two"]'), isNull);
  });

  test('each node must build in the core and keeps its mux', () async {
    final checked = <String>[];
    final rows = await XrayShareReader().parseShareText(
      jsonEncode([
        _config('Home', [_vless('proxy', mux: mux)]),
        _config('Broken', [_vless('proxy')]),
      ]),
      // libXray's link conversion would drop mux; it must not be used.
      convert: (_, _) async => fail('JSON configs are not share links'),
      validate: (xrayJson) async {
        final tag = jsonDecode(xrayJson)['outbounds'][0]['tag'] as String;
        checked.add(tag);
        return tag == 'Broken' ? 'unknown transport' : '';
      },
    );
    expect(checked, ['Home', 'Broken']);
    expect(rows.single.name.value, 'Home');
    final saved = jsonDecode(
      utf8.decode(base64Decode(rows.single.data.value!)),
    );
    expect(saved['outbounds'].single['mux'], mux);
  });

  test('the node keeps its mux in the running config', () {
    final node = xrayConfigOutbounds(
      jsonEncode([
        _config('Home', [_vless('proxy', mux: mux)]),
      ]),
    )!.single;
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(trafficMode: TrafficMode.allVpn),
      entries: [ResolvedServer(id: 1, sourceId: 1, outbound: node)],
      regions: catalog,
      options: options(),
    ).config;
    final entry = (config['outbounds'] as List).singleWhere(
      (outbound) => outbound['tag'] == 'app-entry-0',
    );
    expect(entry['mux'], mux);
  });
}
