import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/l10n/localizations/app_localizations_en.dart';
import 'package:onexray/l10n/localizations/app_localizations_ru.dart';
import 'package:onexray/service/diagnostics/privacy.dart';
import 'package:onexray/service/diagnostics/report.dart';
import 'package:onexray/service/diagnostics/settings.dart';
import 'package:onexray/service/diagnostics/summary.dart';
import 'package:onexray/service/diagnostics/text.dart';

import 'fixtures.dart';

void main() {
  group('NetworkReport', () {
    test('reads libXray reports and tolerates missing parts', () {
      final report = NetworkReport.fromJson(whitelistReport());
      expect(report.supported, isTrue);
      expect(report.network!.interface!.kind, InterfaceKind.usbTethering);
      expect(report.network!.provider!.asn, 25159);
      expect(report.sites.map((site) => site.id), contains('youtube'));
      expect(
        report.hosting.firstWhere((h) => h.id == 'hetzner-ash').label,
        'Hetzner US',
      );
      expect(
        report.hosting
            .firstWhere((h) => h.id == 'hetzner-ash')
            .openWithWhiteName,
        isTrue,
      );
      expect(report.dns!.resolvers[1].forged.map((name) => name.name), [
        'rutracker.org',
        'www.youtube.com',
      ]);

      final empty = NetworkReport.fromJson({'version': 2, 'sites': 'nonsense'});
      expect(empty.supported, isFalse);
      expect(empty.sites, isEmpty);
      expect(empty.facts, isNull);
    });
  });

  group('NetworkReportSettings', () {
    test('defaults keep the address to its network', () {
      const settings = NetworkReportSettings();
      expect(settings.address, ReportAddressMode.network);
      expect(settings.location, ReportLocationMode.country);
      expect(settings.adapter, isFalse);
      expect(settings.sections, ReportSection.all);
    });

    test('a broken value falls back alone', () {
      final settings = NetworkReportSettings.fromJson({
        'address': 'everything',
        'provider': false,
        'checkUdp': 'yes',
        'extraSites': [
          'Example.ORG',
          'https://news.example.com/path?q',
          'bad host',
          'example.org',
        ],
      });
      expect(settings.address, ReportAddressMode.network);
      expect(settings.provider, isFalse);
      expect(settings.checkUdp, isTrue);
      expect(settings.extraSites, ['example.org', 'news.example.com']);
      expect(
        NetworkReportSettings.fromJson(settings.toJson()).toJson(),
        settings.toJson(),
      );
    });

    test('sites are cut to the limit', () {
      final sites = NetworkReportSettings.normalizeSites([
        for (var index = 0; index < 30; index++) 'site$index.example',
      ]);
      expect(sites, hasLength(NetworkReportSettings.maxExtraSites));
    });

    test('turning checks off leaves the network section', () {
      const settings = NetworkReportSettings(
        checkDns: false,
        checkSites: false,
        checkHosting: false,
        checkUdp: false,
      );
      expect(settings.sections, [ReportSection.network]);
      expect(
        const NetworkReportSettings(saveTraffic: true).maxBytes,
        64 * 1024,
      );
    });
  });

  group('redactReport', () {
    test('masks the address to its network by default', () {
      final report = redactReport(
        whitelistReport(),
        const NetworkReportSettings(),
      );
      final network = report['network'] as Map<String, dynamic>;
      final ipv4 = network['ipv4'] as Map<String, dynamic>;
      expect(ipv4['ip'], '198.51.100.0/24');
      expect(ipv4['holder'], isNotEmpty);
      expect(ipv4.containsKey('city'), isFalse);
      final adapter = network['interface'] as Map<String, dynamic>;
      expect(adapter.containsKey('name'), isFalse);
      expect(adapter.containsKey('addresses'), isFalse);
      expect(adapter['kind'], 'usb_tethering');
      expect(report.containsKey('interface'), isFalse);
      expect(report.containsKey('client'), isFalse);
    });

    test('hides what the settings turn off', () {
      final report = redactReport(
        whitelistReport(),
        const NetworkReportSettings(
          address: ReportAddressMode.hidden,
          provider: false,
          location: ReportLocationMode.hidden,
          connectionType: false,
          dnsServers: false,
        ),
        client: const ReportClient(app: 'HYPER CLIENT 1', system: 'test'),
      );
      final network = report['network'] as Map<String, dynamic>;
      final ipv4 = network['ipv4'] as Map<String, dynamic>;
      expect(ipv4.keys, isEmpty);
      expect((network['interface'] as Map).containsKey('kind'), isFalse);
      expect((network['interface'] as Map).containsKey('dns'), isFalse);
      final dns = report['dns'] as Map<String, dynamic>;
      expect(dns.containsKey('system'), isFalse);
      expect(((dns['resolvers'] as List).first as Map)['address'], '');
      expect(report['client'], {'app': 'HYPER CLIENT 1', 'system': 'test'});
    });

    test('keeps everything when asked and never edits the source', () {
      final source = whitelistReport();
      final report = redactReport(
        source,
        const NetworkReportSettings(
          address: ReportAddressMode.full,
          location: ReportLocationMode.city,
          adapter: true,
        ),
      );
      final ipv4 = (report['network'] as Map)['ipv4'] as Map;
      expect(ipv4['ip'], '198.51.100.237');
      expect(ipv4['city'], 'Moscow');
      expect(report['interface'], 'Ethernet 4');
      redactReport(
        source,
        const NetworkReportSettings(address: ReportAddressMode.hidden),
      );
      expect(
        ((source['network'] as Map)['ipv4'] as Map)['ip'],
        '198.51.100.237',
      );
    });

    test('maskAddress keeps the network of both families', () {
      expect(maskAddress('203.0.113.77'), '203.0.113.0/24');
      expect(maskAddress('2001:db8:4192:8df1::77'), '2001:db8:4192::/48');
      expect(maskAddress('not an address'), '');
    });
  });

  group('summarizeReport', () {
    test('a white list of names suggests a borrowed name and a relay', () {
      final summary = summarizeReport(
        NetworkReport.fromJson(whitelistReport()),
      );
      expect(summary.mode, NetworkMode.sniWhitelist);
      final reality = summary.advice.firstWhere(
        (item) => item.code == AdviceCode.realityWhite,
      );
      expect(reality.kind, AdviceKind.works);
      expect(reality.names, ['mail.ru', 'ya.ru']);
      expect(reality.items, ['Hetzner US']);
      final relay = summary.advice.firstWhere(
        (item) => item.code == AdviceCode.relay,
      );
      expect(relay.items, ['Selectel RU', 'Yandex Cloud RU']);
      expect(
        summary.advice
            .firstWhere((item) => item.code == AdviceCode.tlsBlocked)
            .items,
        ['Hetzner DE', 'Hetzner US', 'Vultr NL'],
      );
      expect(
        summary.of(AdviceKind.fails).map((item) => item.code),
        contains(AdviceCode.cdnBlocked),
      );
      expect(
        summary.advice
            .firstWhere((item) => item.code == AdviceCode.noSni)
            .items,
        ['Cloudflare', 'Vultr NL'],
      );
      expect(
        summary.advice.any((item) => item.code == AdviceCode.udpPartial),
        isTrue,
      );
      // Tried, and nothing opened: bypass tools would not help here.
      expect(
        summary.advice.any((item) => item.code == AdviceCode.bypassUseless),
        isTrue,
      );
      expect(
        summary.advice.any((item) => item.code == AdviceCode.fragment),
        isFalse,
      );
    });

    test('a white list by address leaves only a relay', () {
      final report = NetworkReport.fromJson({
        ...whitelistReport(),
        'sni': {'filtered': false},
        'hosting': [
          hosting('hetzner-fsn', 'Hetzner', 'tls_blocked', country: 'DE'),
          hosting(
            'yandex-cloud',
            'Yandex Cloud',
            'ok',
            country: 'RU',
            foreign: false,
          ),
        ],
        'facts': {'mode': 'whitelist', 'udp': 'blocked', 'bypassTried': 4},
      });
      final summary = summarizeReport(report);
      expect(summary.mode, NetworkMode.whitelist);
      expect(
        summary.advice
            .firstWhere((item) => item.code == AdviceCode.relay)
            .items,
        ['Yandex Cloud RU'],
      );
      for (final code in [
        AdviceCode.realityWhite,
        AdviceCode.fragment,
        AdviceCode.tls,
      ]) {
        expect(summary.advice.any((item) => item.code == code), isFalse);
      }
      expect(
        summary.advice.any((item) => item.code == AdviceCode.bypassUseless),
        isTrue,
      );
      expect(
        ReportText.render(AppLocalizationsRu(), report),
        contains('Белые списки по адресам: Отвечают только разрешённые сети'),
      );
    });

    test('a filtered network lists what works and the evidence', () {
      final summary = summarizeReport(NetworkReport.fromJson(filteredReport()));
      expect(summary.mode, NetworkMode.filtered);
      expect(
        summary.advice.firstWhere((item) => item.code == AdviceCode.tls).items,
        ['Scaleway FR'],
      );
      expect(summary.advice.any((item) => item.code == AdviceCode.cdn), isTrue);
      expect(summary.advice.any((item) => item.code == AdviceCode.udp), isTrue);
      expect(
        summary.advice
            .firstWhere((item) => item.code == AdviceCode.frozen)
            .items,
        ['OVH FR'],
      );
      expect(
        summary.advice
            .firstWhere((item) => item.code == AdviceCode.dnsLoss)
            .percent,
        20,
      );
      expect(
        summary.advice
            .firstWhere((item) => item.code == AdviceCode.split)
            .items,
        ['TikTok'],
      );
      // Signal's hello got through but its data stalled: not counted.
      final fragment = summary.advice.firstWhere(
        (item) => item.code == AdviceCode.fragment,
      );
      expect(fragment.kind, AdviceKind.works);
      expect(fragment.items, ['TikTok']);
      expect(
        summary.advice
            .firstWhere((item) => item.code == AdviceCode.fragmentHosting)
            .items,
        ['Vultr NL'],
      );
      expect(
        summary.advice.any((item) => item.code == AdviceCode.bypassUseless),
        isFalse,
      );
      expect(
        summary.advice.firstWhere((item) => item.code == AdviceCode.geo).items,
        ['ChatGPT'],
      );
      expect(
        summary.advice.any((item) => item.code == AdviceCode.realityWhite),
        isFalse,
      );
      expect(
        summary.advice.any((item) => item.code == AdviceCode.relay),
        isFalse,
      );
    });
  });

  group('ReportText', () {
    test('renders the shared text in the App language', () {
      final report = NetworkReport.fromJson(
        redactReport(
          whitelistReport(),
          const NetworkReportSettings(),
          client: const ReportClient(
            app: 'HYPER CLIENT 0.1.0',
            system: 'windows',
          ),
        ),
      );
      final text = ReportText.render(AppLocalizationsRu(), report);
      expect(text, startsWith('HYPER CLIENT · отчёт о сети · '));
      expect(
        text,
        contains('USB-модем · PJSC MegaFon · AS25159 · RU · 198.51.100.0/24'),
      );
      expect(text, contains('Белый список имён серверов: Адреса отвечают'));
      expect(text, contains('Проходят: mail.ru, ya.ru'));
      expect(text, contains('  Только разрешённые имена: YouTube, GitHub'));
      expect(
        text,
        contains('  Hetzner US: Только разрешённые имена → ya.ru ✓'),
      );
      expect(text, contains('REALITY с именем mail.ru, ya.ru на Hetzner US'));
      expect(text, contains('Приложение: HYPER CLIENT 0.1.0 · windows'));
      expect(text, isNot(contains('198.51.100.237')));
      expect(text, isNot(contains('Ethernet 4')));
    });

    test('names the network resolver in the App language', () {
      final report = NetworkReport.fromJson({
        ...filteredReport(),
        'dns': {
          'resolvers': [
            {
              'id': 'system',
              'name': 'System',
              'address': '10.0.1.1',
              'system': true,
              'status': 'ok',
              'names': [
                {'name': 'meduza.io', 'status': 'spoofed'},
              ],
            },
          ],
        },
      });
      final en = AppLocalizationsEn();
      final dns = summarizeReport(report).advice
          .firstWhere((item) => item.code == AdviceCode.dns);
      expect(ReportText.advice(en, dns), contains("Network's DNS"));
      expect(
        ReportText.dnsSummary(en, report.dns!),
        "Spoofed by Network's DNS 10.0.1.1",
      );
    });

    test('every status code has its own label', () {
      final en = AppLocalizationsEn();
      const codes = [
        ReportStatus.ok,
        ReportStatus.timeout,
        ReportStatus.reset,
        ReportStatus.refused,
        ReportStatus.unreachable,
        ReportStatus.closed,
        ReportStatus.alert,
        ReportStatus.certInvalid,
        ReportStatus.frozen,
        ReportStatus.stalled,
        ReportStatus.slow,
        ReportStatus.error,
        ReportStatus.skipped,
        ReportStatus.spoofed,
        ReportStatus.injected,
        ReportStatus.nxdomain,
        ReportStatus.empty,
        ReportStatus.dnsOnly,
        ReportStatus.ipBlocked,
        ReportStatus.sniBlocked,
        ReportStatus.sniWhitelist,
        ReportStatus.noSniOnly,
        ReportStatus.tlsBlocked,
        ReportStatus.mitm,
        ReportStatus.geo,
        ReportStatus.blocked,
        ReportStatus.partial,
      ];
      final labels = {for (final code in codes) ReportText.status(en, code)};
      expect(labels, hasLength(codes.length));
      expect(ReportText.status(en, 'future_code'), 'future_code');
    });

    test('provider drops the AS handle and the country suffix', () {
      expect(
        ReportText.provider(
          const ReportExternal(
            holder: 'MOSCOW-AS - JSC "ER-Telecom Holding", RU',
            asn: 31363,
            country: 'RU',
          ),
        ),
        'JSC "ER-Telecom Holding" · AS31363 · RU',
      );
    });
  });
}
