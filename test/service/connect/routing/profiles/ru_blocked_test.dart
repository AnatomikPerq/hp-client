import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/service/connect/routing/profiles/catalog.dart';
import 'package:onexray/service/connect/routing/profiles/ru_blocked.dart';
import 'package:path/path.dart' as p;

/// Reads (field, value) pairs of one protobuf message.
List<(int, Object)> _fields(List<int> bytes) {
  final result = <(int, Object)>[];
  var offset = 0;
  int varint() {
    var value = 0;
    var shift = 0;
    while (true) {
      final byte = bytes[offset++];
      value |= (byte & 0x7f) << shift;
      if (byte < 0x80) return value;
      shift += 7;
    }
  }

  while (offset < bytes.length) {
    final key = varint();
    if (key & 7 == 0) {
      result.add((key >> 3, varint()));
    } else {
      expect(key & 7, 2);
      final length = varint();
      result.add((key >> 3, bytes.sublist(offset, offset + length)));
      offset += length;
    }
  }
  return result;
}

/// Bytes as text, so records of fields compare by value.
List<(int, Object)> _plain(List<(int, Object)> fields, {bool text = true}) => [
  for (final (field, value) in fields)
    (
      field,
      value is List<int>
          ? (text ? utf8.decode(value) : value.join('.'))
          : value,
    ),
];

String _domains(int count, {String prefix = 'site'}) =>
    [for (var i = 0; i < count; i++) 'domain:$prefix$i.example'].join('\n');

String _ips(int count) =>
    [for (var i = 0; i < count; i++) '10.${i ~/ 256}.${i % 256}.0/24']
        .join('\n');

