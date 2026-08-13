import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/minewire/link.dart';
import 'package:onexray/service/share/xray_share_reader.dart';

void main() {
  group('MinewireLink.parse', () {
    test('reads a full link', () {
      final link = MinewireLink.parse(
        'mw://secret@vsp.example.ru:25565?mode=fast&proxy=socks5#Node',
      );
      expect(link, isNotNull);
      expect(link!.password, 'secret');
      expect(link.host, 'vsp.example.ru');
      expect(link.port, 25565);
      expect(link.mode, 'fast');
      expect(link.proxyType, 'socks5');
      expect(link.name, 'Node');
    });

    test('decodes a percent-encoded name', () {
      final link = MinewireLink.parse(
        'mw://p@host:1:1'.replaceAll(':1:1', ':25565') +
            '#%D0%9E%D1%81%D0%BE%D0%B1%D0%B5%D0%BD%D0%BD%D1%8B%D0%B9',
      );
      expect(link?.name, 'Особенный');
    });

    test('falls back to defaults without query and fragment', () {
      final link = MinewireLink.parse('mw://p@host:25565');
      expect(link?.mode, MinewireLink.defaultMode);
      expect(link?.proxyType, MinewireLink.defaultProxyType);
      expect(link?.name, MinewireLink.defaultName);
    });

    test('rejects links without password, host or port', () {
      expect(MinewireLink.parse('mw://host:25565'), isNull);
      expect(MinewireLink.parse('mw://p@:25565'), isNull);
      expect(MinewireLink.parse('mw://p@host'), isNull);
      expect(MinewireLink.parse('vless://p@host:443'), isNull);
    });

    test('survives a round trip through json', () {
      const original = MinewireLink(
        password: 'p',
        host: 'host',
        port: 25565,
        name: 'Node',
        mode: 'stable',
        proxyType: 'socks5',
      );
      final restored = MinewireLink.fromJson(original.toJson());
      expect(restored?.password, original.password);
      expect(restored?.host, original.host);
      expect(restored?.port, original.port);
      expect(restored?.mode, original.mode);
    });

    test('quotes values in the generated yaml', () {
      const link = MinewireLink(
        password: r'pa"ss',
        host: 'host',
        port: 25565,
        name: 'Node',
      );
      final yaml = link.yaml(1081);
      expect(yaml, contains('local_port: "127.0.0.1:1081"'));
      expect(yaml, contains('server_address: "host:25565"'));
      expect(yaml, contains(r'password: "pa\"ss"'));
    });
  });

  group('XrayShareReader.splitMinewireLinks', () {
    test('pulls minewire links out and keeps the rest intact', () {
      const text = 'vless://a@h:443#One\n'
          'mw://secret@host:25565?mode=fast#Mine\n'
          'trojan://b@h:443#Two';
      final split = XrayShareReader.splitMinewireLinks(text);
      expect(split.minewire, hasLength(1));
      expect(split.minewire.single.name, 'Mine');
      expect(split.rest, isNot(contains('mw://')));
      expect(split.rest, contains('vless://'));
      expect(split.rest, contains('trojan://'));
    });

    test('handles a base64 encoded subscription body', () {
      const text = 'dmxlc3M6Ly9hQGg6NDQzI09uZQptdzovL3NlY3JldEBob3N0OjI1NTY1I01pbmU=';
      final split = XrayShareReader.splitMinewireLinks(text);
      expect(split.minewire, hasLength(1));
      expect(split.minewire.single.host, 'host');
      expect(split.rest, contains('vless://'));
    });

    test('leaves text untouched when there is nothing to split', () {
      const text = 'vless://a@h:443#One';
      final split = XrayShareReader.splitMinewireLinks(text);
      expect(split.minewire, isEmpty);
      expect(split.rest, text);
    });
  });
}
