import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/profiles/catalog.dart';
import 'package:onexray/service/connect/routing/profiles/profile.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';

final _regions = RegionCatalog.fromJson(
  {
    'geosite': {
      'RU': ['CATEGORY-RU'],
    },
    'geoip': {
      'RU': ['RU'],
    },
  },
  geositeCodes: ['CATEGORY-RU'],
  geoipCodes: ['RU'],
);

const _context = TrafficProfileContext(
  geositeCodes: {
    'PRIVATE',
    'CATEGORY-RU',
    'CATEGORY-ADS-ALL',
    'DISCORD',
    'YOUTUBE',
    'CATEGORY-GAMES',
  },
  geoipCodes: {'PRIVATE', 'RU'},
  ruBlocked: true,
);

RuntimeOptions _options({
  ConnectionPlatform platform = ConnectionPlatform.windows,
  bool lan = false,
}) => RuntimeOptions(
  platform: platform,
  sessionDirectory: '/unused-session',
  metricsPort: 18186,
  socksPort: 18187,
  interfaceName: platform == ConnectionPlatform.windows ? 'Ethernet' : '',
  lanProxyEnabled: lan,
  lanProxyUser: 'hyper',
  lanProxyPassword: 'lan-secret',
);

ResolvedServer _node(int id) => ResolvedServer(
  id: id,
  sourceId: 1,
  outbound: {'tag': 'node', 'protocol': 'freedom'},
);

Map<String, dynamic> _compile(
  ConnectionSettings settings, {
  RuntimeOptions? options,
  TrafficProfileContext context = _context,
}) => ConnectionCompiler.compile(
  settings: settings,
  entries: [_node(1)],
  regions: _regions,
  options: options ?? _options(),
  profileContext: context,
).config;

List<Map<String, dynamic>> _rules(Map<String, dynamic> config) => [
  for (final rule in config['routing']['rules'] as List)
    rule as Map<String, dynamic>,
];

List<String> _tags(Map<String, dynamic> config) => [
  for (final rule in _rules(config)) rule['ruleTag'] as String,
];

Map<String, dynamic> _rule(Map<String, dynamic> config, String tag) =>
    _rules(config).singleWhere((rule) => rule['ruleTag'] == tag);

ConnectionSettings _settings(
  TrafficMode mode,
  List<String> enabled, {
  List<TrafficProfile> custom = const [],
  SmartRoutingSettings? smart,
}) => ConnectionSettings(
  trafficMode: mode,
  smart: smart ?? SmartRoutingSettings(directRegions: const ['RU']),
  profiles: TrafficProfileSettings(enabled: enabled, custom: custom),
);

