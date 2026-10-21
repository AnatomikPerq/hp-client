import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/connect/routing/profiles/catalog.dart';
import 'package:path/path.dart' as p;

/// What is installed for the ru-blocked profile.
final class RuBlockedStatus {
  final int domainCount;
  final int ipCount;

  /// When this data was fetched from runetfreedom (by the build for the
  /// bundled copy) and when the App last asked whether it changed.
  final DateTime fetchedAt;
  final DateTime? checkedAt;
  final bool bundled;
  final String? domainsEtag;
  final String? ipsEtag;

  const RuBlockedStatus({
    required this.domainCount,
    required this.ipCount,
    required this.fetchedAt,
    this.checkedAt,
    required this.bundled,
    this.domainsEtag,
    this.ipsEtag,
  });

  factory RuBlockedStatus.fromJson(Map<String, dynamic> json) {
    DateTime? time(Object? value) => value is int && value > 0
        ? DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true)
        : null;
    final domains = json['domains'] as Map<String, dynamic>? ?? const {};
    final ips = json['ips'] as Map<String, dynamic>? ?? const {};
    return RuBlockedStatus(
      domainCount: domains['count'] as int? ?? 0,
      ipCount: ips['count'] as int? ?? 0,
      fetchedAt: time(json['fetchedAt']) ?? DateTime.utc(1970),
      checkedAt: time(json['checkedAt']),
      bundled: json['bundled'] as bool? ?? false,
      domainsEtag: domains['etag'] as String?,
      ipsEtag: ips['etag'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    int seconds(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;
    return {
      'domains': {'count': domainCount, 'etag': ?domainsEtag},
      'ips': {'count': ipCount, 'etag': ?ipsEtag},
      'fetchedAt': seconds(fetchedAt),
      if (checkedAt != null) 'checkedAt': seconds(checkedAt!),
      'bundled': bundled,
    };
  }
}

/// The result of asking runetfreedom for newer lists.
enum RuBlockedUpdate { updated, unchanged }

/// The runetfreedom "blocked in Russia" category (antifilter community and
/// re:filter) behind the ru-blocked profile. A copy fetched by the release
/// build ships in `assets/ru_blocked/`; updates ask for each list with its
/// ETag, so an unchanged list costs one 304 response and a changed one only
/// that category (about 0.8 MB compressed), never runetfreedom's 90 MB of
/// complete geosite/geoip files.
///
/// The lists become `ru-blocked-domains.dat` and `ru-blocked-ips.dat` in the
/// flat Geodata directory, outside the Geodata table: a lost database or a
/// data clear removes them like any file without a manifest, and the next
/// use installs the bundled copy again.
final class RuBlockedList {
  static final instance = RuBlockedList();

  static const domainsUrl =
      'https://raw.githubusercontent.com/runetfreedom/russia-blocked-geosite/release/ru-blocked.txt';
  static const ipsUrl =
      'https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/release/text/ru-blocked.txt';
  static const bundleDir = 'assets/ru_blocked';
  static const manifestFile = 'ru-blocked.json';

  /// A list this short is an error page or a broken release, not data.
  static const minimumEntries = 1000;
  static const _limit = 64 * 1024 * 1024;

  final String Function() _directory;
  final Future<ByteData> Function(String) _loadAsset;
  final Future<T> Function<T>(Future<T> Function()) _withFiles;
  final Future<String> Function(String directory, String name, String type)
  _count;
  final Future<({int status, String? etag, String body})> Function(
    String url,
    String? etag,
  )
  _fetch;
  final DateTime Function() _now;
  Future<RuBlockedUpdate>? _updating;

  RuBlockedList({
    String Function()? directory,
    Future<ByteData> Function(String)? loadAsset,
    Future<T> Function<T>(Future<T> Function())? withFiles,
    Future<String> Function(String directory, String name, String type)? count,
    Future<({int status, String? etag, String body})> Function(
      String url,
      String? etag,
    )?
    fetch,
    DateTime Function()? now,
  }) : _directory = directory ?? (() => VpnConstants.datDir),
       _loadAsset = loadAsset ?? rootBundle.load,
       _withFiles = withFiles ?? GeoDataService().withFiles,
       _count = count ?? _countNative,
       _fetch = fetch ?? _fetchText,
       _now = now ?? DateTime.now;

  String get _root => _directory();

  Future<RuBlockedStatus?> status() => _withFiles(_readStatus);

  /// Whether both files are present; the compiler only references them then.
  Future<bool> installed() =>
      _withFiles(() async => await _installed() != null);

  /// Installs the bundled lists when nothing (or an older copy than the
  /// bundle) is installed. Local only: no network.
  Future<void> ensureInstalled() => _withFiles(() async {
    final current = await _installed();
    final bundle = await _bundle();
    if (bundle == null) {
      if (current != null) return;
      throw const AppFailure(
        FailureCategory.configuration,
        'ruBlockedUnavailable',
        cause: 'The ru-blocked list is neither installed nor bundled',
      );
    }
    if (current != null && !current.fetchedAt.isBefore(bundle.fetchedAt)) {
      return;
    }
    await _install(
      domains: bundle.domains,
      ips: bundle.ips,
      status: RuBlockedStatus(
        domainCount: 0,
        ipCount: 0,
        fetchedAt: bundle.fetchedAt,
        checkedAt: current?.checkedAt,
        bundled: true,
        domainsEtag: bundle.domainsEtag,
        ipsEtag: bundle.ipsEtag,
      ),
    );
  });

  /// Asks runetfreedom for lists newer than the installed ones. Concurrent
  /// callers share one request; a failure leaves the installed copy.
  Future<RuBlockedUpdate> update() =>
      _updating ??= _update().whenComplete(() => _updating = null);

  Future<RuBlockedUpdate> _update() async {
    try {
      await ensureInstalled();
    } on AppFailure {
      // Nothing bundled: the download below installs the first copy.
    }
    final current = await _withFiles(_installed);
    final domains = await _fetch(domainsUrl, current?.domainsEtag);
    final ips = await _fetch(ipsUrl, current?.ipsEtag);
    final now = _now().toUtc();
    if (current != null && domains.status == 304 && ips.status == 304) {
      await _withFiles(
        () => _writeStatus(
          RuBlockedStatus(
            domainCount: current.domainCount,
            ipCount: current.ipCount,
            fetchedAt: current.fetchedAt,
            checkedAt: now,
            bundled: current.bundled,
            domainsEtag: current.domainsEtag,
            ipsEtag: current.ipsEtag,
          ),
        ),
      );
      return RuBlockedUpdate.unchanged;
    }
    // A list that did not change keeps its installed file.
    await _withFiles(
      () => _install(
        domains: domains.status == 304 ? null : domains.body,
        ips: ips.status == 304 ? null : ips.body,
        status: RuBlockedStatus(
          domainCount: current?.domainCount ?? 0,
          ipCount: current?.ipCount ?? 0,
          fetchedAt: now,
          checkedAt: now,
          bundled: false,
          domainsEtag: domains.etag ?? current?.domainsEtag,
          ipsEtag: ips.etag ?? current?.ipsEtag,
        ),
      ),
    );
    return RuBlockedUpdate.updated;
  }

  Future<RuBlockedStatus?> _installed() async {
    for (final name in [
      TrafficProfiles.ruBlockedDomainFile,
      TrafficProfiles.ruBlockedIpFile,
    ]) {
      final file = File(p.join(_root, name));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() == 0) {
        return null;
      }
    }
    return _readStatus();
  }

  Future<RuBlockedStatus?> _readStatus() async {
    final file = File(p.join(_root, manifestFile));
    if (!await file.exists()) return null;
    try {
      return RuBlockedStatus.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> _writeStatus(RuBlockedStatus status) async {
    final file = File(p.join(_root, manifestFile));
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(status.toJson()), flush: true);
    await temporary.rename(file.path);
  }

  Future<
    ({
      String domains,
      String ips,
      DateTime fetchedAt,
      String? domainsEtag,
      String? ipsEtag,
    })?
  >
  _bundle() async {
    try {
      final manifest = jsonDecode(
        utf8.decode(
          (await _loadAsset('$bundleDir/manifest.json')).buffer.asUint8List(),
        ),
      ) as Map<String, dynamic>;
      Future<String> text(String name) async {
        final data = await _loadAsset('$bundleDir/$name');
        return utf8.decode(
          gzip.decode(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          ),
        );
      }

      return (
        domains: await text('domains.txt.gz'),
        ips: await text('ips.txt.gz'),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(
          (manifest['fetchedAt'] as int) * 1000,
          isUtc: true,
        ),
        domainsEtag:
            (manifest['domains'] as Map<String, dynamic>?)?['etag'] as String?,
        ipsEtag: (manifest['ips'] as Map<String, dynamic>?)?['etag'] as String?,
      );
    } on FlutterError {
      return null; // A development build without the fetched lists.
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Encodes and checks the given lists in a staging directory beside the
  /// Geodata root, then moves them in; a null list keeps its installed file
  /// and the count in [status]. Runs inside the Geodata file queue.
  Future<void> _install({
    required String? domains,
    required String? ips,
    required RuBlockedStatus status,
  }) async {
    final encoded = await Isolate.run(
      () => (
        domains: domains == null
            ? null
            : RuBlockedEncoding.sites(
                TrafficProfiles.ruBlockedCode,
                RuBlockedEncoding.parseDomains(domains),
              ),
        ips: ips == null
            ? null
            : RuBlockedEncoding.ips(
                TrafficProfiles.ruBlockedCode,
                RuBlockedEncoding.parseIps(ips),
              ),
      ),
    );
    if ((encoded.domains?.count ?? minimumEntries) < minimumEntries ||
        (encoded.ips?.count ?? minimumEntries) < minimumEntries) {
      throw const AppFailure(
        FailureCategory.input,
        'ruBlockedInvalid',
        cause: 'The ru-blocked list is too short',
      );
    }
    final root = Directory(_root);
    await root.create(recursive: true);
    final stage = Directory(p.join(p.dirname(root.path), '.hp-ru-blocked'));
    if (await stage.exists()) await stage.delete(recursive: true);
    await stage.create();
    try {
      final files = {
        if (encoded.domains case final data?)
          TrafficProfiles.ruBlockedDomainFile: (data, 'domain'),
        if (encoded.ips case final data?)
          TrafficProfiles.ruBlockedIpFile: (data, 'ip'),
      };
      for (final MapEntry(key: name, value: (data, type)) in files.entries) {
        await File(p.join(stage.path, name))
            .writeAsBytes(data.bytes, flush: true);
        final error = await _count(
          stage.path,
          p.basenameWithoutExtension(name),
          type,
        );
        if (error.isNotEmpty) {
          throw AppFailure(
            FailureCategory.input,
            'ruBlockedInvalid',
            cause: error,
          );
        }
      }
      for (final name in files.keys) {
        await File(p.join(stage.path, name)).rename(p.join(root.path, name));
      }
      await _writeStatus(
        RuBlockedStatus(
          domainCount: encoded.domains?.count ?? status.domainCount,
          ipCount: encoded.ips?.count ?? status.ipCount,
          fetchedAt: status.fetchedAt,
          checkedAt: status.checkedAt,
          bundled: status.bundled,
          domainsEtag: status.domainsEtag,
          ipsEtag: status.ipsEtag,
        ),
      );
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }

  static Future<String> _countNative(
    String directory,
    String name,
    String type,
  ) => AppHostApi().countGeoData(
    CountGeoDataRequest(name, type, datDir: directory),
  );

  static Future<({int status, String? etag, String body})> _fetchText(
    String url,
    String? etag,
  ) async {
    await NetClient().asyncInit();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        NetClient().downloadUserAgent,
      );
      if (etag != null) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode == HttpStatus.notModified) {
        await response.drain<void>();
        return (status: 304, etag: etag, body: '');
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw AppFailure(
          FailureCategory.network,
          'httpStatus',
          cause: 'HTTP ${response.statusCode}',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        bytes.add(chunk);
        if (bytes.length > _limit) {
          throw const FormatException('The ru-blocked list is too large');
        }
      }
      return (
        status: 200,
        etag: response.headers.value(HttpHeaders.etagHeader),
        body: utf8.decode(bytes.takeBytes(), allowMalformed: true),
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// Xray's geodata protobufs (`GeoSiteList`, `GeoIPList` of
/// xray-core/common/geodata/geodat.proto), written by hand: one category
/// each, fields in the order Go's encoder writes them.
abstract final class RuBlockedEncoding {
  // Domain.Type values.
  static const _substring = 0;
  static const _regex = 1;
  static const _domain = 2;
  static const _full = 3;

  /// runetfreedom writes `domain:` lines; the other v2fly prefixes are read
  /// too. Comments, blanks and attributes are dropped.
  static List<(int, String)> parseDomains(String text) {
    final result = <(int, String)>[];
    final seen = <String>{};
    for (var line in const LineSplitter().convert(text)) {
      line = line.split('#').first.trim();
      final at = line.indexOf(' @');
      if (at >= 0) line = line.substring(0, at).trim();
      if (line.isEmpty) continue;
      var type = _domain;
      var value = line;
      final colon = line.indexOf(':');
      if (colon > 0) {
        type = switch (line.substring(0, colon)) {
          'domain' => _domain,
          'full' => _full,
          'regexp' => _regex,
          'keyword' => _substring,
          _ => -1,
        };
        value = line.substring(colon + 1).trim();
      }
      if (type < 0 || value.isEmpty || value.contains(RegExp(r'\s'))) continue;
      if (type != _regex) value = value.toLowerCase();
      if (seen.add('$type:$value')) result.add((type, value));
    }
    return result;
  }

  static List<(Uint8List, int)> parseIps(String text) {
    final result = <(Uint8List, int)>[];
    final seen = <String>{};
    for (var line in const LineSplitter().convert(text)) {
      line = line.split('#').first.trim();
      if (line.isEmpty) continue;
      final slash = line.indexOf('/');
      final address = InternetAddress.tryParse(
        slash < 0 ? line : line.substring(0, slash),
      );
      if (address == null) continue;
      final bits = address.rawAddress.length * 8;
      final prefix = slash < 0 ? bits : int.tryParse(line.substring(slash + 1));
      if (prefix == null || prefix < 0 || prefix > bits) continue;
      if (seen.add('${address.address}/$prefix')) {
        result.add((address.rawAddress, prefix));
      }
    }
    return result;
  }

  static ({Uint8List bytes, int count}) sites(
    String code,
    List<(int, String)> domains,
  ) {
    final site = BytesBuilder(copy: false);
    _bytes(site, 1, utf8.encode(code));
    for (final (type, value) in domains) {
      final domain = BytesBuilder(copy: false);
      if (type != 0) _varintField(domain, 1, type);
      _bytes(domain, 2, utf8.encode(value));
      _bytes(site, 2, domain.takeBytes());
    }
    final list = BytesBuilder(copy: false);
    _bytes(list, 1, site.takeBytes());
    return (bytes: list.takeBytes(), count: domains.length);
  }

  static ({Uint8List bytes, int count}) ips(
    String code,
    List<(Uint8List, int)> cidrs,
  ) {
    final geoip = BytesBuilder(copy: false);
    _bytes(geoip, 1, utf8.encode(code));
    for (final (ip, prefix) in cidrs) {
      final cidr = BytesBuilder(copy: false);
      _bytes(cidr, 1, ip);
      if (prefix != 0) _varintField(cidr, 2, prefix);
      _bytes(geoip, 2, cidr.takeBytes());
    }
    final list = BytesBuilder(copy: false);
    _bytes(list, 1, geoip.takeBytes());
    return (bytes: list.takeBytes(), count: cidrs.length);
  }

  static void _bytes(BytesBuilder out, int field, List<int> value) {
    _varint(out, field << 3 | 2);
    _varint(out, value.length);
    out.add(value);
  }

  static void _varintField(BytesBuilder out, int field, int value) {
    _varint(out, field << 3);
    _varint(out, value);
  }

  static void _varint(BytesBuilder out, int value) {
    while (value >= 0x80) {
      out.addByte(value & 0x7f | 0x80);
      value >>= 7;
    }
    out.addByte(value);
  }
}
