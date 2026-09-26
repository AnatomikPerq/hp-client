import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/settings.dart';

const _proxyPort = 10820;

RuntimeOptions _proxyOptions(
  ConnectionPlatform platform, {
  String interfaceName = '',
}) => RuntimeOptions(
  platform: platform,
  windowsMode: WindowsMode.exe,
  sessionDirectory: '/unused-session',
  metricsPort: 18186,
  socksPort: _proxyPort,
  interfaceName: interfaceName,
  systemProxy: true,
);

ResolvedServer _node(int id) => ResolvedServer(
  id: id,
  sourceId: 1,
  outbound: {
    'tag': 'node',
    'protocol': 'socks',
    'settings': {'address': 'node.test', 'port': 12345},
  },
);

const _regions = RegionCatalog.empty();

void main() {
  for (final platform in [
    ConnectionPlatform.windows,
    ConnectionPlatform.linux,
  ]) {
    test('$platform proxy mode serves tunIn on loopback without TUN', () {
      final config = ConnectionCompiler.compile(
        settings: ConnectionSettings(trafficMode: TrafficMode.allVpn),
        entries: [_node(1)],
        regions: _regions,
        // The interface stays in the policy for TUN mode but is not used.
        options: _proxyOptions(platform, interfaceName: 'Ethernet'),
      ).config;

      final inbound = (config['inbounds'] as List).single as Map;
      expect(inbound['tag'], 'tunIn');
      expect(inbound['protocol'], 'socks');
      expect(inbound['listen'], '127.0.0.1');
      expect(inbound['port'], '$_proxyPort');
      expect(inbound['settings']['auth'], 'noauth');

      // No tunnel to escape: outbounds follow OS routing, including another
      // VPN the user may run, instead of pinning the physical interface.
      for (final outbound in config['outbounds'] as List) {
        final sockopt = outbound['streamSettings']?['sockopt'] as Map?;
        expect(
          sockopt?.containsKey('interface') ?? false,
          isFalse,
          reason: '${outbound['tag']}',
        );
      }
    });

    test('$platform proxy mode needs no outbound interface', () {
      expect(() => _proxyOptions(platform), returnsNormally);
    });

    test('$platform Raw proxy mode turns tunIn into the loopback inbound', () {
      final config = ConnectionCompiler.compile(
        settings: ConnectionSettings(expert: true, rawId: 1),
        entries: const [],
        raw: {
          'inbounds': [
            {
              'tag': 'tunIn',
              'protocol': 'tun',
              'settings': {'name': 'Mine'},
              'sniffing': {'enabled': false},
            },
          ],
          'outbounds': [
            {'protocol': 'freedom'},
          ],
          'dns': {
            // A local DNS URL is fine without a required interface.
            'servers': ['https+local://1.1.1.1/dns-query'],
          },
        },
        regions: _regions,
        options: _proxyOptions(platform),
      ).config;
      final inbound = (config['inbounds'] as List).single as Map;
      expect(inbound['protocol'], 'socks');
      expect(inbound['listen'], '127.0.0.1');
      expect(inbound['port'], '$_proxyPort');
      expect(inbound['sniffing'], {'enabled': false});
    });

    test('$platform Raw inbounds may not take the proxy port', () {
      expect(
        () => ConnectionCompiler.compile(
          settings: ConnectionSettings(expert: true, rawId: 1),
          entries: const [],
          raw: {
            'inbounds': [
              {'tag': 'mine', 'protocol': 'socks', 'port': _proxyPort},
            ],
            'outbounds': [
              {'protocol': 'freedom'},
            ],
          },
          regions: _regions,
          options: _proxyOptions(platform),
        ),
        throwsFormatException,
      );
    });
  }

  test('proxy mode is refused where the platform owns the VPN', () {
    for (final platform in [
      ConnectionPlatform.android,
      ConnectionPlatform.ios,
      ConnectionPlatform.macos,
    ]) {
      expect(() => _proxyOptions(platform), throwsFormatException);
    }
  });
}