void main() {
  test('profiles sit between Smart ad blocking and its direct regions', () {
    final config = _compile(
      _settings(
        TrafficMode.smart,
        [TrafficProfiles.ruBlocked, TrafficProfiles.games],
        smart: SmartRoutingSettings(
          directRegions: const ['RU'],
          blockAds: true,
        ),
      ),
    );
    final tags = _tags(config);
    final ads = tags.indexOf('app-smart-ads');
    final vpn = tags.indexOf('app-profiles-proxy-domain');
    final direct = tags.indexOf('app-profiles-direct-domain');
    final regions = tags.indexOf('app-smart-direct-domain');
    expect(ads, lessThan(vpn));
    expect(vpn, lessThan(direct));
    expect(direct, lessThan(regions));
    expect(_rule(config, 'app-profiles-proxy-domain'), {
      'domain': [TrafficProfiles.ruBlockedDomains],
      'balancerTag': 'proxy',
      'ruleTag': 'app-profiles-proxy-domain',
    });
    expect(_rule(config, 'app-profiles-proxy-ip')['ip'], [
      TrafficProfiles.ruBlockedIps,
    ]);
    expect(
      _rule(config, 'app-profiles-direct-domain')['outboundTag'],
      'direct',
    );
    expect(config['routing']['domainStrategy'], 'IPIfNonMatch');
    // The lists are App-managed: no custom Geodata dependency to check.
    expect(geoDataReferences(config), isEmpty);
  });

  test('Selective keeps the LAN direct, routes profiles, and leaves the rest direct', () {
    final config = _compile(
      _settings(TrafficMode.selective, [
        TrafficProfiles.discord,
        TrafficProfiles.games,
      ]),
      options: _options(lan: true),
    );
    final tags = _tags(config);
    expect(tags, contains('app-selective-private-domain'));
    expect(
      tags.indexOf('app-selective-private-ip'),
      lessThan(tags.indexOf('app-profiles-proxy-process')),
    );
    // Direct profiles change nothing when everything else leaves direct.
    expect(tags, isNot(contains('app-profiles-direct-domain')));
    expect(tags, isNot(contains('app-profiles-lan-ip')));
    expect(tags.last, TrafficProfiles.selectiveDirectTag);
    expect(_rule(config, TrafficProfiles.selectiveDirectTag), {
      'inboundTag': ['tunIn', 'app-lan-proxy'],
      'outboundTag': 'direct',
      'ruleTag': TrafficProfiles.selectiveDirectTag,
    });
    expect(_rule(config, 'app-profiles-proxy-process')['process'], [
      'Discord.exe',
      'DiscordPTB.exe',
      'DiscordCanary.exe',
    ]);
    // Smart's region lists do not apply.
    expect(tags, isNot(contains('app-smart-direct-domain')));
  });

  test('Selective resolves unmatched names through the direct resolver', () {
    final config = _compile(
      _settings(TrafficMode.selective, [TrafficProfiles.youtube]),
    );
    final servers = [
      for (final server in config['dns']['servers'] as List)
        server as Map<String, dynamic>,
    ];
    final proxy = servers.firstWhere(
      (server) => server['tag'] == 'app-dns-proxy',
    );
    expect(proxy['domains'], ['geosite:YOUTUBE']);
    final fallback = servers.last;
    expect(fallback['tag'], 'app-dns-direct');
    expect(fallback.containsKey('domains'), isFalse);
  });

  test('Selective fakes only the names profiles send through the VPN', () {
    final config = _compile(
      _settings(TrafficMode.selective, [
        TrafficProfiles.youtube,
      ], smart: SmartRoutingSettings(fakeDns: true)),
    );
    final servers = [
      for (final server in config['dns']['servers'] as List)
        server as Map<String, dynamic>,
    ];
    final fake = servers.singleWhere(
      (server) => server['tag'] == 'app-dns-fake',
    );
    expect(fake['domains'], ['geosite:YOUTUBE']);
    expect(servers.last['tag'], 'app-dns-direct');
    expect(config['fakedns'], isNotEmpty);
  });

  test('Selective with leastPing never adds the proxy catch-all', () {
    final settings = ConnectionSettings(
      trafficMode: TrafficMode.selective,
      smart: SmartRoutingSettings.fromJson({
        'entryCount': 2,
        'selection': {'type': 'leastPing'},
      }),
      profiles: const TrafficProfileSettings(enabled: [TrafficProfiles.ai]),
    );
    final config = ConnectionCompiler.compile(
      settings: settings,
      entries: [_node(1), _node(2)],
      regions: _regions,
      options: _options(),
      profileContext: _context,
    ).config;
    expect(_tags(config), isNot(contains('app-proxy-catchall')));
    expect(_tags(config).last, TrafficProfiles.selectiveDirectTag);
  });

  test('All VPN only takes the profiles that send traffic direct', () {
    final plain = _compile(_settings(TrafficMode.allVpn, const []));
    expect(plain['routing']['domainStrategy'], 'AsIs');
    expect(_tags(plain), isNot(contains('app-direct-dns')));

    final config = _compile(
      _settings(TrafficMode.allVpn, [
        TrafficProfiles.ruBlocked,
        TrafficProfiles.torrents,
      ]),
    );
    final tags = _tags(config);
    expect(tags, isNot(contains('app-profiles-proxy-domain')));
    expect(_rule(config, 'app-profiles-direct-protocol')['protocol'], [
      'bittorrent',
    ]);
    expect(tags, contains('app-direct-dns'));
    expect(config['routing']['domainStrategy'], 'AsIs');

    final addresses = _compile(
      _settings(
        TrafficMode.allVpn,
        const ['custom-1'],
        custom: [
          TrafficProfile(
            id: 'custom-1',
            name: 'Office',
            action: TrafficProfileAction.direct,
            ips: const ['203.0.113.0/24'],
          ),
        ],
      ),
    );
    expect(addresses['routing']['domainStrategy'], 'IPIfNonMatch');
  });

  test('program rules exist only on desktop and keep the LAN out of them', () {
    final desktop = _compile(
      _settings(TrafficMode.smart, [TrafficProfiles.messengers]),
    );
    final tags = _tags(desktop);
    expect(
      tags.indexOf('app-profiles-lan-ip'),
      lessThan(tags.indexOf('app-profiles-proxy-process')),
    );
    final android = _compile(
      _settings(TrafficMode.smart, [TrafficProfiles.messengers]),
      options: _options(platform: ConnectionPlatform.android),
    );
    expect(_tags(android), isNot(contains('app-profiles-proxy-process')));
    expect(_tags(android), isNot(contains('app-profiles-lan-ip')));
    expect(
      _rule(android, 'app-profiles-proxy-ip')['ip'],
      contains('149.154.160.0/20'),
    );
  });

  test('missing categories and lists drop out of built-in profiles', () {
    final config = _compile(
      _settings(TrafficMode.smart, [
        TrafficProfiles.ai,
        TrafficProfiles.ruBlocked,
      ]),
      context: const TrafficProfileContext(
        geositeCodes: {'OPENAI', 'PRIVATE'},
        geoipCodes: {'PRIVATE'},
      ),
    );
    expect(_rule(config, 'app-profiles-proxy-domain')['domain'], [
      'geosite:OPENAI',
    ]);
    expect(_tags(config), isNot(contains('app-profiles-proxy-ip')));
  });

  test('one rule per direction and kind, the LAN guard first', () {
    final settings = _settings(
      TrafficMode.custom,
      const ['custom-1'],
      custom: [
        TrafficProfile(
          id: 'custom-1',
          name: 'Work',
          action: TrafficProfileAction.proxy,
          domains: const ['domain:corp.example'],
          processes: const ['C:/Tools/agent.exe'],
        ),
      ],
    );
    final rules = TrafficProfiles.rules(
      settings.profiles,
      context: _context.withProcesses(true),
    );
    expect(
      [for (final rule in rules) rule.ruleTag],
      [
        'app-profiles-lan-domain',
        'app-profiles-lan-ip',
        'app-profiles-proxy-domain',
        'app-profiles-proxy-process',
      ],
    );
    expect(rules.last.process, ['C:/Tools/agent.exe']);
  });

  test('custom routes run their own rules after the profiles', () {
    final config = ConnectionCompiler.compile(
      settings: _settings(TrafficMode.custom, [TrafficProfiles.youtube]),
      entries: [_node(1)],
      custom: RoutingProfileState(
        name: 'Custom',
        rules: [
          RoutingRuleState(
            domain: ['domain:youtube.com'],
            action: RoutingRuleAction.direct,
          ),
        ],
      ),
      regions: _regions,
      options: _options(),
      profileContext: _context,
    ).config;
    final tags = _tags(config);
    expect(
      tags.indexOf('app-profiles-proxy-domain'),
      lessThan(tags.indexOf('app-custom-0')),
    );
  });

  test('no profiles leave every mode as before', () {
    for (final mode in [TrafficMode.smart, TrafficMode.allVpn]) {
      final settings = ConnectionSettings(
        trafficMode: mode,
        smart: SmartRoutingSettings(directRegions: const ['RU']),
      );
      expect(settings.toJson().containsKey('profiles'), isFalse);
      final config = _compile(settings);
      expect(
        _tags(config).where((tag) => tag.startsWith('app-profiles')),
        isEmpty,
      );
    }
  });
}