void main() {
  test('domain lines become one geosite category in Go field order', () {
    final domains = RuBlockedEncoding.parseDomains(
      [
        '# comment',
        'domain:Example.com',
        'full:www.example.org',
        'keyword:torrent',
        'regexp:^a.+\\.example\$',
        'plain.example',
        'domain:example.com',
        'unknown:value',
        'domain:with space',
        '',
      ].join('\n'),
    );
    expect(domains, [
      (2, 'example.com'),
      (3, 'www.example.org'),
      (0, 'torrent'),
      (1, '^a.+\\.example\$'),
      (2, 'plain.example'),
    ]);
    final encoded = RuBlockedEncoding.sites('RU-BLOCKED', domains);
    expect(encoded.count, 5);
    final list = _fields(encoded.bytes);
    expect(list.single.$1, 1);
    final site = _fields(list.single.$2 as List<int>);
    expect(utf8.decode(site.first.$2 as List<int>), 'RU-BLOCKED');
    final first = _plain(_fields(site[1].$2 as List<int>));
    expect(first, [(1, 2), (2, 'example.com')]);
    // A substring has the default type, which proto3 leaves out.
    final keyword = _plain(_fields(site[3].$2 as List<int>));
    expect(keyword, [(2, 'torrent')]);
  });

  test('address lines become one geoip category', () {
    final cidrs = RuBlockedEncoding.parseIps(
      [
        '1.1.1.1/32',
        '203.0.113.0/24',
        '203.0.113.0/24',
        '2001:db8::/32',
        '198.51.100.7',
        '10.0.0.0/33',
        'not-an-address',
      ].join('\n'),
    );
    expect(cidrs.map((value) => value.$2), [32, 24, 32, 32]);
    expect(cidrs[2].$1, hasLength(16));
    final encoded = RuBlockedEncoding.ips('RU-BLOCKED', cidrs);
    final geoip = _fields(_fields(encoded.bytes).single.$2 as List<int>);
    expect(utf8.decode(geoip.first.$2 as List<int>), 'RU-BLOCKED');
    expect(_plain(_fields(geoip[1].$2 as List<int>), text: false), [
      (1, '1.1.1.1'),
      (2, 32),
    ]);
  });

  group('installed lists', () {
    late Directory root;
    late Directory data;
    late Map<String, List<int>> assets;
    late List<String> counted;
    late List<(String, String?)> requests;
    late Map<String, ({int status, String? etag, String body})> responses;
    var now = DateTime.utc(2026, 10, 21, 12);

    RuBlockedList list() => RuBlockedList(
      directory: () => data.path,
      loadAsset: (name) async {
        final bytes = assets[name];
        if (bytes == null) throw FlutterError('Unable to load asset: $name');
        return ByteData.sublistView(Uint8List.fromList(bytes));
      },
      withFiles: <T>(Future<T> Function() action) => action(),
      count: (directory, name, type) async {
        expect(p.basename(directory), '.hp-ru-blocked');
        expect(File(p.join(directory, '$name.dat')).existsSync(), isTrue);
        counted.add('$name:$type');
        return '';
      },
      fetch: (url, etag) async {
        requests.add((url, etag));
        return responses[url]!;
      },
      now: () => now,
    );

    void bundle({required int fetchedAt, int domains = 1200}) {
      assets = {
        '${RuBlockedList.bundleDir}/manifest.json': utf8.encode(
          jsonEncode({
            'fetchedAt': fetchedAt,
            'domains': {'etag': 'W/"d1"'},
            'ips': {'etag': 'W/"i1"'},
          }),
        ),
        '${RuBlockedList.bundleDir}/domains.txt.gz': gzip.encode(
          utf8.encode(_domains(domains)),
        ),
        '${RuBlockedList.bundleDir}/ips.txt.gz': gzip.encode(
          utf8.encode(_ips(1100)),
        ),
      };
    }

    File file(String name) => File(p.join(data.path, name));

    setUp(() {
      root = Directory.systemTemp.createTempSync('ru-blocked-');
      data = Directory(p.join(root.path, 'dat'));
      assets = {};
      counted = [];
      requests = [];
      responses = {};
      now = DateTime.utc(2026, 10, 21, 12);
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('the bundled copy installs once and checks both files', () async {
      bundle(fetchedAt: 1792600000);
      await list().ensureInstalled();
      expect(counted, ['ru-blocked-domains:domain', 'ru-blocked-ips:ip']);
      expect(
        file(TrafficProfiles.ruBlockedDomainFile).lengthSync(),
        isPositive,
      );
      expect(
        Directory(p.join(root.path, '.hp-ru-blocked')).existsSync(),
        isFalse,
      );
      final status = (await list().status())!;
      expect(status.domainCount, 1200);
      expect(status.ipCount, 1100);
      expect(status.bundled, isTrue);
      expect(status.domainsEtag, 'W/"d1"');
      await list().ensureInstalled();
      expect(counted, hasLength(2));
      // A newer App ships a newer snapshot.
      bundle(fetchedAt: 1792700000, domains: 1300);
      await list().ensureInstalled();
      expect((await list().status())!.domainCount, 1300);
    });

    test('nothing bundled and nothing installed is a clear failure', () async {
      await expectLater(list().ensureInstalled(), throwsA(isA<AppFailure>()));
      expect(await list().installed(), isFalse);
    });

    test('unchanged lists cost conditional requests only', () async {
      bundle(fetchedAt: 1792600000);
      await list().ensureInstalled();
      final before = file(TrafficProfiles.ruBlockedDomainFile)
          .readAsBytesSync();
      responses = {
        RuBlockedList.domainsUrl: (status: 304, etag: 'W/"d1"', body: ''),
        RuBlockedList.ipsUrl: (status: 304, etag: 'W/"i1"', body: ''),
      };
      expect(await list().update(), RuBlockedUpdate.unchanged);
      expect(requests, [
        (RuBlockedList.domainsUrl, 'W/"d1"'),
        (RuBlockedList.ipsUrl, 'W/"i1"'),
      ]);
      expect(
        file(TrafficProfiles.ruBlockedDomainFile).readAsBytesSync(),
        before,
      );
      final status = (await list().status())!;
      expect(status.checkedAt, now);
      expect(status.bundled, isTrue);
    });

    test('a changed list replaces only its own file', () async {
      bundle(fetchedAt: 1792600000);
      await list().ensureInstalled();
      final domains = file(TrafficProfiles.ruBlockedDomainFile)
          .readAsBytesSync();
      counted.clear();
      responses = {
        RuBlockedList.domainsUrl: (status: 304, etag: 'W/"d1"', body: ''),
        RuBlockedList.ipsUrl: (status: 200, etag: 'W/"i2"', body: _ips(1500)),
      };
      expect(await list().update(), RuBlockedUpdate.updated);
      expect(counted, ['ru-blocked-ips:ip']);
      expect(
        file(TrafficProfiles.ruBlockedDomainFile).readAsBytesSync(),
        domains,
      );
      final status = (await list().status())!;
      expect(status.domainCount, 1200);
      expect(status.ipCount, 1500);
      expect(status.ipsEtag, 'W/"i2"');
      expect(status.domainsEtag, 'W/"d1"');
      expect(status.bundled, isFalse);
      expect(status.fetchedAt, now);
    });

    test('a short list is refused and the installed copy stays', () async {
      bundle(fetchedAt: 1792600000);
      await list().ensureInstalled();
      final ips = file(TrafficProfiles.ruBlockedIpFile).readAsBytesSync();
      responses = {
        RuBlockedList.domainsUrl: (status: 304, etag: 'W/"d1"', body: ''),
        RuBlockedList.ipsUrl: (status: 200, etag: 'W/"i3"', body: '<html>'),
      };
      await expectLater(list().update(), throwsA(isA<AppFailure>()));
      expect(file(TrafficProfiles.ruBlockedIpFile).readAsBytesSync(), ips);
      expect((await list().status())!.ipsEtag, 'W/"i1"');
    });

    test('without a bundle the first update downloads both lists', () async {
      responses = {
        RuBlockedList.domainsUrl: (
          status: 200,
          etag: 'W/"d9"',
          body: _domains(1100),
        ),
        RuBlockedList.ipsUrl: (status: 200, etag: 'W/"i9"', body: _ips(1100)),
      };
      expect(await list().update(), RuBlockedUpdate.updated);
      expect(requests, [
        (RuBlockedList.domainsUrl, null),
        (RuBlockedList.ipsUrl, null),
      ]);
      expect(await list().installed(), isTrue);
    });
  });
}
