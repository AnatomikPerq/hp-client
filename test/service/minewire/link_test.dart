import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/minewire/link.dart';
import 'package:onexray/service/minewire/share.dart';
import 'package:onexray/service/shared/share/xray_share_reader.dart';
import 'package:onexray/service/shared/xray/validation.dart';

void main() {
  group('MinewireLink', () {
    test('parses a full link', () {
      final link = MinewireLink.parse(
        'mw://p%40ss%3Aword@mw.example.org:25565?mode=realistic#My%20node',
      )!;
      expect(link.password, 'p@ss:word');
      expect(link.host, 'mw.example.org');
      expect(link.port, 25565);
      expect(link.mode, 'realistic');
      expect(link.name, 'My node');
    });

    test('defaults the mode and the name', () {
      final link = MinewireLink.parse('mw://secret@1.2.3.4:25565')!;
      expect(link.mode, MinewireLink.defaultMode);
      expect(link.name, MinewireLink.defaultName);
    });

    test('rejects malformed links instead of failing an import', () {
      for (final raw in [
        'mw://@host:25565',
        'mw://secret@host',
        'mw://secret@:25565',
        'mw://secret@host:0',
        'mw://secret@host:25565?mode=turbo',
        'mw://%E0%A4%A@host:25565',
        'vless://uuid@host:443',
        '',
      ]) {
        expect(MinewireLink.parse(raw), isNull, reason: raw);
      }
    });

    test('outbound and share link round-trip', () {
      final link = MinewireLink.parse(
        'mw://s3cr%2Ft@node.test:25566?mode=fast#Узел',
      )!;
      final outbound = link.toOutbound();
      expect(outbound['protocol'], 'minewire');
      expect(outbound['tag'], 'Узел');
      final back = MinewireLink.fromOutbound(outbound)!;
      expect(back.password, 's3cr/t');
      final again = MinewireLink.parse(back.toShareLink())!;
      expect(again.toOutbound(), outbound);
    });

    test('an invalid stored outbound is not treated as runnable', () {
      expect(
        MinewireLink.fromOutbound({
          'protocol': 'minewire',
          'settings': {'address': 'h', 'port': 1},
        }),
        isNull,
      );
      expect(MinewireLink.fromOutbound({'protocol': 'vless'}), isNull);
    });
  });

  group('share text', () {
    const mw = 'mw://secret@mw.test:25565#A';
    const vless = 'vless://uuid@v.test:443?security=tls#B';

    test('minewire lines are taken out before libXray', () {
      final split = splitMinewireLinks('$vless\n$mw\n');
      expect(split.links.single.name, 'A');
      expect(split.rest.trim(), vless);
    });

    test('a base64 subscription body is looked into', () {
      final body = base64.encode(utf8.encode('$mw\n$vless'));
      final split = splitMinewireLinks(body);
      expect(split.links.single.host, 'mw.test');
      expect(split.rest, vless);
    });

    test('text without minewire passes through untouched', () {
      final body = base64.encode(utf8.encode(vless));
      expect(splitMinewireLinks(body).rest, body);
    });

    test('age-encrypted text is left to libXray', () {
      const armor =
          '-----BEGIN AGE ENCRYPTED FILE-----\nabc\n-----END AGE ENCRYPTED FILE-----';
      expect(splitMinewireLinks(armor).rest, armor);
    });

    test('minewire-only text never calls libXray', () async {
      var calls = 0;
      final rows = await XrayShareReader().parseShareText(
        mw,
        convert: (_, _) async {
          calls++;
          return [];
        },
      );
      expect(calls, 0);
      expect(rows.single.name.value, 'A');
    });

    test('libXray failing on the rest keeps the minewire nodes', () async {
      final rows = await XrayShareReader().parseShareText(
        '$mw\n# comment',
        convert: (_, _) async => throw StateError('no valid outbound'),
      );
      expect(rows, hasLength(1));
    });

    test('libXray failing without minewire nodes still fails', () async {
      await expectLater(
        XrayShareReader().parseShareText(
          vless,
          convert: (_, _) async => throw StateError('no valid outbound'),
        ),
        throwsStateError,
      );
    });
  });

  test('validation checks a minewire node in its runtime socks shape', () {
    final outbound = MinewireLink.parse('mw://secret@mw.test:25565#A')!
        .toOutbound();
    final config = jsonDecode(XrayValidation.nodes([outbound])) as Map;
    final projected = (config['outbounds'] as List).single as Map;
    expect(projected['protocol'], 'socks');
    expect(projected['tag'], 'A');
    expect(jsonEncode(config), isNot(contains('secret')));
  });
}
