import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/settings.dart';

void main() {
  test('desktop policy defaults to TUN with a port clear of 10808/10809', () {
    final policy = PlatformPolicy.defaults();
    expect(policy.desktopRunMode, DesktopRunMode.tun);
    expect(policy.systemProxyPort, 10820);
    expect(policy.usesSystemProxy(ConnectionPlatform.windows), isFalse);
  });

  test('proxy mode is recognized only on desktop platforms', () {
    final policy = PlatformPolicy.defaults().withDesktopRunMode(
      DesktopRunMode.systemProxy,
    );
    expect(policy.usesSystemProxy(ConnectionPlatform.windows), isTrue);
    expect(policy.usesSystemProxy(ConnectionPlatform.linux), isTrue);
    expect(policy.usesSystemProxy(ConnectionPlatform.android), isFalse);
    expect(policy.usesSystemProxy(ConnectionPlatform.macos), isFalse);
  });

  test('stored policies without the desktop group keep working', () {
    final legacy = PlatformPolicy.defaults().toJson()..remove('desktop');
    final policy = PlatformPolicy.fromJson(legacy);
    expect(policy.desktopRunMode, DesktopRunMode.tun);
  });

  test('invalid run modes and ports are rejected', () {
    Map<String, dynamic> withDesktop(Map<String, dynamic> desktop) => {
      ...PlatformPolicy.defaults().toJson(),
      'desktop': desktop,
    };
    for (final desktop in <Map<String, dynamic>>[
      {'runMode': 'socks'},
      {'proxyPort': 0},
      {'proxyPort': 65536},
      {'proxyPort': '10820'},
    ]) {
      expect(
        () => PlatformPolicy.fromJson(withDesktop(desktop)),
        throwsFormatException,
        reason: '$desktop',
      );
    }
  });

  test('switching mode, or the port in proxy mode, changes the runtime', () {
    final tun = PlatformPolicy.defaults();
    final proxy = tun.withDesktopRunMode(DesktopRunMode.systemProxy);
    bool same(PlatformPolicy a, PlatformPolicy b) =>
        PolicyEditorService.sameRuntime(a, b, ConnectionPlatform.windows);

    expect(same(tun, proxy), isFalse);

    PlatformPolicy withPort(PlatformPolicy policy, int port) {
      final json = policy.toJson();
      json['desktop'] = {...json['desktop'] as Map, 'proxyPort': port};
      return PlatformPolicy.fromJson(json);
    }

    expect(same(proxy, withPort(proxy, 10900)), isFalse);
    // The port is inert while TUN runs.
    expect(same(tun, withPort(tun, 10900)), isTrue);
  });
}
