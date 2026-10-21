import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
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

  group('kill switch', () {
    PlatformPolicy withDesktop(
      PlatformPolicy policy,
      Map<String, Object> values,
    ) {
      final json = policy.toJson();
      json['desktop'] = {...json['desktop'] as Map, ...values};
      return PlatformPolicy.fromJson(json);
    }

    bool same(PlatformPolicy a, PlatformPolicy b) =>
        PolicyEditorService.sameRuntime(a, b, ConnectionPlatform.windows);

    test('is on by default, local network allowed, not strict', () {
      final policy = PlatformPolicy.defaults();
      expect(policy.killSwitchEnabled, isTrue);
      expect(policy.killSwitchAllowsLan, isTrue);
      expect(policy.killSwitchStrict, isFalse);
      // Stored before the kill switch existed: it is on after the update.
      final legacy = policy.toJson();
      legacy['desktop'] = {'runMode': 'tun', 'proxyPort': 10820};
      expect(PlatformPolicy.fromJson(legacy).killSwitchEnabled, isTrue);
    });

    test('its switches change the runtime where they apply', () {
      final tun = PlatformPolicy.defaults();
      expect(same(tun, withDesktop(tun, {'killSwitch': false})), isFalse);
      expect(same(tun, withDesktop(tun, {'killSwitchStrict': true})), isFalse);
      expect(same(tun, withDesktop(tun, {'killSwitchLan': false})), isFalse);

      final proxy = tun.withDesktopRunMode(DesktopRunMode.systemProxy);
      // Proxy mode has no filters, so no local network to allow.
      expect(same(proxy, withDesktop(proxy, {'killSwitchLan': false})), isTrue);
      expect(same(proxy, withDesktop(proxy, {'killSwitch': false})), isFalse);

      // Its settings are inert while it is off.
      final off = withDesktop(tun, {'killSwitch': false});
      expect(same(off, withDesktop(off, {'killSwitchStrict': true})), isTrue);
    });
  });

  group('system proxy exceptions', () {
    PlatformPolicy withBypass(PlatformPolicy policy, List<String> hosts) {
      final json = policy.toJson();
      json['desktop'] = {...json['desktop'] as Map, 'proxyBypass': hosts};
      return PlatformPolicy.fromJson(json);
    }

    test('default to none and keep older stored policies valid', () {
      expect(PlatformPolicy.defaults().systemProxyBypass, isEmpty);
      final legacy = PlatformPolicy.defaults().toJson();
      (legacy['desktop'] as Map).remove('proxyBypass');
      expect(PlatformPolicy.fromJson(legacy).systemProxyBypass, isEmpty);
    });

    test('take domains, wildcards and addresses', () {
      const hosts = [
        'example.com',
        '*.example.com',
        'intranet',
        '192.168.50.*',
        '[::1]',
        'пример.рф',
      ];
      expect(
        withBypass(PlatformPolicy.defaults(), hosts).systemProxyBypass,
        hosts,
      );
    });

    test('reject what would break or empty the list', () {
      for (final host in [
        '',
        'a b.com',
        'a;b.com',
        'a,b.com',
        "it's.com",
        r'back\slash',
        '<local>',
        '*',
        '*.*',
      ]) {
        expect(
          PlatformPolicy.validSystemProxyBypass(host),
          isFalse,
          reason: host,
        );
        expect(
          () => withBypass(PlatformPolicy.defaults(), [host]),
          throwsFormatException,
          reason: host,
        );
      }
      expect(
        () => withBypass(
          PlatformPolicy.defaults(),
          List.filled(PlatformPolicy.maxSystemProxyBypass + 1, 'a.com'),
        ),
        throwsFormatException,
      );
    });

    test('change the runtime only in proxy mode', () {
      final tun = PlatformPolicy.defaults();
      final proxy = tun.withDesktopRunMode(DesktopRunMode.systemProxy);
      bool same(PlatformPolicy a, PlatformPolicy b) =>
          PolicyEditorService.sameRuntime(a, b, ConnectionPlatform.windows);

      expect(same(proxy, withBypass(proxy, ['example.com'])), isFalse);
      expect(same(tun, withBypass(tun, ['example.com'])), isTrue);
    });

    test('the editor drops blank rows and repeats before saving', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final coordinator = ConnectionCoordinator(database: db);
      addTearDown(() async {
        coordinator.dispose();
        await db.close();
      });
      final service = PolicyEditorService(
        coordinator: coordinator,
        platform: ConnectionPlatform.linux,
      );
      final draft = PolicyEditorDraft(ConnectionConfiguration());
      draft.policy['xrayOutboundInterfaceName'] = 'eth0';
      draft.policy['desktop']['proxyBypass'] = [
        ' example.com ',
        '',
        'EXAMPLE.com',
        '*.lan',
      ];
      expect(service.prepare(draft).policy.systemProxyBypass, [
        'example.com',
        '*.lan',
      ]);
    });
  });
}
