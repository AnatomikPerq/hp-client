import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/settings.dart';

RuntimeOptions _options(ConnectionPlatform platform) => RuntimeOptions(
  platform: platform,
  windowsMode: WindowsMode.exe,
  sessionDirectory: '/unused-session',
  metricsPort: 18186,
  socksPort: 18187,
  interfaceName: 'Ethernet',
);

Map<String, dynamic> _compile(
  Map<String, dynamic> raw, {
  ConnectionPlatform platform = ConnectionPlatform.windows,
}) => ConnectionCompiler.compile(
  settings: ConnectionSettings(expert: true, rawId: 1),
  entries: const [],
  raw: raw,
  regions: const RegionCatalog.empty(),
  options: _options(platform),
).config;

Map<String, dynamic> _raw(List<Map<String, dynamic>> inbounds) => {
  'inbounds': inbounds,
  'outbounds': [
    {'tag': 'out', 'protocol': 'freedom'},
  ],
};

Map<String, dynamic> _inbound(Map<String, dynamic> config, String tag) =>
    (config['inbounds'] as List).cast<Map<String, dynamic>>().singleWhere(
      (inbound) => inbound['tag'] == tag,
    );

void main() {
  test('an inbound without listen stays on this computer', () {
    final config = _compile(
      _raw([
        {'tag': 'share', 'protocol': 'socks', 'port': 1080},
      ]),
    );
    expect(_inbound(config, 'share')['listen'], '127.0.0.1');
  });

  test('an open proxy for the local network is refused', () {
    for (final inbound in [
      {'tag': 'a', 'protocol': 'socks', 'listen': '0.0.0.0', 'port': 1080},
      {
        'tag': 'b',
        'protocol': 'socks',
        'listen': '192.168.1.10',
        'port': 1080,
        'settings': {'auth': 'noauth'},
      },
      {'tag': 'c', 'protocol': 'http', 'listen': '::', 'port': 8080},
    ]) {
      expect(
        () => _compile(_raw([inbound])),
        throwsFormatException,
        reason: '$inbound',
      );
    }
  });

  test('outside listeners with authentication or own access stay', () {
    final config = _compile(
      _raw([
        {
          'tag': 'lan',
          'protocol': 'socks',
          'listen': '0.0.0.0',
          'port': 1080,
          'settings': {
            'auth': 'password',
            'accounts': [
              {'user': 'u', 'pass': 'p'},
            ],
          },
        },
        {
          'tag': 'forward',
          'protocol': 'dokodemo-door',
          'listen': '0.0.0.0',
          'port': 5353,
        },
        {
          'tag': 'local',
          'protocol': 'http',
          'listen': '127.0.0.1',
          'port': 8080,
        },
      ]),
    );
    expect(_inbound(config, 'lan')['listen'], '0.0.0.0');
    expect(_inbound(config, 'forward')['listen'], '0.0.0.0');
  });

  test('only Xray options reach the Core environment', () {
    final config = _compile({
      ..._raw(const []),
      'env': {
        'xray.buf.readv': 'enable',
        'GODEBUG': 'x509ignoreCN=0',
        'HTTP_PROXY': 'http://attacker.test:8080',
      },
    });
    final env = config['env'] as Map;
    expect(env.containsKey('xray.buf.readv'), isTrue);
    expect(env.containsKey('GODEBUG'), isFalse);
    expect(env.containsKey('HTTP_PROXY'), isFalse);
  });

  test('a desktop Core never exposes a Raw API', () {
    Map<String, dynamic> withApi() => {
      ..._raw([
        {
          'tag': 'api-in',
          'protocol': 'dokodemo-door',
          'listen': '127.0.0.1',
          'port': 10085,
          'settings': {'address': '127.0.0.1'},
        },
        {'tag': 'socks-in', 'protocol': 'socks', 'port': 1080},
      ]),
      'api': {
        'tag': 'api',
        'services': ['HandlerService'],
      },
      'routing': {
        'rules': [
          {
            'inboundTag': ['api-in'],
            'outboundTag': 'api',
          },
          {
            'inboundTag': ['socks-in'],
            'outboundTag': 'out',
          },
        ],
      },
    };

    final desktop = _compile(withApi());
    expect(desktop.containsKey('api'), isFalse);
    expect(
      (desktop['routing']['rules'] as List).any(
        (rule) => rule['outboundTag'] == 'api',
      ),
      isFalse,
    );
    expect(
      (desktop['inbounds'] as List).map((inbound) => inbound['tag']),
      isNot(contains('api-in')),
    );
    expect(
      (desktop['inbounds'] as List).map((inbound) => inbound['tag']),
      contains('socks-in'),
    );

    // Mobile Cores run inside the sandboxed App process.
    final mobile = _compile(withApi(), platform: ConnectionPlatform.android);
    expect(mobile.containsKey('api'), isTrue);
  });
}
